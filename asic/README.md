# TensorRail ASIC Flow Scaffold

This directory contains an experimental OpenLane/OpenROAD flow for treating the
TensorRail systolic-array RTL as a small ASIC macro. The main project remains an
FPGA carrier-board proof of concept; these files exist so Syqnal can show a real
IC-design workflow without inventing signoff artifacts.

## Flow

- RTL: `rtl/mac_cell.v`, `rtl/systolic_array.v`, `rtl/tensorrail_asic_top.v`
- Top module: `tensorrail_asic_top`
- PDK target: `sky130A`
- Flow config: `openlane/tensorrail_mac_tile/config.json`
- Pin order: `openlane/tensorrail_mac_tile/pin_order.cfg`

Run from the repository root with an OpenLane environment and a Sky130 PDK:

```bash
cd asic/openlane/tensorrail_mac_tile
python3 -m openlane --pdk-root "$PDK_ROOT" --run-tag syqnal_ci config.json
```

Expected generated evidence, after a successful run:

- `runs/syqnal_ci*/results/final/gds/*.gds`
- `runs/syqnal_ci*/results/final/def/*.def`
- OpenSTA timing reports
- OpenROAD placement/routing reports
- KLayout or Magic silicon DRC reports
- Netgen LVS reports when extraction/setup files are available

No generated GDS/OAS is committed here. Syqnal Hardware CI should create and
inspect that artifact, then render the GDS preview from the actual layout.

## Evidence Rules

The SVG in `layout/tensorrail_floorplan.svg` is a conceptual floorplan only.
It is not a GDS preview and must not be treated as DRC, LVS, timing, or power
evidence.

Trusted ASIC evidence comes from the OpenLane run artifacts:

- GDS/OAS produced by OpenLane
- KLayout metadata and preview generated from that layout database
- Magic or KLayout DRC reports
- Netgen LVS reports
- OpenSTA timing reports
- OpenROAD/OpenLane power reports

Syqnal should show green signoff chips only when the corresponding report is
present in the CI artifact for the same commit SHA.
