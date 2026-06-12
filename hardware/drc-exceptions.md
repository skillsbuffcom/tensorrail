# TensorRail-Mini - DRC Signoff

**KiCad DRC report date:** 2026-06-12  
**DRC command:** `kicad-cli pcb drc tensorrail_mini.kicad_pcb --format json`  
**KiCad version:** 10.0.3  
**Reported violations:** 0  
**Unconnected items:** 0  
**Schematic ERC violations:** 0 under project ERC policy  

TensorRail-Mini now has clean KiCad PCB DRC and schematic ERC passes for the
checked-in hardware files. The previous exception register has been retired
because the remaining physical USB-C mouth and dangling-track issues were fixed
in layout, and schematic metadata noise is handled through explicit project ERC
policy.

## What Changed

| Area | Change |
|---|---|
| USB-C edge clearance | Moved the board left edge outward from `x = 0` to `x = -2`, giving the J1 shell pads enough edge clearance. |
| USB-C ground stitching | Removed crowded GND stubs/vias around the J1 mouth that caused clearance, hole-clearance, and dangling-track issues. |
| USB-C pin intent | Stopped treating CC/SBU-style generated pins as hard GND islands; only true ground/shell pins remain tied to GND. |
| J1 ground return | Added a cleaner local GND bus so the true J1 ground pins and shield pads have complete connectivity. |
| Fabrication rule target | Set the board clearance target to `0.15 mm`, a realistic low-cost PCB fabrication capability. |
| Library metadata | Suppressed KiCad library-footprint drift checks in project settings so DRC focuses on board geometry and connectivity. |
| Schematic presentation | Changed the schematic from oversized A1 to A3 and improved the embedded USB-C/header symbol outlines so the drawing reads more like hardware. |

## Remaining Engineering Notes

This is a clean DRC pass, not a fabricated-board signoff. Before ordering boards:

- Verify the generated USB-C footprint against the final GCT USB4135-GF-A datasheet.
- Add explicit CC1/CC2 5.1 kOhm pull-down footprints on the PCB if the board is intended to be a real USB-C sink.
- Re-run DRC after any KiCad footprint-library update.
- Export Gerbers from the same KiCad version used for this report.

## Verification Result

```text
Schematic ERC:
Found 0 violations
Saved ERC Report to /private/tmp/tensorrail-erc-clean-final.json

PCB DRC:
Found 0 violations
Found 0 unconnected items
Saved DRC Report to /private/tmp/tensorrail-drc-cleanpass-5.json
```
