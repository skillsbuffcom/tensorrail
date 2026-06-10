# TensorRail-Mini Board Bring-Up Plan

**Revision:** 0.1
**Target:** TensorRail-Mini v0.1 carrier board + OrangeCrab 85F FPGA module
**Date:** 2026-06-09

> **Important:** No board has been fabricated. This document is a pre-fabrication
> bring-up plan written before any real hardware exists. It is written to be
> realistic and complete so that it can be followed when a board is eventually built.
> All pass/fail criteria are based on datasheet specifications and simulation estimates.

---

## Safety Notes

- Work with an **isolated bench supply** with current limiting at **100 mA** until all power rails are verified.
- Wear an **ESD wrist strap** when handling the board and FPGA module.
- First power-on must be with the **FPGA module removed**; test bare carrier first.
- No component on the carrier board should exceed 60°C at idle. Use a thermal camera or non-contact thermometer to check after 60 seconds of power-on.

---

## Milestone Overview

| Phase | Goal | Key Pass Criteria | Est. Duration |
|---|---|---|---|
| **0** | Visual inspection | No bridges, polarity correct | 30 min |
| **1** | Carrier power (no module) | All rails within spec | 1 hr |
| **2** | USB-C and debug header checks | 5 V input stable; JTAG header sane | 30 min |
| **3** | FPGA module insertion + reset | Module responds to JTAG | 1 hr |
| **4** | Bitstream load | LEDs respond as expected | 2 hr |
| **5** | RTL smoke test (UART) | Tile-done byte received | 1 hr |
| **6** | SPI flash connectivity | JEDEC ID reads expected W25Q128 response | 2 hr |
| **7** | Full golden-model verification | Hardware matches Python model | half day |

---

## Phase 0 — Visual Inspection

### Checklist (hand or USB microscope)

- [ ] **Solder joints**: All 0402, SOT-23-8, SOIC-8, oscillator, and connector joints well-wetted; no bridges on U1/U2/U3.
- [ ] **Component polarity**: D1 cathode band correct (anode to J1 VBUS, cathode to power rail). LED D2–D5 orientation consistent with silkscreen.
- [ ] **CC resistors R1/R2**: Verify 5.1 kΩ values (orange, orange, gold in E96 marking). Both CC pins must have pull-downs for USB-C 5 V negotiation.
- [ ] **Feedback resistors R6/R7**: Verify 3.48 kΩ (R6 top) and 3.30 kΩ (R7 bottom). Incorrect values will mis-set the 1.2 V output.
- [ ] **No missing passives**: Check C4–C23 (100 nF bypass) — these are easy to miss at 0402 size.
- [ ] **Feather headers J4/J5**: Ensure female socket headers are flush and square; FPGA module must seat fully without rocking.
- [ ] **Mounting holes MH1–MH4**: Confirm holes are clear of debris; M3 bolt should drop in freely.

---

## Phase 1 — Carrier Power Rails (Module Removed)

### 1.1 Pre-Power Resistance Check

With bench supply disconnected and no module fitted:

| Net | TP | Expected | Fail if |
|---|---|---|---|
| VBUS to GND | TP1–TP4 | > 5 kΩ | < 100 Ω (short) |
| 3V3 to GND | TP2–TP4 | > 1 kΩ | < 50 Ω |
| 1V2 to GND | TP3–TP4 | > 500 Ω | < 50 Ω |

### 1.2 Power-On Sequence

**Step 1**: Set bench supply to **5.0 V, current limit 100 mA**. Connect to USB-C cable plugged into J1 (or probe TP1 and TP4 directly).

**Step 2**: Power on. Measure:

| Rail | TP | Nominal | Tolerance |
|---|---|---|---|
| VBUS | TP1 | 5.00 V | ±0.25 V |
| 3V3 (Buck) | TP2 | 3.30 V | ±0.10 V |
| 1V2 (Buck) | TP3 | 1.20 V | ±0.06 V |

**Step 3**: Measure total current. Expected: **< 30 mA** with no module.

**Step 4**: LED D2 (power indicator) should illuminate. D3–D5 should be off (no FPGA driving them).

**Step 5**: Verify TPS62130 PG (power-good) pin is HIGH. If LOW: check R6/R7 values and L1 continuity.

### 1.3 Load-Step Check (Optional, Phase 1)

Apply a 350 mA load step to the 1.2 V rail with an active load (e.g., BK Precision 8500) or a 3.4 Ω power resistor switched with a FET.

- Capture V(1V2) on oscilloscope: 200 MSa/s, 20 MHz BW.
- Compare to `simulation/power_core_load_step.cir` SPICE result.
- **Pass**: undershoot < 60 mV (stays above 1.14 V), recovery < 50 µs.

---

## Phase 2 — USB-C and Debug Header Checks

The current carrier is USB-C power-only; it does not include a USB-UART bridge.
UART pins are exposed on TP5/TP6 and the expansion header for connection to an
external 3.3 V USB-UART adapter.

### 2.1 USB-C Sink Check

- Confirm CC1 and CC2 each measure approximately 5.1 kΩ to ground.
- Confirm VBUS reaches TP1 with either plug orientation.
- Confirm no D+/D- enumeration is expected from this board revision.

### 2.2 External UART Adapter Check

Connect a 3.3 V USB-UART adapter:

| Adapter signal | Board point |
|---|---|
| TXD | TP6 / UART_RX |
| RXD | TP5 / UART_TX |
| GND | TP4 / GND |

Use 115200 baud, 8N1 after the FPGA bitstream is loaded.

---

## Phase 3 — FPGA Module Insertion

### 3.1 Module Seating

- Power off the carrier completely before inserting the OrangeCrab module.
- Align module edge castellations with J2/J3 female headers.
- Press firmly and evenly; module should click flush.
- Check for any bent pins under 10× magnification.

### 3.2 Power-On with Module

Re-apply bench supply. Expected additional current:
- OrangeCrab 85F at reset (oscillator only): ~50 mA extra → total ~80 mA.
- If current exceeds 200 mA, remove module immediately and recheck for shorts.

### 3.3 JTAG Connectivity

Connect a Lattice programming cable or FT2232H JTAG adapter to J4.

```bash
openFPGALoader --detect
# Expected output includes: LFE5U-85F
```

If the device is not detected, check:
1. RESET\_N held low (TP8) — should be HIGH at idle (R5 pull-up).
2. JTAG cable orientation (pin 1 marker on J4 matches VTref = 3.3V).
3. 3.3V present on J4 pin 1 (measured with DMM before cable is connected).

---

## Phase 4 — Bitstream Load

### 4.1 Synthesise and Load

```bash
# From repo root:
yosys -p "synth_ecp5 -top tensorrail_top -json out/tensorrail.json" \
    rtl/top.v rtl/systolic_array.v rtl/mac_cell.v rtl/control_fsm.v

nextpnr-ecp5 --85k --package CSFBGA285 \
    --json out/tensorrail.json \
    --textcfg out/tensorrail.config

ecppack out/tensorrail.config out/tensorrail.bit

# Load via JTAG
openFPGALoader -b orangeCrab85f out/tensorrail.bit
```

### 4.2 First-Boot LED Checks

After bitstream loads:

- [ ] **D2** (power): still on (3.3 V present — carrier, not FPGA)
- [ ] **D3** (busy): should pulse briefly during tile computation, then off
- [ ] **D4** (done): should pulse once when tile finishes
- [ ] **D5** (heartbeat): should blink at ~0.7 Hz (26-bit counter at 48 MHz)

If heartbeat does not blink, the design is not running — check configuration status.

---

## Phase 5 — RTL Smoke Test via UART

Open a serial terminal at **115200 baud, 8N1**:

```bash
screen /dev/ttyUSB0 115200
# Or: minicom -D /dev/ttyUSB0 -b 115200
```

After power-on + bitstream load, the FSM auto-starts one tile computation.
Expected UART output within ~1 ms:

```
D
```

(The letter 'D' = 0x44 is transmitted by the UART stub on `done_pulse`. A full
production design would send the hex psum values.)

If no output is received:
1. Verify TP5 (UART\_TX) toggles with an oscilloscope during the computation window.
2. Check UART timing: TP5 should show 115200 baud rate symbols (8.68 us bit width).
3. Verify FPGA\_GPIO0 is correctly mapped in the LPF constraints file.

---

## Phase 6 — SPI Flash Connectivity

The carrier includes a W25Q128 SPI NOR flash. The current accelerator bitstream
does not consume flash data yet, so this phase uses a minimal SPI read-ID test
bitstream.

### 6.1 SPI Read-ID with Logic Analyser

Attach a logic analyser to SPI_SCK, SPI_MOSI, SPI_MISO, and SPI_CS_FLASH.

```python
# Using FPGA soft-SPI bit-bang in a separate test bitstream:
# W25Q128 JEDEC ID command: 0x9F -> expected manufacturer 0xEF.
```

Expected response pattern: `0xEF 0x40 0x18` for common W25Q128JV variants.

### 6.2 Sector Erase / Program / Read Test

Use a sacrificial sector, write a known pattern, then read it back. Only run
this after confirming write-protect and hold pins are pulled high.

---

## Phase 7 — Full Golden-Model Verification

Run the Python script to generate reference test vectors:

```bash
python simulation/golden_model.py --gen-hex
# Produces: hex/weights.hex, hex/activations.hex, hex/expected_psum.hex
```

Load these into the FPGA via a UART command protocol (future work), trigger
a tile computation, and read back the results. Compare to `expected_psum.hex`.

**Pass criteria** for Phase 7:

| Metric | Threshold |
|---|---|
| Bit-exact psum match | 100% (all 4 output columns) |
| Tile done latency | ≤ 30 µs at 48 MHz |
| Total board current at 5 V | ≤ 200 mA during compute |
| LED D5 heartbeat | Blinking continuously |

---

## Known Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| CC resistors wrong value → no 5 V negotiation | Low | Measure R1/R2 before power-on (Phase 0) |
| Buck output voltage off → FPGA VCCCORE out of spec | Medium | Verify R6/R7 values; measure TP3 in Phase 1 |
| FPGA module not seated properly | Low | Inspect under magnification; gentle press-fit check |
| SPI flash timing violation at high speed | Medium | Start at 5-10 MHz; increase after confirmed working |
| Systolic array psum mismatch | Low | Trace from RTL: check mac\_cell.v sign-extension line |
| Feather header pin mapping wrong in LPF | Medium | Cross-check hardware/tensorrail\_mini.lpf against OrangeCrab schematic |

---

## Test Equipment

| Item | Minimum Spec | Example Model |
|---|---|---|
| Bench power supply | 0–10 V, 1 A, current-limiting | Rigol DP832 |
| Oscilloscope | 100 MHz, 200 MSa/s, 2-channel | Rigol DS1054Z |
| Multimeter | 4-digit | Any |
| USB microscope / loupe | 10× | Any |
| Logic analyser (optional) | 8-channel, 24 MHz | Saleae Logic 8 |
| JTAG adapter | FTDI FT2232H-based | openFPGALoader compatible |

---

## Revision History

| Rev | Date | Author | Changes |
|---|---|---|---|
| 0.1 | 2024-01-15 | TensorRail Contributors | Initial release |
