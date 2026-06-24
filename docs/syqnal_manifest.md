# Syqnal Import Manifest

This file maps TensorRail-Mini repository content to Syqnal project evidence.

## Primary Evidence

| Category | Files |
|---|---|
| Schematic | `hardware/tensorrail_mini.kicad_sch` |
| PCB layout | `hardware/tensorrail_mini.kicad_pcb`, `hardware/tensorrail_mini.kicad_pro` |
| BOM | `hardware/bom.csv` |
| RTL | `rtl/mac_cell.v`, `rtl/systolic_array.v`, `rtl/tensorrail_asic_top.v`, `rtl/control_fsm.v`, `rtl/top.v` |
| RTL simulation | `rtl/sim/tb_systolic_array.v`, generated `rtl/sim/tensorrail_tb.vcd` |
| ASIC flow / GDSII | `asic/openlane/tensorrail_mac_tile/config.json`, `asic/openlane/tensorrail_mac_tile/pin_order.cfg`, generated OpenLane `runs/*/results/final/gds/*.gds` |
| Golden model | `simulation/golden_model.py`, generated `expected_result.csv`, `hex/*.hex` |
| Power simulation | `simulation/power_core_load_step.cir`, generated `simulation/power_core_load_step.raw` |
| Mechanical CAD | `mechanical/tensorrail_enclosure.scad`, generated `mechanical/*.stl` |
| Documentation | `docs/architecture.md`, `docs/bringup_plan.md`, `docs/validation_report.md` |

## Generated Artifact Targets

Run these commands after installing the relevant tools:

```bash
python3 simulation/golden_model.py --csv --gen-hex
scripts/run_rtl_sim.sh
ngspice -b simulation/power_core_load_step.cir
scripts/export_mechanical.sh
scripts/export_gerbers.sh
cd asic/openlane/tensorrail_mac_tile && python3 -m openlane --pdk-root "$PDK_ROOT" --run-tag syqnal_ci config.json
```

## Current Status

TensorRail-Mini is a simulation prototype. It is suitable for demonstrating
hardware-system thinking, RTL verification, power modelling, and manufacturable
design intent. The `asic/` directory is an experimental OpenLane ASIC-flow
scaffold for Syqnal verification and education; it does not mean this FPGA
carrier-board project has been taped out. The conceptual floorplan SVG is not
GDS/OAS evidence. The project is not suitable for fabrication without KiCad
ERC/DRC, ASIC DRC/LVS/timing signoff, netlist review, and a human PCB/IC design
review.
