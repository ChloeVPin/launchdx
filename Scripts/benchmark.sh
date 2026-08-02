#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARY="$ROOT/.build/release/launchdx"
OUTPUT_DIR="${1:-/tmp/launchdx-benchmark}"

if [ ! -x "$BINARY" ]; then
  echo "Release binary not found. Run swift build -c release first." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
sh "$ROOT/Scripts/make-fixtures.sh" "$OUTPUT_DIR/base" >/dev/null

ROOT_PATH="$ROOT" BINARY_PATH="$BINARY" OUTPUT_PATH="$OUTPUT_DIR" python3 - <<'PY'
import json
import os
import pathlib
import shutil
import statistics
import subprocess
import sys
import time

root = pathlib.Path(os.environ["OUTPUT_PATH"])
binary = os.environ["BINARY_PATH"]
base = root / "base" / "Valid.app"

rows = []
for resource_count in (0, 5000):
    for nested_count in (0, 10, 50):
        app = root / f"app_{resource_count}_{nested_count}.app"
        shutil.copytree(base, app)
        resources = app / "Contents" / "Resources"
        resources.mkdir()
        for index in range(resource_count):
            (resources / f"resource_{index}.txt").write_text("launchdx benchmark payload\n")
        frameworks = app / "Contents" / "Frameworks"
        frameworks.mkdir()
        for index in range(nested_count):
            container = frameworks / f"Framework{index}.framework"
            container.mkdir()
            (container / f"Framework{index}").write_bytes(b"not a Mach-O file")

        samples = []
        for _ in range(5):
            started = time.perf_counter()
            process = subprocess.run(
                [binary, "diagnose", str(app), "--json"],
                capture_output=True,
                text=True,
            )
            elapsed = (time.perf_counter() - started) * 1000
            json.loads(process.stdout)
            samples.append(elapsed)

        samples.sort()
        rows.append({
            "resource_files": resource_count,
            "nested_containers": nested_count,
            "median_ms": round(statistics.median(samples), 1),
            "max_ms_of_5_samples": round(samples[-1], 1),
            "exit_code": process.returncode,
        })

real_targets = [
    "/Applications/Google Chrome.app",
    "/Applications/Cursor.app",
    "/Applications/Freebuff.app",
    "/Applications/Notion.app",
]
for target in real_targets:
    if not pathlib.Path(target).exists():
        continue
    started = time.perf_counter()
    process = subprocess.run(
        [binary, "diagnose", target, "--json"],
        capture_output=True,
        text=True,
    )
    elapsed = (time.perf_counter() - started) * 1000
    report = json.loads(process.stdout)
    security = (report.get("bundle") or {}).get("security") or {}
    nested = (security.get("signature") or {}).get("nested") or {}
    rows.append({
        "target": target,
        "median_ms": round(elapsed, 1),
        "observed_ms": round(elapsed, 1),
        "exit_code": process.returncode,
        "launch_status": report.get("launchStatus"),
        "inspection_status": report.get("inspectionStatus"),
        "nested_checked": len(nested.get("pathsChecked", [])),
    })

print(json.dumps(rows, indent=2, sort_keys=True))
PY
