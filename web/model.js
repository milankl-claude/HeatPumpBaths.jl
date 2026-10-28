// Bath-filling model, JavaScript mirror of the Julia functions in index.jl.
// Runs in the browser (interactive graph) and in Node (test/consistency.jl).
// Any change to the model must be made in both places; test/consistency.jl checks they agree.

const RHO_C = 4186.0 / 60; // W per (L/min) per K: heat flow carried by water flowing at 1 L/min, per K

// `rows`: columns of the run-time table with minutes already converted
// ("-" -> 0, "3 hr+" -> 180) as {model, inlet, store, heat_pump, flow, minutes, capped}
function tabulatedRuntimeTable(rows, model, inletTemperature, storeTemperature, heatPumpKW) {
    const entries = [];
    for (let i = 0; i < rows.model.length; i++) {
        if (rows.model[i] === model && rows.inlet[i] === inletTemperature &&
            rows.store[i] === storeTemperature && rows.heat_pump[i] === heatPumpKW) {
            entries.push({ flow: rows.flow[i], minutes: rows.minutes[i], capped: rows.capped[i] });
        }
    }
    entries.sort((a, b) => a.flow - b.flow);
    return {
        flow: entries.map(e => e.flow),
        minutes: entries.map(e => e.minutes),
        capped: entries.map(e => e.capped),
    };
}

// Any heat pump size between the tabulated ones, interpolated linearly; capped if either neighbour is.
function runtimeTable(rows, model, inletTemperature, storeTemperature, heatPumpKW) {
    const tabulated = [...new Set(rows.heat_pump)].sort((a, b) => a - b);
    if (tabulated.includes(heatPumpKW)) {
        return tabulatedRuntimeTable(rows, model, inletTemperature, storeTemperature, heatPumpKW);
    }
    let i = 0;
    while (tabulated[i + 1] < heatPumpKW) i++;
    const lower = tabulated[i], upper = tabulated[i + 1];
    const weight = (heatPumpKW - lower) / (upper - lower);
    const a = tabulatedRuntimeTable(rows, model, inletTemperature, storeTemperature, lower);
    const b = tabulatedRuntimeTable(rows, model, inletTemperature, storeTemperature, upper);
    return {
        flow: a.flow,
        minutes: a.minutes.map((m, k) => (1 - weight) * m + weight * b.minutes[k]),
        capped: a.capped.map((c, k) => c || b.capped[k]),
    };
}

// Run time (minutes) and capped flag at a 40 °C-equivalent flow rate; NaN outside the table.
function interpolateRuntime(table, flow40) {
    const { flow, minutes, capped } = table;
    const n = flow.length;
    if (flow40 > flow[n - 1] || flow40 < flow[0]) return [NaN, false];
    let i = 0;
    while (i < n - 1 && flow[i + 1] <= flow40) i++;
    if (i === n - 1) return [minutes[n - 1], capped[n - 1]];
    const weight = (flow40 - flow[i]) / (flow[i + 1] - flow[i]);
    return [(1 - weight) * minutes[i] + weight * minutes[i + 1], capped[i] || capped[i + 1]];
}

// Largest bath volume (L) at bath temperature T and flow F (L/min): [volume, capped], volume NaN if infeasible.
function maxBathVolume(table, T, F, { inletTemperature, storeTemperature, lossCoefficient, roomTemperature }) {
    const deliveryTemperature = T + lossCoefficient * Math.max(T - roomTemperature, 0) / (2 * RHO_C * F);
    if (deliveryTemperature >= storeTemperature) return [NaN, false];
    const flow40 = F * (deliveryTemperature - inletTemperature) / (40 - inletTemperature);
    const [minutes, capped] = interpolateRuntime(table, flow40);
    return [F * minutes, capped];
}

// Largest bath volume (L) fillable within each fill time in `times` (min) at bath temperature T:
// upper envelope over tap flows of F*t, over flows whose run time is at least t (flows limited to the
// booklet's 40 °C-equivalent range). Returns {volumes, capped, flows}; NaN volume where no flow manages.
function bathFrontier(table, T, times, settings, numberOfFlows = 1000) {
    const { inletTemperature, lossCoefficient, roomTemperature } = settings;
    // F40 = a F + b is linear in the tap flow F, so the tabulated F40 range maps to a tap flow range
    const a = (T - inletTemperature) / (40 - inletTemperature);
    const b = lossCoefficient * Math.max(T - roomTemperature, 0) / (2 * RHO_C * (40 - inletTemperature));
    const slowest = Math.max((table.flow[0] - b) / a, 1.0e-3);
    const fastest = (table.flow[table.flow.length - 1] - b) / a * (1 - 1.0e-9); // stay inside the table
    const volumes = times.map(() => NaN), capped = times.map(() => false), flows = times.map(() => NaN);
    if (!(fastest > slowest)) return { volumes, capped, flows };
    for (let j = 0; j < numberOfFlows; j++) {
        const F = j === numberOfFlows - 1 ? fastest : slowest + j * (fastest - slowest) / (numberOfFlows - 1);
        const [volume, flowCapped] = maxBathVolume(table, T, F, settings);
        if (isNaN(volume)) continue;
        const runTime = volume / F;
        for (let i = 0; i < times.length; i++) {
            if (times[i] <= runTime && !(F * times[i] <= volumes[i])) {  // also true when volumes[i] is NaN
                volumes[i] = F * times[i]; capped[i] = flowCapped; flows[i] = F;
            }
        }
    }
    return { volumes, capped, flows };
}

const BathModel = { RHO_C, tabulatedRuntimeTable, runtimeTable, interpolateRuntime, maxBathVolume, bathFrontier };
if (typeof module !== "undefined") module.exports = BathModel;
