#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="$ROOT/rtl/sim"

command -v iverilog >/dev/null 2>&1 || {
  echo "iverilog is required for RTL simulation." >&2
  exit 127
}
command -v vvp >/dev/null 2>&1 || {
  echo "vvp is required for RTL simulation." >&2
  exit 127
}

(
  cd "$SIM"
  iverilog -g2012 -o tb_sa \
    ../mac_cell.v \
    ../systolic_array.v \
    tb_systolic_array.v
  vvp tb_sa
)

echo "Wrote rtl/sim/tensorrail_tb.vcd"

