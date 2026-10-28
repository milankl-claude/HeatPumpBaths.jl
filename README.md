# HeatPumpBaths.jl

How big a bath can a heat pump with a [Heat Geek Mini Store](https://newarkcylinders.co.uk/) fill,
and how long does it take?

**Interactive notebook:** https://milankl.github.io/HeatPumpBaths.jl/

For a chosen store type, heat pump size, store temperature and mains inlet temperature, the graph
shows the largest bath that can be filled at bath temperatures of 37–45 °C, against the time it
takes to fill it. Heat lost by the bath while it fills is included. The model is explained in the
notebook.

## Repository layout

| Path | Content |
|---|---|
| `index.jl` | The [Pluto](https://plutojl.org) notebook: model, explanation, interactive graph |
| `web/model.js` | JavaScript copy of the model, so the graph is interactive on the static website |
| `data/` | Tables extracted from the Mini Store booklet (`runtime.csv`, `models.csv`, `recharge.csv`) |
| `scripts/extract.py` | Extracts `data/` from the booklet PDF |
| `scripts/load.jl` | Loads `data/` into DataFrames |
| `test/consistency.jl` | Checks the JavaScript and Julia models give the same results |

## Running locally

```julia
using Pluto
Pluto.run()   # then open index.jl
```

## Changing the model

The model exists twice: in Julia (`index.jl`) and in JavaScript (`web/model.js`), which the
website's interactive graph uses. Any change to the model must be made in both. The `Test` workflow
runs both on a grid of inputs and fails if they disagree; run it locally with

```bash
julia --project=test -e 'using Pkg; Pkg.instantiate()'
julia --project=test test/consistency.jl
```

## Website

On every push to `main`, the `Export Pluto notebook to GitHub Pages` workflow runs the notebook with
[PlutoSliderServer](https://github.com/JuliaPluto/PlutoSliderServer.jl) and publishes the static HTML
to GitHub Pages (Settings → Pages → Source: *GitHub Actions*).

## Data source

All performance data are © Newark Cylinders / Heat Geek, taken from the publicly available
[Heat Geek Mini Store V1.1 Specification & Installation Booklet](https://newarkcylinders.co.uk/wp-content/uploads/2024/08/Heat-Geek-Mini-Store-V1.1-Specification-Installation-Booklet-updated-Sept-2024.pdf)
(updated September 2024). This is an independent analysis, not endorsed by either company.
