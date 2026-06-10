#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCB="$ROOT/hardware/tensorrail_mini.kicad_pcb"
OUT="$ROOT/hardware/gerbers"

command -v kicad-cli >/dev/null 2>&1 || {
  echo "kicad-cli is required to export Gerbers." >&2
  exit 127
}

mkdir -p "$OUT"

kicad-cli pcb export gerbers \
  --output "$OUT" \
  --layers "F.Cu,B.Cu,F.Paste,B.Paste,F.Mask,B.Mask,F.SilkS,B.SilkS,Edge.Cuts" \
  "$PCB"

kicad-cli pcb export drill \
  --output "$OUT" \
  --format excellon \
  "$PCB"

(
  cd "$OUT"
  zip -j tensorrail_mini_gerbers.zip ./*.gbr ./*.drl 2>/dev/null
)

echo "Wrote $OUT/tensorrail_mini_gerbers.zip"

