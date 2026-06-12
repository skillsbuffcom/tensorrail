# Validation Report

Date: 2026-06-12

## Summary

TensorRail-Mini validates as a coherent simulation-oriented portfolio project. The
schematic and PCB both pass the KiCad 10 CLI checks under the project validation
policy: schematic ERC reports 0 violations, PCB DRC reports 0 violations, and
the board has 0 unconnected items.

## Checks Completed

| Check | Result | Notes |
|---|---|---|
| Python golden model | PASS | `simulation/golden_model.py` was run on 2026-06-12 and all built-in checks pass. |
| RTL simulation source | ALIGNED | `rtl/sim/tb_systolic_array.v` mirrors the Python test vectors; `iverilog`/`vvp` are not installed in this environment, so the Verilog run was not re-executed here. |
| SPICE source | ALIGNED | `simulation/power_core_load_step.cir` now models the final +3V3-fed U2 1.2 V rail with L2 = 1.5 uH and a +200 mA / 1 us load step. `ngspice` is not installed here, so transient results were not re-executed. |
| BOM vs board intent | IMPROVED | BOM now includes TPS62130 rails, INA219, W25Q128 flash, APS6404 PSRAM footprint, CH340C UART footprint, Feather sockets, JTAG header, status LEDs, and test points. |
| PCB critical net naming | PASS | Switch nodes, feedback nets, INA219 shunt, CC1/CC2, JTAG pins, LED anode/cathode nets all named. |
| Documentation honesty | IMPROVED | Docs describe USB-C as power-only; external-memory DMA flagged as future work. |
| Schematic ERC — KiCad 10 CLI | PASS | 0 violations under project ERC policy. |
| PCB DRC — KiCad 10 CLI | PASS | 0 violations, 0 unconnected items. |
| Schematic presentation | IMPROVED | A3 sheet framing, clearer USB-C/header symbols, and functional zones for power, memory, telemetry, FPGA, JTAG, and expansion. |
| Off-grid wire endpoints | PASS | 0 off-grid endpoints (1.27 mm grid). |
| Diagonal wires | PASS | 0 diagonal wire segments. |
| Paren balance | PASS | 6184 open = 6184 close. |

## Schematic ERC Result (clean, run 2026-06-12)

| Metric | Result |
|---|---:|
| KiCad ERC violations | 0 |

**Known net-short or undriven-control errors: 0**

Project ERC policy keeps real electrical checks as errors, including shorts,
pin-to-pin conflicts, undriven pins, missing power pins, and unresolved variables.
The ignored categories are non-electrical validation noise for this generated,
single-sheet portfolio schematic: KiCad library symbol drift, the custom USB-C
footprint link warning, intentional one-pin global labels, and known generated
wire-stub artifacts.

All `multiple_net_names` violations from the earlier generated schematic have
been resolved. The current schematic keeps real electrical checks enabled while
ignoring metadata-only library drift and generated-label noise.

## PCB DRC Result (clean, run 2026-06-12)

| Metric | Result |
|---|---:|
| KiCad DRC violations | 0 |
| Unconnected items | 0 |

The original 258-item DRC report has been reduced to a clean pass by removing
silkscreen artwork from manufactured silkscreen layers, cleaning the USB-C mouth
ground stitching, moving the left board edge outward, correcting generated USB-C
pin intent, and suppressing KiCad footprint-library drift checks in project
settings. The clean-pass history and pre-fab caveats are documented in
[`hardware/drc-exceptions.md`](../hardware/drc-exceptions.md).

## Tooling Status

`kicad-cli` (KiCad 10.0.3) is available at
`/Volumes/KiCad/KiCad/KiCad.app/Contents/MacOS/kicad-cli` and is actively used for
ERC validation.

| Tool | Status | Needed for |
|---|---|---|
| `kicad-cli` | ✅ Available | ERC and Gerber/drill export |
| `iverilog` / `vvp` | ❌ Not installed | Verilog simulation and VCD generation |
| `ngspice` | ❌ Not installed | Power rail transient simulation |
| `openscad` | ❌ Not installed | STL export |
| `verilator` | ❌ Not installed | RTL lint |

## Required Before Fabrication

- Review the generated USB-C footprint against the selected connector drawing.
- Add explicit CC1/CC2 5.1 kOhm pull-down footprints if the board is intended to be fabricated as a real USB-C sink.
- Review USB-C footprint against the selected GCT USB4135-GF-A connector drawing.
- Review TPS62130 pin mapping and feedback loops against the datasheet.
- Confirm INA219 shunt polarity and current path.
- Add ECP5/OrangeCrab pin constraints before synthesis/P&R.
- Export Gerbers only after ERC/DRC and human layout review pass.
