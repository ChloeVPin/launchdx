#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${1:-"$ROOT/.build/schema-fixtures"}
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

"$ROOT/.build/release/launchdx" diagnose "$OUTPUT_DIR/Missing.app" --json > "$OUTPUT_DIR/valid.json" || status=$?
status=${status:-0}
test "$status" -eq 66
python3 "$ROOT/Scripts/validate-report.py" "$OUTPUT_DIR/valid.json"

python3 - "$OUTPUT_DIR/valid.json" "$OUTPUT_DIR/invalid.json" <<'PY'
import json
import sys
source, destination = sys.argv[1:]
report = json.load(open(source))
report["unexpected"] = True
json.dump(report, open(destination, "w"))
PY

if python3 "$ROOT/Scripts/validate-report.py" "$OUTPUT_DIR/invalid.json" >/dev/null 2>&1; then
  echo "invalid report unexpectedly passed schema validation" >&2
  exit 1
fi

echo "schema report validation assertions passed"
