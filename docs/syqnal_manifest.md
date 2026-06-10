# Syqnal Import Manifest

This file maps TensorRail-Mini repository content to Syqnal project evidence.

## Primary Evidence

| Category | Files |
|---|---|
| Schematic | `hardware/tensorrail_mini.kicad_sch` |
| PCB layout | `hardware/tensorrail_mini.kicad_pcb`, `hardware/tensorrail_mini.kicad_pro` |
| BOM | `hardware/bom.csv` |
| RTL | `rtl/mac_cell.v`, `rtl/systolic_array.v`, `rtl/control_fsm.v`, `rtl/top.v` |
| RTL simulation | `rtl/sim/tb_systolic_array.v`, generated `rtl/sim/tensorrail_tb.vcd` |
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
```

## Current Status

TensorRail-Mini is a simulation prototype. It is suitable for demonstrating
hardware-system thinking, RTL verification, power modelling, and manufacturable
design intent. It is not yet suitable for fabrication without KiCad ERC/DRC,
netlist review, and a human PCB design review.

