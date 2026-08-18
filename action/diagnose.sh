#!/bin/bash
# GitHub Action entry for launchdx. Calls the real launchdx CLI.
# It does not diagnose on its own and does not modify the target.
set -eu

path="${LAUNCHDX_PATH:-}"
bin="${LAUNCHDX_BIN:-}"
json="${LAUNCHDX_JSON:-true}"
report_path="${LAUNCHDX_REPORT_PATH:-launchdx-report.json}"
fail_on_blocker="${LAUNCHDX_FAIL_ON_BLOCKER:-true}"
fail_on_error="${LAUNCHDX_FAIL_ON_ERROR:-true}"
allow_install="${LAUNCHDX_INSTALL:-true}"

write_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >>"$GITHUB_OUTPUT"
  fi
}

if [ -z "$path" ]; then
  echo "launchdx-action: input 'path' is required" >&2
  write_output "exit-code" "64"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 64
fi

if [ ! -e "$path" ]; then
  echo "launchdx-action: target does not exist: $path" >&2
  write_output "exit-code" "66"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 66
fi

if [ -z "$bin" ] && command -v launchdx >/dev/null 2>&1; then
  bin="$(command -v launchdx)"
fi

if [ -z "$bin" ]; then
  if [ "$allow_install" != "true" ]; then
    echo "launchdx-action: launchdx is not installed and install is disabled" >&2
    write_output "exit-code" "69"
    write_output "launch-status" ""
    write_output "report-path" ""
    exit 69
  fi
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "launchdx-action: diagnosis requires a macOS runner" >&2
    write_output "exit-code" "78"
    write_output "launch-status" ""
    write_output "report-path" ""
    exit 78
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "launchdx-action: Homebrew is required to install launchdx" >&2
    write_output "exit-code" "69"
    write_output "launch-status" ""
    write_output "report-path" ""
    exit 69
  fi
  brew tap ChloeVPin/launchdx
  brew install launchdx
  bin="$(command -v launchdx)"
fi

if [ ! -x "$bin" ]; then
  echo "launchdx-action: launchdx is not executable: $bin" >&2
  write_output "exit-code" "69"
  write_output "launch-status" ""
  write_output "report-path" ""
  exit 69
fi

mkdir -p "$(dirname "$report_path")"

set +e
if [ "$json" = "true" ]; then
  "$bin" diagnose "$path" --json --no-color >"$report_path"
  status=$?
else
  "$bin" diagnose "$path" --no-color >"$report_path"
  status=$?
fi
set -e

launch_status=""
if [ "$json" = "true" ] && [ -s "$report_path" ] && command -v python3 >/dev/null 2>&1; then
  launch_status="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("launchStatus") or "")
except Exception:
    print("")
' "$report_path")"
fi

write_output "exit-code" "$status"
write_output "launch-status" "$launch_status"
write_output "report-path" "$report_path"

echo "launchdx-action: exit $status launch-status=${launch_status:-unknown} report=$report_path"

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -eq 1 ]; then
  if [ "$fail_on_blocker" = "true" ]; then
    echo "launchdx-action: confirmed launch blocker" >&2
    exit 1
  fi
  echo "launchdx-action: blocker recorded; fail-on-blocker is false"
  exit 0
fi

if [ "$fail_on_error" = "true" ]; then
  echo "launchdx-action: launchdx failed with exit $status" >&2
  exit "$status"
fi

echo "launchdx-action: non-blocker failure recorded; fail-on-error is false"
exit 0
