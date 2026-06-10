#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAD="$ROOT/mechanical/tensorrail_enclosure.scad"

command -v openscad >/dev/null 2>&1 || {
  echo "openscad is required to export STL files." >&2
  exit 127
}

openscad -D 'PART="base"' -o "$ROOT/mechanical/base.stl" "$SCAD"
openscad -D 'PART="lid"' -o "$ROOT/mechanical/lid.stl" "$SCAD"
openscad -D 'PART="exploded"' -o "$ROOT/mechanical/exploded.stl" "$SCAD"

echo "Wrote mechanical/base.stl, lid.stl, and exploded.stl"

