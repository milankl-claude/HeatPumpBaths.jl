# Load the CSVs produced by extract.py into DataFrames
# julia --project=test scripts/load.jl   (from the repository root)
using CSV, DataFrames

const DATA = joinpath(@__DIR__, "..", "data")

models = CSV.read(joinpath(DATA, "models.csv"), DataFrame)
runtime = CSV.read(joinpath(DATA, "runtime.csv"), DataFrame)    # runtime_min is missing when status != "value"
recharge = CSV.read(joinpath(DATA, "recharge.csv"), DataFrame)

# example: run time at 8 L/min, 10°C inlet, 8 kW heat pump, as store temperature × model
example = filter(r -> r.flow_rate_L_per_min == 8 && r.inlet_temperature_C == 10 && r.heat_pump_kW == 8, runtime)
println(unstack(example, :store_temperature_C, :model, :runtime_min))
