# Check that the JavaScript model (web/model.js, used by the interactive graph) gives the same
# results as the Julia model in index.jl, over a grid of all controls.
# Run from the repository root:  julia --project=test test/consistency.jl
using Test, PlutoUI, CairoMakie, NodeJS_20_jll

const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "index.jl"))   # defines the model functions and `runtime_columns`

# minimal JSON writer for the numbers, strings, bools and vectors passed to Node
tojs(x::AbstractString) = repr(x)
tojs(x::Bool) = string(x)
tojs(x::Real) = isnan(x) ? "null" : string(Float64(x))
tojs(x::AbstractVector) = "[" * join(tojs.(x), ",") * "]"
tojs(x::NamedTuple) = "{" * join(("\"$k\":" * tojs(v) for (k, v) in pairs(x)), ",") * "}"

cases = vec([
    (; store, heat_pump, store_temperature, inlet_temperature, loss_coefficient, room_temperature, T, F)
        for store in unique(runtime.model), heat_pump in 4:14, store_temperature in 45:5:70,
        inlet_temperature in (10, 13), loss_coefficient in (0, 50, 150), room_temperature in (15, 20),
        T in 37:2:45, F in 3:0.5:10
])

julia_results = map(cases) do c
    table = runtime_table(runtime, c.store, c.inlet_temperature, c.store_temperature, c.heat_pump)
    max_bath_volume(table, c.T, c.F; c.inlet_temperature, c.store_temperature, c.loss_coefficient, c.room_temperature)
end

node_script = """
const BathModel = require($(repr(joinpath(ROOT, "web", "model.js"))));
const rows = $(tojs(runtime_columns));
const cases = $(tojs([collect(Float64, (c.heat_pump, c.store_temperature, c.inlet_temperature,
    c.loss_coefficient, c.room_temperature, c.T, c.F)) for c in cases]));
const stores = $(tojs([c.store for c in cases]));
const out = cases.map(([heatPump, storeTemperature, inletTemperature, lossCoefficient, roomTemperature, T, F], i) => {
    const table = BathModel.runtimeTable(rows, stores[i], inletTemperature, storeTemperature, heatPump);
    const [volume, capped] = BathModel.maxBathVolume(table, T, F,
        { inletTemperature, storeTemperature, lossCoefficient, roomTemperature });
    return (isNaN(volume) ? "NaN" : volume) + " " + (capped ? 1 : 0);
});
process.stdout.write(out.join("\\n"));
"""
script_file = tempname() * ".js"
write(script_file, node_script)
node_results = map(split(read(`$(node()) $script_file`, String), '\n')) do line
    volume, capped = split(line)
    (parse(Float64, volume), capped == "1")
end

# frontier (largest bath within each fill time) on a coarser grid of controls
frontier_times = collect(0.0:0.5:60.0)
frontier_cases = vec([
    (; store, heat_pump, store_temperature, inlet_temperature, loss_coefficient, room_temperature, T)
        for store in unique(runtime.model), heat_pump in 4:14, store_temperature in 45:5:70,
        inlet_temperature in (10, 13), loss_coefficient in (0, 50, 150), room_temperature in (15, 20),
        T in 37:4:45
])
julia_frontiers = map(frontier_cases) do c
    table = runtime_table(runtime, c.store, c.inlet_temperature, c.store_temperature, c.heat_pump)
    bath_frontier(table, c.T, frontier_times; c.inlet_temperature, c.store_temperature,
        c.loss_coefficient, c.room_temperature)
end
frontier_script = """
const BathModel = require($(repr(joinpath(ROOT, "web", "model.js"))));
const rows = $(tojs(runtime_columns));
const times = $(tojs(frontier_times));
const cases = $(tojs([collect(Float64, (c.heat_pump, c.store_temperature, c.inlet_temperature,
    c.loss_coefficient, c.room_temperature, c.T)) for c in frontier_cases]));
const stores = $(tojs([c.store for c in frontier_cases]));
const out = cases.map(([heatPump, storeTemperature, inletTemperature, lossCoefficient, roomTemperature, T], i) => {
    const table = BathModel.runtimeTable(rows, stores[i], inletTemperature, storeTemperature, heatPump);
    const f = BathModel.bathFrontier(table, T, times,
        { inletTemperature, storeTemperature, lossCoefficient, roomTemperature });
    return f.volumes.map((v, k) => (isNaN(v) ? "NaN" : v) + ":" + (f.capped[k] ? 1 : 0)).join(" ");
});
process.stdout.write(out.join("\\n"));
"""
write(script_file, frontier_script)
node_frontiers = map(split(read(`$(node()) $script_file`, String), '\n')) do line
    map(split(line)) do entry
        volume, capped = split(entry, ':')
        (parse(Float64, volume), capped == "1")
    end
end

@testset "JavaScript model matches Julia model" begin
    @test length(node_results) == length(julia_results)
    volumes_match = all(zip(julia_results, node_results)) do ((vj, cj), (vn, cn))
        (isnan(vj) && isnan(vn)) || (isapprox(vj, vn; rtol = 1e-10) && cj == cn)
    end
    @test volumes_match
    @test count(r -> !isnan(r[1]), julia_results) > length(julia_results) ÷ 4   # grid is not all infeasible

    @test length(node_frontiers) == length(julia_frontiers)
    frontiers_match = all(zip(julia_frontiers, node_frontiers)) do ((volumes, capped, _), node)
        all(zip(volumes, capped, node)) do (vj, cj, (vn, cn))
            (isnan(vj) && isnan(vn)) || (isapprox(vj, vn; rtol = 1e-10) && cj == cn)
        end
    end
    @test frontiers_match
end

@testset "frontier physics" begin
    # every feasible line starts at the origin
    @test all(((volumes, _, _),) -> all(isnan, volumes) || volumes[1] == 0, julia_frontiers)
end
