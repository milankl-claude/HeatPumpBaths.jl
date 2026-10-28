### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ dd8f12f5-7b13-44c2-aa4c-1648e1d52916
md"""
# How big a bath can a heat pump fill?

A heat pump heats water slowly, so a home without space for a hot water cylinder can instead use a
small, hot store such as Heat Geek's Mini Store, and heat the bath water through it as it runs.
How big a bath can that fill, and how quickly?

**The problem.** A 5 kW heat pump keeping an 80 L Mini Store at 55 °C cannot fill even a small 80 L
bath in winter: the store is too small and its temperature drops too quickly. At 45 °C it manages
about 54 L, and even a lukewarm 37 °C bath stops at about 72 L. The heat the bath loses to the room
plays only a minor role; leaving it out adds about 6 L.

**Solution 1: a bigger heat pump.** With 7 kW instead of 5 kW, the heat pump reheats the store
faster, but a small 80 L bath at 45 °C still takes about 20 minutes. Without that patience, if you want
the bath within 10 minutes, only about 55 L can be filled at a very hot 45 °C, as the heat pump still
isn't quick enough to keep the store hot. The underlying problem is that a 55 °C store is too close
to a 45 °C bath. Furthermore, the heat pump has now been sized for a hot bath in winter, not for
average use, so it is oversized the rest of the year and therefore less efficient, e.g. through
short cycling.

**Solution 2: a hotter store, temporarily.** Raise the store temperature to 70 °C just before a bath.
The store supports this, and so do heat pumps with high-temperature refrigerants such as R290. Even
with the 5 kW heat pump, a very hot 45 °C small bath then fills in 10 minutes, and a standard 120 L
bath at 40 °C in about 20 minutes. A large 150 L bath stays out of reach unless lukewarm (37 °C), but
we won't need that. It does require raising the store temperature before the bath (by hand or on a
timer), and the hotter store loses a little more heat to the loft, but that is far more efficient
than sizing the heat pump for the rarest use of the year.

The graph starts at the problem's settings. Try 7 kW for solution 1, or a store temperature of
70 °C for solution 2.
"""

# ╔═╡ 70d34bee-921e-4dc5-bfce-1b4d290964e4
using CSV, DataFrames, CairoMakie, HypertextLiteral, PlutoUI

# ╔═╡ c81a072b-6b34-422b-83c5-fc2f11c3b539
md"""
## Model

The booklet tables give the run time ``t_\max(F_{40})`` for which the store delivers a flow ``F_{40}`` of
water mixed to **40 °C** from inlet temperature ``T_\text{in}`` (10 or 13 °C). This is the store's
capacity in heat terms: power ``\rho c\,F_{40}\,(40 - T_\text{in})`` for ``t_\max``.

**Filling the bath.** We fill a bath of volume ``V`` at flow ``F``, which takes ``t = V/F``. While it fills,
the bath loses heat to the room at rate ``U\,f(t)\,(T - T_\text{room})``, where ``U`` (W/K) is the
loss coefficient of a full bath (mainly evaporation and conduction into the tub) and ``f`` is the fill
fraction, rising linearly from 0 to 1. The average loss over the fill is therefore half the full-bath loss:

```math
Q_\text{loss} = \tfrac12\, U\,(T - T_\text{room})\, \frac{V}{F}.
```

To still end at ``T`` the tap must deliver water at a hotter temperature ``T_d``:

```math
\rho c\,V\,(T_d - T_\text{in}) = \rho c\,V\,(T - T_\text{in}) + Q_\text{loss}
\quad\Rightarrow\quad
T_d = T + \frac{U\,(T - T_\text{room})}{2\,\rho c\,F}.
```

``T_d`` does not depend on ``V``. In the store's terms that is an **equivalent 40 °C flow**

```math
F_{40} = F\,\frac{T_d - T_\text{in}}{40 - T_\text{in}},
```

so the largest bath is ``V_\max = F\; t_\max(F_{40})``, provided ``T_d`` is below the store temperature.

**Smaller baths.** A bath smaller than ``V_\max(F)`` can be filled at the same flow ``F``, it just
takes less time. So the set of achievable (fill time, volume) pairs is the union over all flows of the
segments from the origin to ``(t_\max(F),\, V_\max(F))``, and its edge is the upper envelope

```math
V(t) = \max\,\{\, F\,t \;:\; t_\max(F) \geq t \,\}.
```

For short fill times every flow qualifies, so the edge follows the fastest flow the booklet covers,
``F_{40} = 10`` L/min, straight into the origin. Since ``F_{40} = \big(F\,(T - T_\text{in}) + \tfrac12 U\,(T - T_\text{room})/\rho c\big)/(40 - T_\text{in})``
is linear in ``F``, that fastest tap flow follows directly. Nothing is extrapolated beyond the data at
long fill times.

**How the table is used.** ``t_\max`` is interpolated linearly in flow between the tabulated
5, 6, 8, 10 L/min; outside that range there is no data and nothing is plotted. A "-" cell (under 5 min) counts as 0 min, and "3 hr+" as 180 min,
so in that case ``V_\max`` is a **lower bound** (dashed in the graph).
"""

# ╔═╡ f7414c86-1f3c-460e-9283-dac58ef6608e
runtime = CSV.read(joinpath(@__DIR__, "data", "runtime.csv"), DataFrame)

# ╔═╡ 33135613-fd6d-41d2-981a-f8203c1ee278
const CAPPED_MINUTES = 180.0   # "3 hr+" in the booklet

# ╔═╡ 73ead624-e973-4a04-a434-72345de29c6c
# the run-time tables combine Fat and Tall (both 110 L) into one table
const STORE_MODELS = Dict(
    "Mini Store XS (60 L)" => "Mini Store XS",
    "Mini Store (80 L)" => "Mini Store",
    "Mini Store Fat / Tall (110 L)" => "Mini Store Fat / Tall",
    "Mini Store XL (130 L)" => "Mini Store XL",
)

# ╔═╡ 614585aa-6258-4601-b22d-fcc3e8b837e9
const STORE_NAMES = ["Mini Store XS (60 L)", "Mini Store (80 L)", "Mini Store Fat / Tall (110 L)", "Mini Store XL (130 L)"]

# ╔═╡ 7b66dc07-b2f7-4479-8a44-d2116205c8a8
"""Run time in minutes at the four tabulated flow rates for one booklet table, plus whether it was capped at 3 hr+."""
function tabulated_runtime_table(runtime, model, inlet_temperature, store_temperature, heat_pump_kW)
    rows = filter(
        r -> r.model == model && r.inlet_temperature_C == inlet_temperature &&
            r.store_temperature_C == store_temperature && r.heat_pump_kW == heat_pump_kW,
        runtime,
    )
    sort!(rows, :flow_rate_L_per_min)
    minutes = [
        status == "value" ? Float64(value) : status == "3hr+" ? CAPPED_MINUTES : 0.0
            for (status, value) in zip(rows.status, rows.runtime_min)
    ]
    return (; flow = Float64.(rows.flow_rate_L_per_min), minutes, capped = rows.status .== "3hr+")
end

# ╔═╡ 5c0e7a41-8d2b-4f6e-9a13-2b7c4d9e0f18
"""
Run-time table for any heat pump size between 4 and 14 kW. Sizes not in the booklet (odd kW)
are interpolated linearly between the neighbouring tabulated sizes; capped if either neighbour is.
"""
function runtime_table(runtime, model, inlet_temperature, store_temperature, heat_pump_kW)
    tabulated = sort(unique(runtime.heat_pump_kW))
    heat_pump_kW in tabulated &&
        return tabulated_runtime_table(runtime, model, inlet_temperature, store_temperature, heat_pump_kW)
    i = searchsortedlast(tabulated, heat_pump_kW)
    lower, upper = tabulated[i], tabulated[i + 1]
    weight = (heat_pump_kW - lower) / (upper - lower)
    a = tabulated_runtime_table(runtime, model, inlet_temperature, store_temperature, lower)
    b = tabulated_runtime_table(runtime, model, inlet_temperature, store_temperature, upper)
    return (; a.flow, minutes = (1 - weight) .* a.minutes .+ weight .* b.minutes, capped = a.capped .| b.capped)
end

# ╔═╡ 50da6c0c-3d3a-4100-9565-ecf9c0775ac9
"""Interpolate run time (minutes) and capped-flag at an arbitrary 40 °C-equivalent flow rate."""
function interpolate_runtime(table, flow_40)
    (; flow, minutes, capped) = table
    (flow_40 > last(flow) || flow_40 < first(flow)) && return (NaN, false)
    i = searchsortedlast(flow, flow_40)
    i == length(flow) && return (last(minutes), last(capped))
    weight = (flow_40 - flow[i]) / (flow[i + 1] - flow[i])
    return ((1 - weight) * minutes[i] + weight * minutes[i + 1], capped[i] || capped[i + 1])
end

# ╔═╡ 4e2ac973-9e54-4dad-aed1-96c2d4fd91f4
const RHO_C = 4186.0 / 60   # W per (L/min) per K: heat flow carried by water flowing at 1 L/min, per K

# ╔═╡ 1a9e946f-54ad-427c-b579-4cbe2aa0b10e
"""
Largest bath volume (L) at bath temperature `T` and flow `F` (L/min).
Returns `(volume, capped)`; `volume` is NaN when infeasible.
"""
function max_bath_volume(table, T, F; inlet_temperature, store_temperature, loss_coefficient, room_temperature)
    delivery_temperature = T + loss_coefficient * max(T - room_temperature, 0) / (2 * RHO_C * F)
    delivery_temperature >= store_temperature && return (NaN, false)
    flow_40 = F * (delivery_temperature - inlet_temperature) / (40 - inlet_temperature)
    minutes, capped = interpolate_runtime(table, flow_40)
    return (F * minutes, capped)
end

# ╔═╡ 8f3c2b1a-4d5e-4f60-9a7b-0c1d2e3f4a66
"""
Largest bath volume (L) that can be filled within each fill time in `times` (min) at bath
temperature `T`. Any bath smaller than ``V_\\max(F)`` can be filled at the same flow ``F`` in less
time, so this is the upper envelope over tap flows of ``F t``, taken over the flows whose run time
``t_\\max`` is at least ``t``. Flows are limited to the booklet's 5–10 L/min (40 °C-equivalent).
Returns `(volumes, capped, flows)`: NaN volume where no flow manages, `flows` the limiting flow.
"""
function bath_frontier(table, T, times; inlet_temperature, store_temperature, loss_coefficient,
        room_temperature, number_of_flows = 1000)
    # F₄₀ = a F + b is linear in the tap flow F, so the tabulated F₄₀ range maps to a tap flow range
    a = (T - inlet_temperature) / (40 - inlet_temperature)
    b = loss_coefficient * max(T - room_temperature, 0) / (2 * RHO_C * (40 - inlet_temperature))
    slowest = max((first(table.flow) - b) / a, 1.0e-3)
    fastest = (last(table.flow) - b) / a * (1 - 1.0e-9)     # shrink to stay inside the table
    volumes = fill(NaN, length(times))
    capped = fill(false, length(times))
    limiting_flows = fill(NaN, length(times))
    fastest <= slowest && return (volumes, capped, limiting_flows)
    for F in range(slowest, fastest; length = number_of_flows)
        volume, flow_capped = max_bath_volume(table, T, F; inlet_temperature, store_temperature,
            loss_coefficient, room_temperature)
        isnan(volume) && continue
        run_time = volume / F
        for (i, t) in enumerate(times)
            if t <= run_time && !(F * t <= volumes[i])    # also true when volumes[i] is NaN
                volumes[i], capped[i], limiting_flows[i] = F * t, flow_capped, F
            end
        end
    end
    return (volumes, capped, limiting_flows)
end

# ╔═╡ 0f04360a-f619-4ade-b934-6b8f9440a8bf
md"""
## Caveats

- The booklet tables are for a **40 °C** mixed outlet; using them for other bath temperatures assumes
  the store's heat capacity can be traded energy-for-energy, which holds while the store stays hotter
  than the delivery temperature ``T_d``.
- Bath heat loss uses a single lumped coefficient ``U`` and the mean fill fraction ½; a cold tub
  (especially cast iron or steel) absorbs extra heat at the start, which you can mimic with a larger ``U``.
- Only 40 °C-equivalent flows of 5–10 L/min are used (the booklet's range). Lines therefore stop at
  their slow (right-hand) end, and small baths follow the fastest flow in the data even if the tap
  could run faster.
"""

# ╔═╡ a1f0c3d2-6e4b-4c8a-9f21-3b5d7e9a0c11
md"""
**Reading the graph.** Each coloured line is a bath temperature and shows the largest bath that
can be filled within a given time; every smaller bath can be filled too. Small baths fill at the
fastest flow the booklet covers, so lines start at the origin along that flow; the right end of a
line is the slowest flow in the data. Dashed: the booklet's "3 hr+" was reached, so the bath could be
larger. Odd heat pump sizes are interpolated between the booklet's even-kW tables. Bath heat loss
``U = 75`` W/K means a full 150 L bath at 40 °C in an 18 °C room cools by about 0.16 °C/min. Fat and
Tall (both 110 L) share one booklet table.

**Data.** Run-time tables from the *Heat Geek Mini Store V1.1* booklet (pp. 12–19), extracted to
`data/runtime.csv` by `scripts/extract.py`. All performance data are © Newark Cylinders / Heat Geek,
taken from the publicly available
[booklet](https://newarkcylinders.co.uk/wp-content/uploads/2024/08/Heat-Geek-Mini-Store-V1.1-Specification-Installation-Booklet-updated-Sept-2024.pdf);
this notebook is an independent analysis, not endorsed by either.
"""

# ╔═╡ b2e1d4c3-7f5a-4d9b-8e32-4c6e8f0b1d22
# the run-time table in the form web/model.js expects: "-" → 0 min, "3 hr+" → 180 min
runtime_columns = (;
    model = runtime.model,
    inlet = runtime.inlet_temperature_C,
    store = runtime.store_temperature_C,
    heat_pump = runtime.heat_pump_kW,
    flow = runtime.flow_rate_L_per_min,
    minutes = [status == "value" ? Float64(value) : status == "3hr+" ? CAPPED_MINUTES : 0.0
        for (status, value) in zip(runtime.status, runtime.runtime_min)],
    capped = runtime.status .== "3hr+",
)

# ╔═╡ c3f2e5d4-8a6b-4e0c-9f43-5d7f9a1c2e33
# web/model.js is the JavaScript mirror of the model functions below, tested by test/consistency.jl
model_js = read(joinpath(@__DIR__, "web", "model.js"), String)

# ╔═╡ d4a3f6e5-9b7c-4f1d-8a54-6e8a0b2d3f44
# line colours for bath temperatures 37–45 °C, shared by the interactive and the Julia graph
bath_colors = ["#" * CairoMakie.Colors.hex(c) for c in cgrad(:thermal, 10; categorical = true)[1:9]]

# ╔═╡ e5b4a7f6-0c8d-4a2e-9b65-7f9b1c3e4a55
@htl("""
<div class="bath-widget" style="font-family: system-ui, sans-serif; max-width: 900px;">
<style>
  .bath-widget .controls { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 6px 18px; margin: 8px 0; }
  .bath-widget label { display: flex; align-items: center; gap: 8px; font-size: 0.95em; }
  .bath-widget label span.name { min-width: 9.5em; }
  .bath-widget input[type=range], .bath-widget select { flex: 1; min-width: 0; }
  .bath-widget output { min-width: 4.5em; font-variant-numeric: tabular-nums; }
</style>
<div class="controls">
  <label><span class="name">Store</span>
    <select name="store">
      <option value="Mini Store XS">Mini Store XS (60 L)</option>
      <option value="Mini Store" selected>Mini Store (80 L)</option>
      <option value="Mini Store Fat / Tall">Mini Store Fat / Tall (110 L)</option>
      <option value="Mini Store XL">Mini Store XL (130 L)</option>
    </select></label>
  <label><span class="name">Heat pump</span>
    <input type="range" name="heat_pump" min="4" max="14" step="1" value="5"><output></output></label>
  <label><span class="name">Store temperature</span>
    <input type="range" name="store_temperature" min="45" max="70" step="5" value="55"><output></output></label>
  <label><span class="name">Season</span>
    <select name="inlet">
      <option value="10" selected>winter (10 °C mains)</option>
      <option value="13">spring/autumn (13 °C mains)</option>
    </select></label>
  <label><span class="name">Bath heat loss</span>
    <input type="range" name="loss" min="0" max="150" step="5" value="75"><output></output></label>
  <label><span class="name">Room temperature</span>
    <input type="range" name="room" min="10" max="25" step="1" value="18"><output></output></label>
</div>
<div class="plot"></div>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<script>
$(HypertextLiteral.JavaScript(model_js))

const rows = $(runtime_columns);
const colors = $(bath_colors);
const root = currentScript.parentElement;
const plotDiv = root.querySelector(".plot");
const units = { heat_pump: " kW", store_temperature: " °C", loss: " W/K", room: " °C" };
const value = name => root.querySelector(`[name="\${name}"]`).value;

function draw() {
    for (const input of root.querySelectorAll("input[type=range]")) {
        input.nextElementSibling.textContent = input.value + units[input.name];
    }
    const store = value("store"), heatPump = +value("heat_pump"), storeTemperature = +value("store_temperature");
    const settings = {
        inletTemperature: +value("inlet"), storeTemperature,
        lossCoefficient: +value("loss"), roomTemperature: +value("room"),
    };
    const table = BathModel.runtimeTable(rows, store, settings.inletTemperature, storeTemperature, heatPump);
    const traces = [], annotations = [], shapes = [];
    let longestTime = 0, largestVolume = 0;
    const times = Array.from({ length: 2001 }, (_, i) => i / 10);   // 0 to 200 min
    for (let k = 0; k < 9; k++) {
        const T = 37 + k;
        const frontier = BathModel.bathFrontier(table, T, times, settings);
        const solid = { x: times, y: [], customdata: frontier.flows }, dashed = { x: times, y: [], customdata: frontier.flows };
        frontier.volumes.forEach((volume, i) => {
            if (!isNaN(volume)) { longestTime = Math.max(longestTime, times[i]); largestVolume = Math.max(largestVolume, volume); }
            solid.y.push(!isNaN(volume) && !frontier.capped[i] ? volume : null);
            dashed.y.push(!isNaN(volume) && frontier.capped[i] ? volume : null);
        });
        const hover = "%{y:.0f} L in %{x:.1f} min<br>at %{customdata:.1f} L/min<extra>" + T + " °C</extra>";
        traces.push({ ...solid, mode: "lines", name: T + " °C", legendgroup: T,
            line: { color: colors[k], width: 3 }, hovertemplate: hover });
        traces.push({ ...dashed, mode: "lines", name: T + " °C", legendgroup: T, showlegend: false,
            line: { color: colors[k], width: 3, dash: "dash" }, hovertemplate: hover });
    }
    // axes grow to fit the lines (in steps of 10 min / 50 L), but never below 40 min / 250 L
    const maxTime = Math.max(40, Math.ceil(1.05 * longestTime / 10) * 10);
    const maxVolume = Math.max(250, Math.ceil(1.05 * largestVolume / 50) * 50);

    for (const F of [5, 6, 8, 10]) {
        traces.push({ x: [0, maxTime], y: [0, F * maxTime], mode: "lines", hoverinfo: "skip",
            line: { color: "rgba(128,128,128,0.4)", width: 1 }, showlegend: false });
        const t = Math.min(maxTime, 0.97 * maxVolume / F);
        annotations.push({ x: t, y: F * t, text: F + " L/min", showarrow: false, xanchor: "right",
            yanchor: "bottom", font: { color: "gray", size: 12 } });
    }
    for (const [volume, label] of [[80, "small bath"], [120, "standard bath"], [150, "large bath"]]) {
        shapes.push({ type: "line", x0: 0, x1: maxTime, y0: volume, y1: volume,
            line: { color: "rgba(0,0,0,0.25)", dash: "dot", width: 1 } });
        annotations.push({ x: maxTime, y: volume, text: label, showarrow: false, xanchor: "right",
            yanchor: "bottom", font: { color: "rgba(0,0,0,0.5)", size: 11 } });
    }
    const storeLabel = root.querySelector('[name="store"]').selectedOptions[0].textContent;
    Plotly.react(plotDiv, traces, {
        title: { text: `\${storeLabel}, \${heatPump} kW heat pump, store at \${storeTemperature} °C, \${settings.inletTemperature === 10 ? "winter" : "spring/autumn"}`,
            font: { size: 15 } },
        xaxis: { title: "Time to fill the bath (min)", range: [0, maxTime] },
        yaxis: { title: "Bath volume V (L)", range: [0, maxVolume] },
        legend: { title: { text: "Bath T" } },
        annotations, shapes, height: 520, margin: { t: 50, r: 10 },
    }, { displaylogo: false, responsive: true });
}

root.querySelectorAll("input, select").forEach(el => el.addEventListener("input", draw));
draw();
</script>
</div>
""")

# ╔═╡ 6b8eeff0-b63b-4c13-af26-b42a92781557
md"""
## Julia reference version

The same graph computed in Julia. It only responds to these controls when the notebook is running
in Pluto (on the website, use the interactive graph at the top instead).

Store **S** $(@bind store_name PlutoUI.Select(STORE_NAMES; default = "Mini Store (80 L)"))
 Heat pump **H** $(@bind H PlutoUI.Slider(4:1:14; default = 5, show_value = true)) kW
 Store temperature $(@bind store_temperature PlutoUI.Slider(45:5:70; default = 55, show_value = true)) °C
"""

# ╔═╡ 0ed36d23-39b6-40a7-a568-8ebe822770d9
md"""
Season $(@bind inlet_temperature PlutoUI.Select([10 => "winter (10 °C mains)", 13 => "spring/autumn (13 °C mains)"]))
 Bath heat loss ``U`` $(@bind loss_coefficient PlutoUI.Slider(0:5:150; default = 75, show_value = true)) W/K
 Room $(@bind room_temperature PlutoUI.Slider(10:1:25; default = 18, show_value = true)) °C
"""

# ╔═╡ fc4f3474-d2f1-4d2b-b969-92eb56f751b3
begin
    settings = (; inlet_temperature, store_temperature, loss_coefficient, room_temperature)
    S = STORE_MODELS[store_name]
    table = runtime_table(runtime, S, inlet_temperature, store_temperature, H)
    nothing
end

# ╔═╡ ffefe839-fdc3-4611-82e9-d8ccb3094ec0
let
    fig = Figure(; size = (900, 520))
    ax = Axis(fig[1, 1]; xlabel = "Time to fill the bath (min)", ylabel = "Bath volume V (L)",
        title = "$(store_name), $(H) kW heat pump, store at $(store_temperature) °C, $(inlet_temperature == 10 ? "winter" : "spring/autumn")")
    max_time, max_volume = 40, 250

    # guides: constant flow rate F means V = F·t
    for F in (5, 6, 8, 10)
        lines!(ax, [0, max_time], [0, F * max_time]; color = (:gray, 0.4), linewidth = 1)
        t_label = min(max_time, 0.97 * max_volume / F)
        text!(ax, t_label, F * t_label; text = "$F L/min", color = :gray, align = (:right, :bottom), fontsize = 12)
    end
    hlines!(ax, [80, 120, 150]; color = (:black, 0.25), linestyle = :dot)
    text!(ax, fill(max_time, 3), [80, 120, 150]; text = ["small bath", "standard bath", "large bath"],
        align = (:right, :bottom), color = (:black, 0.5), fontsize = 11)

    bath_temperatures = 37:1:45
    times = 0:0.1:200
    for (k, T) in enumerate(bath_temperatures)
        volumes, capped, _ = bath_frontier(table, T, times; settings...)
        lines!(ax, times, ifelse.(capped, NaN, volumes); color = bath_colors[k], linewidth = 3, label = "$(T) °C")
        lines!(ax, times, ifelse.(capped, volumes, NaN); color = bath_colors[k], linewidth = 3, linestyle = :dash)
    end
    limits!(ax, 0, max_time, 0, max_volume)
    Legend(fig[1, 2], ax, "Bath T")
    fig
end

# ╔═╡ Cell order:
# ╟─dd8f12f5-7b13-44c2-aa4c-1648e1d52916
# ╟─e5b4a7f6-0c8d-4a2e-9b65-7f9b1c3e4a55
# ╟─a1f0c3d2-6e4b-4c8a-9f21-3b5d7e9a0c11
# ╠═70d34bee-921e-4dc5-bfce-1b4d290964e4
# ╟─c81a072b-6b34-422b-83c5-fc2f11c3b539
# ╠═f7414c86-1f3c-460e-9283-dac58ef6608e
# ╠═33135613-fd6d-41d2-981a-f8203c1ee278
# ╠═73ead624-e973-4a04-a434-72345de29c6c
# ╠═614585aa-6258-4601-b22d-fcc3e8b837e9
# ╠═7b66dc07-b2f7-4479-8a44-d2116205c8a8
# ╠═5c0e7a41-8d2b-4f6e-9a13-2b7c4d9e0f18
# ╠═50da6c0c-3d3a-4100-9565-ecf9c0775ac9
# ╠═4e2ac973-9e54-4dad-aed1-96c2d4fd91f4
# ╠═1a9e946f-54ad-427c-b579-4cbe2aa0b10e
# ╠═8f3c2b1a-4d5e-4f60-9a7b-0c1d2e3f4a66
# ╠═b2e1d4c3-7f5a-4d9b-8e32-4c6e8f0b1d22
# ╠═c3f2e5d4-8a6b-4e0c-9f43-5d7f9a1c2e33
# ╠═d4a3f6e5-9b7c-4f1d-8a54-6e8a0b2d3f44
# ╠═fc4f3474-d2f1-4d2b-b969-92eb56f751b3
# ╟─6b8eeff0-b63b-4c13-af26-b42a92781557
# ╟─ffefe839-fdc3-4611-82e9-d8ccb3094ec0
# ╟─0ed36d23-39b6-40a7-a568-8ebe822770d9
# ╟─0f04360a-f619-4ade-b934-6b8f9440a8bf
