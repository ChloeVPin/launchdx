#!/bin/bash
# Tests the GitHub Action wrapper. The fake launchdx records argv and exit
# status; the script under test is action/diagnose.sh, not a second diagnosis.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/action/diagnose.sh"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/launchdx-action-XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

fake_bin="$WORKDIR/launchdx"
args_file="$WORKDIR/args"
report="$WORKDIR/report.json"
output="$WORKDIR/github-output"
target="$WORKDIR/Valid.app"
mkdir -p "$target"

cat >"$fake_bin" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" >"${LAUNCHDX_FAKE_ARGS:?}"
status="${LAUNCHDX_FAKE_STATUS:-1}"
if printf '%s\n' "$@" | grep -q -- '--json'; then
  printf '%s\n' "${LAUNCHDX_FAKE_JSON}"
else
  printf '%s\n' "${LAUNCHDX_FAKE_TEXT:-Launch status: BLOCKED}"
fi
exit "$status"
FAKE
chmod 755 "$fake_bin" "$SCRIPT"

run_action() {
  rm -f "$args_file" "$report" "$output"
  fake_json='{"launchStatus":"blocked"}'
  if [ -n "${LAUNCHDX_FAKE_JSON:-}" ]; then
    fake_json="$LAUNCHDX_FAKE_JSON"
  fi
  LAUNCHDX_PATH="$target" \
    LAUNCHDX_BIN="$fake_bin" \
    LAUNCHDX_JSON="${LAUNCHDX_JSON:-true}" \
    LAUNCHDX_REPORT_PATH="$report" \
    LAUNCHDX_FAIL_ON_BLOCKER="${LAUNCHDX_FAIL_ON_BLOCKER:-true}" \
    LAUNCHDX_FAIL_ON_ERROR="${LAUNCHDX_FAIL_ON_ERROR:-true}" \
    LAUNCHDX_INSTALL=false \
    LAUNCHDX_FAKE_ARGS="$args_file" \
    LAUNCHDX_FAKE_STATUS="${LAUNCHDX_FAKE_STATUS:-1}" \
    LAUNCHDX_FAKE_JSON="$fake_json" \
    GITHUB_OUTPUT="$output" \
    bash "$SCRIPT"
}

expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@"
  local got=$?
  set -e
  if [ "$got" -ne "$expected" ]; then
    echo "expected exit $expected, got $got" >&2
    exit 1
  fi
}

expect_exit 64 env -u LAUNCHDX_PATH LAUNCHDX_INSTALL=false bash "$SCRIPT"

missing="$WORKDIR/missing.app"
expect_exit 66 env LAUNCHDX_PATH="$missing" LAUNCHDX_INSTALL=false bash "$SCRIPT"

expect_exit 1 run_action
grep -qx "diagnose" "$args_file"
grep -qx "$target" "$args_file"
grep -qx -- "--json" "$args_file"
grep -qx -- "--no-color" "$args_file"
grep -q "exit-code=1" "$output"
grep -q "launch-status=blocked" "$output"
grep -q "report-path=$report" "$output"
python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['launchStatus']=='blocked'" "$report"

LAUNCHDX_FAIL_ON_BLOCKER=false expect_exit 0 run_action
grep -q "exit-code=1" "$output"
grep -q "launch-status=blocked" "$output"

LAUNCHDX_FAKE_STATUS=0 LAUNCHDX_FAKE_JSON='{"launchStatus":"clean"}' expect_exit 0 run_action
grep -q "exit-code=0" "$output"
grep -q "launch-status=clean" "$output"

LAUNCHDX_FAKE_STATUS=66 expect_exit 66 run_action
LAUNCHDX_FAKE_STATUS=66 LAUNCHDX_FAIL_ON_ERROR=false expect_exit 0 run_action

echo "action wrapper assertions passed"
