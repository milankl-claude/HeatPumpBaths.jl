"""Extract tables from the Heat Geek Mini Store V1.1 booklet into CSV.

Usage, from the repository root (needs `pip install pdfplumber`):
    curl -L -o spec.pdf "https://newarkcylinders.co.uk/wp-content/uploads/2024/08/Heat-Geek-Mini-Store-V1.1-Specification-Installation-Booklet-updated-Sept-2024.pdf"
    python3 scripts/extract.py spec.pdf

Outputs (in ./data):
  models.csv    - per-model specs (page 11)
  runtime.csv   - hot water run time, long format (pages 12-19)
  recharge.csv  - recharge time 40->55C and minutes per degC (page 20)
"""

import csv
import os
import re
import sys

import pdfplumber

PDF = sys.argv[1] if len(sys.argv) > 1 else "spec.pdf"
OUT = "data"
os.makedirs(OUT, exist_ok=True)

with pdfplumber.open(PDF) as pdf:
    pages = [page.extract_text() or "" for page in pdf.pages]

POWERS = [4, 6, 8, 10, 12, 14]  # heat pump output in kW, columns of every table

# ---------------------------------------------------------------- models (p. 11)
models = []
for block in re.split(r"\n(?=Mini Store[^\n]*- As per General Spec)", "\n" + pages[10])[1:]:
    name = block.split(" - As per")[0].strip()

    def grab(pattern):
        match = re.search(pattern, block)
        return match.groups() if match else None

    shell = grab(r"Shell Dimensions[^:]*: (\d+) x (\d+) mm")
    overall = grab(r"Nominal Overall Dimensions: (\d+) x (\d+) mm")
    models.append(
        dict(
            model=name,
            volume_L=grab(r"Volume (\d+) L")[0],
            shell_height_mm=shell[0],
            shell_diameter_mm=shell[1],
            overall_height_mm=overall[0],
            overall_diameter_mm=overall[1],
            weight_empty_kg=grab(r"Weight \(empty\) (\d+) kg")[0],
            weight_full_kg=grab(r"Weight \(full\) (\d+) kg")[0],
            standing_heat_loss_kWh_per_24h=grab(r"Standing Heat Loss: ([\d.]+)")[0],
        )
    )

with open(f"{OUT}/models.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(models[0]))
    writer.writeheader()
    writer.writerows(models)

# ------------------------------------------------------------ run time (p. 12-19)
# Cells: number -> minutes; "-" -> no usable run time; "3 hr+" -> effectively unlimited.
CELL = r"(3 hr\+|-|[\d.]+)"
ROW = re.compile(rf"^(\d+)°C " + " ".join([CELL] * 6) + "$")
MODEL_HEADER = re.compile(r"^(Mini Store.*?)\s*-?\s*(\d+)\s*L\b.*Run time", re.IGNORECASE)

runtime = []
for page in pages[11:19]:
    flow, inlet = re.search(r"Hot water duration at (\d+) L/m (\d+)°C Inlet", page).groups()
    model = volume = None
    for line in page.splitlines():
        if header := MODEL_HEADER.match(line):
            model, volume = header.group(1).strip(), header.group(2)
        elif (row := ROW.match(line)) and model:
            store_temperature, *cells = row.groups()
            for power, cell in zip(POWERS, cells):
                status = {"-": "none", "3 hr+": "3hr+"}.get(cell, "value")
                runtime.append(
                    dict(
                        flow_rate_L_per_min=flow,
                        inlet_temperature_C=inlet,
                        model=model,
                        volume_L=volume,
                        store_temperature_C=store_temperature,
                        heat_pump_kW=power,
                        runtime_min=cell if status == "value" else "",
                        status=status,
                    )
                )

with open(f"{OUT}/runtime.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(runtime[0]))
    writer.writeheader()
    writer.writerows(runtime)

# ------------------------------------------------------------ recharge (p. 20)
recharge = {}
section = None
for line in pages[19].splitlines():
    if line.startswith("Recharge Time"):
        section = "recharge_40_to_55C_min"
    elif line.startswith("Mins per"):
        section = "min_per_degC"
    elif section and (row := re.match(r"^(\d+)L (Mini Store.*?) ([\d.]+(?: [\d.]+){5})$", line)):
        volume, model, values = row.groups()
        for power, value in zip(POWERS, values.split()):
            key = (model, volume, power)
            recharge.setdefault(key, dict(model=model, volume_L=volume, heat_pump_kW=power))
            recharge[key][section] = value

with open(f"{OUT}/recharge.csv", "w", newline="") as f:
    rows = list(recharge.values())
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)

print(f"models: {len(models)} rows, runtime: {len(runtime)} rows, recharge: {len(recharge)} rows")
