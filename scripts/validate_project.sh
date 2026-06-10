#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Python golden model =="
python3 simulation/golden_model.py

echo
echo "== Optional tool checks =="
for tool in iverilog vvp ngspice openscad kicad-cli verilator; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "FOUND $tool: $(command -v "$tool")"
  else
    echo "MISSING $tool"
  fi
done

echo
echo "Run these when tools are installed:"
echo "  scripts/run_rtl_sim.sh"
echo "  ngspice -b simulation/power_core_load_step.cir"
echo "  scripts/export_mechanical.sh"
echo "  scripts/export_gerbers.sh"

