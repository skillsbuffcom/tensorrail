#!/usr/bin/env python3
"""
golden_model.py — NumPy INT8 Golden Reference for the TensorRail-Mini Systolic Array
TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept

Overview
--------
This script is the software ground-truth for the 4×4 INT8 weight-stationary
systolic array implemented in rtl/systolic_array.v.  It computes the same
arithmetic as the hardware so that simulation results can be verified bit-exact.

INT8 Quantised Matrix Multiplication
-------------------------------------
A standard floating-point matrix multiply C = A @ W accumulates products of
real numbers.  In a quantised accelerator every value is first mapped to a
signed 8-bit integer (INT8, range -128 … +127):

    scale = max(|x|) / 127          # per-tensor symmetric quantisation
    q     = clip(round(x / scale), -128, 127)   # INT8 representative

The hardware performs the multiply-accumulate in INT32 to avoid overflow:

    C_int32[m, n] = sum_k( A_int8[m, k] * W_int8[k, n] )   (K terms)

For a 4×4 array with K=4: max product per cell = 127*127 = 16 129 (fits INT16),
max accumulated value = 16 129 * 4 = 64 516 (fits INT17, well within INT32).

To recover floating-point outputs after the array:
    C_float ≈ C_int32 * scale_A * scale_W   (requantisation — not in RTL yet)

This file mirrors the hardware arithmetic exactly:
  - Signed INT8 inputs, sign-extended to INT32 before multiplication
  - No saturation or rounding inside the accumulation loop
  - Output is INT32 (no requantisation)

Usage
-----
  python golden_model.py                    # print matrices + run all tests
  python golden_model.py --csv              # also write expected_result.csv
  python golden_model.py --benchmark 1000   # INT8 vs FP32 SNR analysis
  python golden_model.py --gen-hex          # write hex/ vectors for Verilog TB

Requirements: numpy  (pip install numpy)
"""

import argparse
import csv
import os
import sys

import numpy as np

# ── RTL parameters (must match top-level Verilog parameters) ─────────────────
ROWS       = 4          # Systolic array rows    (MAC cells per column)
COLS       = 4          # Systolic array columns (MAC cells per row)
DATA_WIDTH = 8          # Operand width in bits
ACC_WIDTH  = 32         # Accumulator width in bits

INT8_MIN  = -(1 << (DATA_WIDTH - 1))       # -128
INT8_MAX  =  (1 << (DATA_WIDTH - 1)) - 1   #  127
INT32_MIN = -(1 << (ACC_WIDTH  - 1))
INT32_MAX =  (1 << (ACC_WIDTH  - 1)) - 1

# ── Canonical demo matrices ───────────────────────────────────────────────────
# These two 4×4 INT8 matrices are the default "golden" inputs.
# They are deterministic, human-readable, and exercise:
#   - positive and negative values
#   - off-diagonal structure (not just identity or all-same)
#   - non-trivial partial sums that are easy to verify by hand
#
# A is the activation matrix  (shape [ROWS, COLS] = [4, 4])
# W is the weight matrix      (shape [COLS, COLS] = [4, 4], i.e. [K, N])
#
# Handcrafted so that C = A @ W can be checked with pencil and paper:
#   Row 0 of A = [ 1,  2,  3,  4]
#   Row 1 of A = [ 5,  6,  7,  8]
#   Row 2 of A = [-1, -2, -3, -4]
#   Row 3 of A = [10,  0,  0, -5]
#
#   Col 0 of W = [1, 1, 1, 1]  (all-ones column)
#   Col 1 of W = [1,-1, 1,-1]  (alternating)
#   Col 2 of W = [2, 0, 2, 0]  (even-row scale)
#   Col 3 of W = [0, 0, 0,127] (single-entry extreme)

A_DEMO = np.array([
    [ 1,  2,  3,   4],
    [ 5,  6,  7,   8],
    [-1, -2, -3,  -4],
    [10,  0,  0,  -5],
], dtype=np.int8)

W_DEMO = np.array([
    [1,  1, 2,   0],
    [1, -1, 0,   0],
    [1,  1, 2,   0],
    [1, -1, 0, 127],
], dtype=np.int8)

# Expected result (computed once here; verified below in main)
# C_DEMO[m, n] = sum_k A_DEMO[m,k] * W_DEMO[k,n]
#
# Row 0: [1+2+3+4, 1-2+3-4, 2+6, 508]  = [10, -2, 8, 508]
# Row 1: [5+6+7+8, 5-6+7-8, 10+14, 1016] = [26, -2, 24, 1016]
# Row 2: [-1-2-3-4, -1+2-3+4, -2-6, -508] = [-10, 2, -8, -508]
# Row 3: [10+0+0-5, 10+0+0+5, 20+0, -635] = [5, 15, 20, -635]
C_DEMO_EXPECTED = np.array([
    [  10,  -2,   8,   508],
    [  26,  -2,  24,  1016],
    [ -10,   2,  -8,  -508],
    [   5,  15,  20,  -635],
], dtype=np.int32)


# ── Core computation ──────────────────────────────────────────────────────────

def systolic_matmul(A: np.ndarray, W: np.ndarray) -> np.ndarray:
    """
    INT8 matrix multiply matching the weight-stationary hardware dataflow.

    Parameters
    ----------
    A : int8 array, shape [M, K]   — activation matrix
    W : int8 array, shape [K, N]   — weight matrix

    Returns
    -------
    C : int32 array, shape [M, N]  — partial sum output

    The triple loop is intentionally explicit to mirror the cycle-accurate
    systolic movement: activations ripple west→east, weights are stationary,
    partial sums drain north→south and accumulate across K inner steps.
    For hardware with K=ROWS=COLS=4 this is a 4×4 tile; larger matrices are
    broken into tiles by software (not implemented in v0.1 RTL).
    """
    assert A.dtype == np.int8, f"A must be int8, got {A.dtype}"
    assert W.dtype == np.int8, f"W must be int8, got {W.dtype}"
    assert A.shape[1] == W.shape[0], \
        f"Inner dimension mismatch: A{A.shape} @ W{W.shape}"

    M, K = A.shape
    _K, N = W.shape
    C  = np.zeros((M, N), dtype=np.int32)
    A32 = A.astype(np.int32)   # sign-extend INT8 to INT32 before multiply
    W32 = W.astype(np.int32)

    for m in range(M):
        for n in range(N):
            acc = np.int32(0)
            for k in range(K):
                # Each step mirrors one MAC cell: acc += a_in * weight_stationary
                acc = np.int32(acc + A32[m, k] * W32[k, n])
            C[m, n] = acc
    return C


def quantise(x: np.ndarray, scale: float) -> np.ndarray:
    """Symmetric per-tensor quantisation → INT8."""
    return np.clip(
        np.round(x.astype(np.float64) / scale), INT8_MIN, INT8_MAX
    ).astype(np.int8)


def dequantise(C: np.ndarray, scale_a: float, scale_w: float) -> np.ndarray:
    """Map INT32 accumulator back to float32 for SNR comparison."""
    return C.astype(np.float64) * scale_a * scale_w


# ── Pretty-print helpers ──────────────────────────────────────────────────────

def _fmt_int8(v: int) -> str:
    return f"{v:4d}"

def _fmt_int32(v: int) -> str:
    return f"{v:7d}"

def print_matrix(name: str, M: np.ndarray, fmt_fn) -> None:
    """Print a 2-D matrix with a header label."""
    rows, cols = M.shape
    print(f"  {name}  ({rows}×{cols} {M.dtype}):")
    for r in range(rows):
        row_str = "  ".join(fmt_fn(int(M[r, c])) for c in range(cols))
        print(f"    [{row_str}]")


# ── Demo: print inputs and result ─────────────────────────────────────────────

def run_demo() -> np.ndarray:
    """
    Compute and pretty-print the canonical demo matrix multiply.

    Returns the INT32 result matrix C so the caller can export it.
    """
    print("=" * 64)
    print("  TensorRail-Mini  4×4 INT8 Matrix Multiply — Demo")
    print("=" * 64)
    print()
    print("  C = A × W   (INT8 inputs, INT32 accumulation)")
    print()
    print_matrix("A (activations)", A_DEMO, _fmt_int8)
    print()
    print_matrix("W (weights)    ", W_DEMO, _fmt_int8)
    print()

    C = systolic_matmul(A_DEMO, W_DEMO)

    print_matrix("C (result)     ", C, _fmt_int32)
    print()

    # Sanity-check against hand-computed expected values
    if not np.array_equal(C, C_DEMO_EXPECTED):
        print("[FAIL] Demo result does not match expected C_DEMO_EXPECTED")
        print("       Expected:")
        print_matrix("  expected", C_DEMO_EXPECTED, _fmt_int32)
        sys.exit(1)
    else:
        print("  [PASS] Demo result matches hand-computed expected values")

    # Hex dump — useful for comparing against Verilog waveforms
    print()
    print("  C in hex (row-major, INT32 two's-complement):")
    for r in range(ROWS):
        row_hex = "  ".join(
            f"0x{int(C[r, c]) & 0xFFFFFFFF:08X}" for c in range(COLS)
        )
        print(f"    row {r}: [{row_hex}]")

    print()
    return C


# ── Testbench vector tests (must match tb_systolic_array.v exactly) ──────────

def test_identity() -> None:
    """
    TEST 1: Identity weight matrix.
    W = I₄ (diagonal ones).  A = [[1, 2, 3, 4]].
    psum[c] = A[0, c].  Expected: [[1, 2, 3, 4]].
    Matches tb_systolic_array.v TEST 1.
    """
    W = np.eye(COLS, dtype=np.int8)
    A = np.arange(1, ROWS + 1, dtype=np.int8).reshape(1, ROWS)
    C = systolic_matmul(A, W)
    expected = A.astype(np.int32)
    assert np.array_equal(C, expected), \
        f"[FAIL] Test 1: Identity\n  got {C}\n  exp {expected}"
    print("[PASS] Test 1: Identity weight matrix  — psum = [1, 2, 3, 4]")


def test_all_ones() -> None:
    """
    TEST 2: All-ones weight matrix.
    W = 1 everywhere.  A = [[2, 2, 2, 2]].
    psum[c] = 2×ROWS = 8 for all c.  Expected: [[8, 8, 8, 8]].
    Matches tb_systolic_array.v TEST 2.
    """
    W = np.ones((ROWS, COLS), dtype=np.int8)
    A = np.full((1, ROWS), fill_value=2, dtype=np.int8)
    C = systolic_matmul(A, W)
    expected = np.full((1, COLS), fill_value=2 * ROWS, dtype=np.int32)
    assert np.array_equal(C, expected), \
        f"[FAIL] Test 2: All-ones\n  got {C}\n  exp {expected}"
    print(f"[PASS] Test 2: All-ones weight matrix  — psum = [{2*ROWS}]*{COLS}")


def test_negative_weights() -> None:
    """
    TEST 3: Signed negative weights.
    W = -1 everywhere (0xFF in INT8).  A = [[3, 3, 3, 3]].
    psum[c] = (-1)×3×ROWS = -12 = 0xFFFFFFF4 for all c.
    Matches tb_systolic_array.v TEST 3.
    """
    W = np.full((ROWS, COLS), fill_value=-1, dtype=np.int8)
    A = np.full((1, ROWS), fill_value=3, dtype=np.int8)
    C = systolic_matmul(A, W)
    expected_val = -3 * ROWS  # -12
    expected = np.full((1, COLS), fill_value=expected_val, dtype=np.int32)
    assert np.array_equal(C, expected), \
        f"[FAIL] Test 3: Negative weight\n  got {C}\n  exp {expected}"
    print(f"[PASS] Test 3: Signed negative weights — psum = [{expected_val}]*{COLS}"
          f"  (0x{expected_val & 0xFFFFFFFF:08X})")


def test_max_values() -> None:
    """
    TEST 4: Maximum INT8 values (+127 × +127).
    W = +127 everywhere.  A = [[127, 127, 127, 127]].
    Per cell: 127×127 = 16 129.  Accumulated over ROWS=4: 64 516 = 0x0000FC04.
    No INT32 overflow: 64 516 << 2^31 - 1 ≈ 2.1×10⁹.
    Matches tb_systolic_array.v TEST 4.
    """
    W = np.full((ROWS, COLS), fill_value=127, dtype=np.int8)
    A = np.full((1,  ROWS), fill_value=127, dtype=np.int8)
    C = systolic_matmul(A, W)
    expected_val = 127 * 127 * ROWS   # 64 516
    expected = np.full((1, COLS), fill_value=expected_val, dtype=np.int32)
    assert np.array_equal(C, expected), \
        f"[FAIL] Test 4: Max INT8\n  got {C}\n  exp {expected}"
    print(f"[PASS] Test 4: Max INT8 values         — psum = [{expected_val}]*{COLS}"
          f"  (0x{expected_val & 0xFFFFFFFF:08X})")


def run_tb_tests() -> None:
    """Run all four testbench-vector checks and report."""
    print("-" * 64)
    print("  Testbench vector checks (matching tb_systolic_array.v)")
    print("-" * 64)
    test_identity()
    test_all_ones()
    test_negative_weights()
    test_max_values()
    print()


# ── CSV export ────────────────────────────────────────────────────────────────

def export_csv(C: np.ndarray, path: str = "expected_result.csv") -> None:
    """
    Write the INT32 result matrix to a CSV file.

    Format: one row per matrix row, columns separated by commas.
    Signed decimal values — easy to import into spreadsheets or Python.
    """
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([f"col_{c}" for c in range(C.shape[1])])  # header
        for r in range(C.shape[0]):
            writer.writerow([int(C[r, c]) for c in range(C.shape[1])])
    print(f"[INFO] Wrote expected result to {path}")


# ── Quantisation SNR benchmark ────────────────────────────────────────────────

def snr_benchmark(n_trials: int = 1000, seed: int = 42) -> None:
    """
    Measure signal-to-noise ratio between FP32 reference and INT8 quantised output.

    Methodology for each trial:
      1.  Draw A, W ~ N(0,1) as FP32.
      2.  Symmetric per-tensor quantisation → INT8 with their own scales.
      3.  INT8 matmul via systolic_matmul(), then dequantise back to FP64.
      4.  SNR = 10 log10( ||C_ref||² / ||C_ref - C_deq||² ).

    For random Gaussian INT8 inputs, mean SNR > 30 dB is typical and sufficient
    for inference workloads where accuracy degrades < 1 % vs FP32.
    """
    rng  = np.random.default_rng(seed)
    snrs = []

    for _ in range(n_trials):
        A_fp = rng.standard_normal((ROWS, COLS)).astype(np.float32)
        W_fp = rng.standard_normal((COLS, COLS)).astype(np.float32)

        scale_a = float(np.max(np.abs(A_fp))) / 127.0 + 1e-10
        scale_w = float(np.max(np.abs(W_fp))) / 127.0 + 1e-10

        A_i8 = quantise(A_fp, scale_a)
        W_i8 = quantise(W_fp, scale_w)

        C_ref = A_fp.astype(np.float64) @ W_fp.astype(np.float64)
        C_i8  = systolic_matmul(A_i8, W_i8)
        C_deq = dequantise(C_i8, scale_a, scale_w)

        signal = float(np.sum(C_ref ** 2))
        noise  = float(np.sum((C_ref - C_deq) ** 2))
        if noise > 0:
            snrs.append(10.0 * np.log10(signal / noise))

    mean_snr = float(np.mean(snrs))
    min_snr  = float(np.min(snrs))
    print(f"[INFO] SNR over {n_trials} trials (seed={seed}):")
    print(f"         mean = {mean_snr:.1f} dB")
    print(f"         min  = {min_snr:.1f} dB")
    assert mean_snr > 30.0, \
        f"[FAIL] Mean SNR {mean_snr:.1f} dB is below the 30 dB threshold"
    print("[PASS] Quantisation SNR > 30 dB  (INT8 precision acceptable)\n")


# ── $readmemh hex file generation ─────────────────────────────────────────────

def _write_hex(data: np.ndarray, path: str) -> None:
    """Write a flat array as $readmemh-compatible hex, one value per line."""
    with open(path, "w") as f:
        for v in data.flatten():
            if data.dtype == np.int8:
                f.write(f"{int(v) & 0xFF:02X}\n")
            elif data.dtype == np.int32:
                f.write(f"{int(v) & 0xFFFFFFFF:08X}\n")
            else:
                raise ValueError(f"Unsupported dtype {data.dtype}")


def generate_hex_files(out_dir: str = "hex") -> None:
    """
    Write three $readmemh files for use in Verilog simulation:

      weights.hex       — COLS×ROWS INT8 weights, column-major (matches
                          the serial shift-in order of systolic_array.v)
      activations.hex   — 1×ROWS INT8 activation row
      expected_psum.hex — 1×COLS INT32 expected partial sums

    Seed is fixed so the testbench is bit-reproducible across runs.
    """
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(0xABCD_1234)

    W = rng.integers(INT8_MIN, INT8_MAX + 1, (ROWS, COLS), dtype=np.int8)
    A = rng.integers(INT8_MIN, INT8_MAX + 1, (1,   ROWS),  dtype=np.int8)
    C = systolic_matmul(A, W)

    # Column-major weight ordering matches hardware shift-in sequence
    W_colmaj = W.T.copy()

    _write_hex(W_colmaj, os.path.join(out_dir, "weights.hex"))
    _write_hex(A,        os.path.join(out_dir, "activations.hex"))
    _write_hex(C,        os.path.join(out_dir, "expected_psum.hex"))
    print(f"[INFO] Wrote $readmemh test vectors → {out_dir}/")
    print(f"         weights.hex       ({COLS}×{ROWS} INT8, column-major)")
    print(f"         activations.hex   (1×{ROWS} INT8)")
    print(f"         expected_psum.hex (1×{COLS} INT32)")
    print()


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="TensorRail-Mini — INT8 Systolic Array Golden Model")
    parser.add_argument(
        "--csv", action="store_true",
        help="Export demo result matrix to expected_result.csv")
    parser.add_argument(
        "--csv-path", default="expected_result.csv", metavar="PATH",
        help="Output path for --csv (default: expected_result.csv)")
    parser.add_argument(
        "--benchmark", type=int, default=0, metavar="N",
        help="Run N-trial INT8 vs FP32 SNR analysis (0 = skip)")
    parser.add_argument(
        "--gen-hex", action="store_true",
        help="Write $readmemh hex test vectors to hex/ directory")
    args = parser.parse_args()

    # 1. Print demo matrices and result
    C_demo = run_demo()

    # 2. Optionally export CSV
    if args.csv:
        export_csv(C_demo, args.csv_path)

    # 3. Testbench vector verification
    run_tb_tests()

    # 4. Optional SNR benchmark
    if args.benchmark > 0:
        snr_benchmark(args.benchmark)

    # 5. Optional hex file generation
    if args.gen_hex:
        generate_hex_files()

    print("All checks passed.")


if __name__ == "__main__":
    main()
