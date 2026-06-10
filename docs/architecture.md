# TensorRail-Mini Architecture Reference

> **Status**: Simulation prototype. No physical board has been fabricated.
> Resource and timing figures are analytical until Yosys/nextpnr reports are
> generated on the target machine.

---

## 1. System Overview

TensorRail-Mini pairs a commercial **Lattice ECP5 Feather module** (e.g., OrangeCrab 85F) with a minimal carrier board to demonstrate a small INT8 systolic-array matrix-multiply accelerator.

The module/carrier approach was chosen deliberately over a bare FPGA design:
- Eliminates BGA soldering, DDR3 routing, and power-sequencing complexity from the proof-of-concept.
- Keeps the carrier BOM under $15 and manufacturable by any two-layer PCB house.
- Lets the RTL proof-of-concept run on real silicon cheaply while hardware is iterated.

```
Host (USB-C cable, power + UART)
        │
        ▼
  ┌─────────────────────────────────────────────────────┐
  │              TensorRail-Mini Carrier Board           │
  │                                                     │
  │  USB-C (J1)  →  power-only 5 V input               │
  │                                                     │
  │  5V VBUS → Buck (U1) → 3.3V                         │
  │  3.3V    → Buck (U2) → 1.2V                         │
  │                          │                          │
  │                     INA219 current monitor          │
  │                          ▼                          │
  │                           ┌────────────────────┐    │
  │  W25Q128 SPI flash ─SPI─►│  ECP5 FPGA Module  │    │
  │  50 MHz oscillator ─CLK─►│  (OrangeCrab 85F)  │    │
  │                           │                    │    │
  │                           │  ┌──────────────┐  │    │
  │                           │  │  4×4 INT8    │  │    │
  │                           │  │  Systolic    │  │    │
  │                           │  │  Array       │  │    │
  │                           │  └──────────────┘  │    │
  │                           │  Control FSM       │    │
  │                           │  UART Status Port  │    │
  │                           └────────────────────┘    │
  │  LEDs D2–D5 ←── FPGA GPIO12–15                      │
  │  JTAG J2   ←── FPGA JTAG pins                       │
  └─────────────────────────────────────────────────────┘
```

---

## 2. Systolic Array Architecture

### 2.1 Weight-Stationary Dataflow

The array uses a **weight-stationary** strategy:

| Datum | Direction | Registered? |
|---|---|---|
| Activations (A) | West → East | Yes, one register per cell per cycle |
| Weights (W) | Stationary | Held in per-cell register during tile compute |
| Partial sums | North → South | Accumulated and forwarded each cycle |

**Trade-off**: Weight-stationary minimises weight-memory reads (weights loaded once per tile). The cost is a full weight reload between tiles with different weights, which adds `COLS × K` cycles of load overhead.

### 2.2 MAC Cell Micro-Architecture

Each of the 16 cells (4 rows × 4 columns) contains:

```
          a_in ──────────────────► a_out
                      │
                  [A_reg]
                      │  signed 8×8
               ┌─────▼──────┐
    b_in ──────►  INT8 × INT8│──► 16-bit product
    (static)   └─────────────┘
                      │  sign-extend to 32 bits
               ┌──────▼──────┐
    acc_in ────►    INT32 +   │──► acc_out
               └─────────────┘
```

Critical path: `A_reg → multiplier → adder → P_reg`.
Estimated at ~4 ns on ECP5 at default speed grade (200 MHz is feasible for this path).

### 2.3 Array Timing

```
Cycle:   0    1    2    3    4    5    6    7    8
         │    │    │    │    │    │    │    │    │
act[0] ──┤ C00 │    │    │    │    │    │    │    │
act[1]   │  ──┤ C10 │    │    │    │    │    │    │
act[2]   │    │  ──┤ C20 │    │    │    │    │    │
act[3]   │    │    │  ──┤ C30 │    │    │    │    │
         │    │    │    │    │    │    │    │    │
psum[0] arrives at south edge after ROWS = 4 cycles (cycle 4)
psum[1] arrives at cycle 5, psum[2] at 6, psum[3] at 7
```

For a single-row activation (1×K matmul): total latency = ROWS + K - 1 cycles.

### 2.4 Tile Computation Phases

| Phase | Duration (cycles) | Description |
|---|---|---|
| LOAD\_W | COLS × K = 4×4 = 16 | Shift weights into all columns |
| COMPUTE | M = 4 | Inject 4 activation rows |
| DRAIN | ROWS = 4 | Wait for partial sums to reach south edge |
| **Total** | **24 cycles** | Plus CSR overhead (~2 cycles) |

At 48 MHz: 24 cycles × 20.8 ns = **~500 ns per 4×4×4 tile**.
Useful arithmetic: 4×4×4×2 = 128 ops → 128 / 500ns = **256 MOPS** (INT8).

At 200 MHz (with PLL): ~61 MOPS per tile would achieve ~1 GOPS sustained.
These are analytical estimates; actual performance depends on memory bandwidth.

---

## 3. Memory Subsystem

### 3.1 On-Chip BRAM Budget (ECP5 LFE5U-85F = 208 × 9 Kb EBR)

| Usage | EBR blocks | Size |
|---|---|---|
| Weight buffer (4×4 INT8, double-buffered) | 1 | 128 bytes |
| Activation line buffer | 1 | 64 bytes |
| Output accumulator buffer | 1 | 64 bytes |
| FSM state + CSR | — | Distributed RAM |
| **Total** | **3** | **<1 Kb** |

The 4×4 array is tiny; the real BRAM budget would dominate in a 16×16 design.

### 3.2 External Memory and I/O

The v0.2 carrier includes a W25Q128 SPI NOR flash and routes the same SPI bus to
the expansion header. The present RTL still uses stubbed weight and activation
sources inside `control_fsm.v`; a real DMA path from external memory is future
work.

Planned next memory options:
- Add SPI/QPI PSRAM on a future carrier spin for tensor storage.
- Use the 40-pin expansion header for a daughtercard memory interface.
- Stream small vectors over a UART/SPI debug bridge during bring-up.

---

## 4. Clock Architecture

| Domain | Source | Frequency | Notes |
|---|---|---|---|
| `clk` | OrangeCrab 48 MHz oscillator | 48 MHz | Current top.v passthrough |
| `clk_fast` (future) | ECP5 EHXPLLL | 100–200 MHz | For higher throughput |
| `uart_clk` | Derived from `clk` | (baud divider) | 115200 baud at 48 MHz |

The ECP5 EHXPLLL PLL is not instantiated in the current prototype. Adding it
would allow the systolic array to run at 100–200 MHz with a simple CLKI_DIV /
CLKFB_DIV / CLKOP_DIV configuration (see ECP5 sysCLOCK PLL usage guide).

---

## 5. CSR Register Map

Base: word-addressed via simple combinatorial bus in `control_fsm.v`.

| Address | Register | Bits | R/W | Description |
|---|---|---|---|---|
| 0x00 | CTRL | [0] start | W1S | Write 1 to begin tile computation |
| | | [1] sw\_reset | W1S | Soft reset to IDLE state |
| 0x04 | STATUS | [0] busy | RO | Asserted while not in IDLE or DONE |
| | | [1] done | RO | Pulses for one cycle on completion |
| | | [5:3] state\_dbg | RO | Current FSM state code |
| 0x08 | TILE\_M | [15:0] | RW | Activation rows per tile |
| 0x0C | TILE\_N | [15:0] | RW | Weight / output columns |
| 0x10 | TILE\_K | [15:0] | RW | Inner dimension (weight shift cycles) |

---

## 6. INT8 Quantisation Model

### 6.1 Symmetric per-tensor quantisation

```
scale = max(|x|) / 127
q     = round(x / scale),  clamped to [-128, 127]
x ≈ q × scale
```

### 6.2 Accumulator precision analysis (4×4 array)

```
Max single product:  127 × 127 = 16 129   (fits in INT16)
Max accumulation:    16 129 × 4 = 64 516  (fits in INT17 → safe in INT32)
```

No overflow is possible in the 4×4 prototype.  For a 16×16 array with K=16:
`127 × 127 × 16 = 258 064` — still well within INT32 (max ~2.1 billion).

### 6.3 Requantisation (future, not implemented in RTL)

After the systolic array, each INT32 accumulator must be scaled back to INT8
for the next layer:

```
scale_out = max(|C_fp|) / 127
out_int8  = clip(round(C_int32 × scale_in × scale_w / scale_out), -128, 127)
```

The Python golden model includes `requantise_output()` for reference.

---

## 7. Resource Utilisation Estimates

Target: **LFE5U-85F** (ECP5 85K LUT variant on OrangeCrab).

| Resource | 4×4 Estimate | 85F Available |
|---|---|---|
| LUT4 | ~800 | 83 640 |
| DFF | ~400 | 83 640 |
| DSP (MULT18X18D) | 16 | 156 |
| EBR (9 Kb) | 3 | 208 |

The 4×4 array is very small — under 1% of the ECP5-85F.
A 16×16 array would use ~3 200 LUTs and 64 DSPs (~40% of DSP tiles on ECP5-85F).

---

## 8. Known Limitations and Future Work

| Item | Status | Notes |
|---|---|---|
| External-memory DMA | Not implemented | FSM uses stub data; real weights need DMA or host streaming |
| PLL for higher frequency | Not instantiated | Add EHXPLLL for 100–200 MHz operation |
| Requantisation unit | Python only | RTL requant block is a future milestone |
| Multi-tile tiling | Not implemented | Single-tile proof of concept only |
| AXI4-Lite CSR bus | Not implemented | Simple combinatorial bus used in sim |
| Verilator lint | Not verified | Run `verilator --lint-only rtl/*.v` to check |
