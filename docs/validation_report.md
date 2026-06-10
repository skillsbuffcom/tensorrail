# Validation Report

Date: 2026-06-09

## Summary

TensorRail-Mini currently validates as a coherent simulation-oriented portfolio
project, not as a fab-released hardware design.

## Checks Completed

| Check | Result | Notes |
|---|---|---|
| Python golden model | PASS | `simulation/golden_model.py` computes expected INT8 results and all built-in checks pass. |
| BOM vs board intent | IMPROVED | BOM now matches the v0.2 carrier: TPS62130 rails, INA219, W25Q128 flash, oscillator, Feather sockets, 40-pin expansion. |
| PCB critical net naming | IMPROVED | Switch nodes, feedback nodes, INA219 shunt, CC pins, JTAG pins, and LED anode nets are no longer anonymous `net 0`. |
| Documentation honesty | IMPROVED | Docs now describe USB-C as power-only and external-memory DMA as future work. |

## Checks Blocked On Local Tooling

These tools were not available in the current environment:

| Tool | Needed for |
|---|---|
| `iverilog` / `vvp` | Verilog simulation and VCD generation |
| `ngspice` | Power rail transient run and `.raw` generation |
| `openscad` | STL export |
| `kicad-cli` | ERC/DRC and Gerber/drill export |
| `verilator` | RTL lint |

## Required Before Fabrication

- Run KiCad ERC and PCB DRC.
- Review USB-C footprint against the selected GCT connector drawing.
- Review TPS62130 pin mapping and feedback loops against the datasheet.
- Confirm INA219 shunt polarity and current path.
- Add or finalize ECP5/OrangeCrab pin constraints before synthesis/P&R claims.
- Export Gerbers only after ERC/DRC and human layout review pass.

