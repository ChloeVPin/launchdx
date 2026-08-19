#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${1:-"$ROOT/.build/integration-fixtures"}
LAUNCHDX=${LAUNCHDX_BIN:-"$ROOT/.build/release/launchdx"}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "real macOS integration tests require macOS" >&2
  exit 78
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "real macOS integration tests require an Apple Silicon runner" >&2
  exit 78
fi
for tool in clang codesign spctl xattr plutil; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 69; }
done
[[ -x "$LAUNCHDX" ]] || { echo "missing launchdx binary: $LAUNCHDX" >&2; exit 69; }

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

make_app() {
  local app="$1"
  local name="$2"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.launchdx.integration.${name}</string>
<key>CFBundleExecutable</key><string>${name}</string>
<key>CFBundleName</key><string>${name}</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  cat > "$OUTPUT_DIR/${name}.c" <<'C'
#include <stdio.h>
int main(void) { puts("launchdx integration fixture"); return 0; }
C
  clang -arch arm64 -mmacosx-version-min=13.0 "$OUTPUT_DIR/${name}.c" -o "$app/Contents/MacOS/$name"
  chmod 755 "$app/Contents/MacOS/$name"
  printf 'fixture resource\n' > "$app/Contents/Resources/marker.txt"
}

run_report() {
  local app="$1"
  local output="$2"
  set +e
  "$LAUNCHDX" diagnose "$app" --json > "$output"
  local status=$?
  set -e
  python3 "$ROOT/Scripts/validate-report.py" "$output" >/dev/null
  echo "$status"
}

make_app "$OUTPUT_DIR/AdHoc.app" AdHoc
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/AdHoc.app" >/dev/null

make_app "$OUTPUT_DIR/Modified.app" Modified
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/Modified.app" >/dev/null
printf 'changed after signing\n' >> "$OUTPUT_DIR/Modified.app/Contents/Resources/marker.txt"

make_app "$OUTPUT_DIR/NestedUnsigned.app" NestedUnsigned
mkdir -p "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app/Contents/MacOS"
cp "$OUTPUT_DIR/NestedUnsigned.app/Contents/MacOS/NestedUnsigned" "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app/Contents/MacOS/UnsignedHelper"
chmod 755 "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app/Contents/MacOS/UnsignedHelper"
cat > "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.launchdx.integration.unsigned-helper</string>
<key>CFBundleExecutable</key><string>UnsignedHelper</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app" >/dev/null
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/NestedUnsigned.app" >/dev/null
rm -rf "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app/Contents/_CodeSignature"

xattr -w com.apple.quarantine '0083;00000000;launchdx.integration;00000000-0000-0000-0000-000000000001' "$OUTPUT_DIR/Modified.app"

if command -v hdiutil >/dev/null 2>&1; then
  mkdir -p "$OUTPUT_DIR/dmg-src"
  cp -R "$OUTPUT_DIR/AdHoc.app" "$OUTPUT_DIR/dmg-src/AdHoc.app"
  rm -f "$OUTPUT_DIR/AdHoc.dmg"
  hdiutil create -volname LaunchDXAdHoc -srcfolder "$OUTPUT_DIR/dmg-src" -ov -format UDZO "$OUTPUT_DIR/AdHoc.dmg" >/dev/null
fi

if command -v pkgbuild >/dev/null 2>&1; then
  mkdir -p "$OUTPUT_DIR/pkg-root"
  cp -R "$OUTPUT_DIR/AdHoc.app" "$OUTPUT_DIR/pkg-root/AdHoc.app"
  rm -f "$OUTPUT_DIR/AdHoc.pkg"
  pkgbuild --root "$OUTPUT_DIR/pkg-root" --identifier "dev.launchdx.integration.adhoc" --version "0.0.1" "$OUTPUT_DIR/AdHoc.pkg" >/dev/null
fi

codesign --verify --strict --verbose=2 "$OUTPUT_DIR/AdHoc.app" >/dev/null
if codesign --verify --strict --verbose=2 "$OUTPUT_DIR/Modified.app" >/dev/null 2>&1; then
  echo "native modified signature unexpectedly passed" >&2
  exit 1
fi
if codesign --verify --strict --verbose=2 "$OUTPUT_DIR/NestedUnsigned.app/Contents/Helpers/UnsignedHelper.app" >/dev/null 2>&1; then
  echo "native nested helper signature unexpectedly passed" >&2
  exit 1
fi

adhoc_json="$OUTPUT_DIR/AdHoc.json"
modified_json="$OUTPUT_DIR/Modified.json"
nested_json="$OUTPUT_DIR/NestedUnsigned.json"
adhoc_status=$(run_report "$OUTPUT_DIR/AdHoc.app" "$adhoc_json")
modified_status=$(run_report "$OUTPUT_DIR/Modified.app" "$modified_json")
nested_status=$(run_report "$OUTPUT_DIR/NestedUnsigned.app" "$nested_json")

dmg_json=""
dmg_status="skip"
if [[ -f "$OUTPUT_DIR/AdHoc.dmg" ]]; then
  dmg_json="$OUTPUT_DIR/AdHoc.dmg.json"
  dmg_status=$(run_report "$OUTPUT_DIR/AdHoc.dmg" "$dmg_json")
fi

pkg_json=""
pkg_status="skip"
if [[ -f "$OUTPUT_DIR/AdHoc.pkg" ]]; then
  pkg_json="$OUTPUT_DIR/AdHoc.pkg.json"
  pkg_status=$(run_report "$OUTPUT_DIR/AdHoc.pkg" "$pkg_json")
fi

python3 - "$adhoc_json" "$modified_json" "$nested_json" "$adhoc_status" "$modified_status" "$nested_status" "$dmg_json" "$dmg_status" "$pkg_json" "$pkg_status" <<'PY'
import json
import sys

adhoc, modified, nested = [json.load(open(path)) for path in sys.argv[1:4]]
statuses = [int(value) for value in sys.argv[4:7]]
dmg_path, dmg_status = sys.argv[7], sys.argv[8]
pkg_path, pkg_status = sys.argv[9], sys.argv[10]
assert statuses[0] in (0, 1), statuses
assert statuses[1] == 1, statuses
assert statuses[2] == 1, statuses
assert any(item["id"] == "signature.ad-hoc" for item in adhoc["findings"])
assert any(item["id"] == "gatekeeper.assessment" for item in adhoc["findings"])
assert any(item["id"] == "signature.invalid" for item in modified["findings"])
assert modified["bundle"]["security"]["quarantine"]["present"] is True
assert any(item["id"] in ("signature.nested-unsigned", "signature.nested-invalid") for item in nested["findings"])
adhoc_finding = next(item for item in adhoc["findings"] if item["id"] == "signature.ad-hoc")
assert adhoc_finding["status"] == "warning"
assert adhoc_finding["severity"] == "warning"
if dmg_status != "skip":
    dmg = json.load(open(dmg_path))
    assert dmg["target"]["kind"] == "disk_image"
    assert dmg["container"]["available"] is True
    assert any(item["id"] == "container.app-found" for item in dmg["findings"])
    assert any(item["id"] == "signature.ad-hoc" for item in dmg["findings"])
    print("dmg", dmg["inspectionStatus"], dmg["launchStatus"], [item["id"] for item in dmg["findings"]])
if pkg_status != "skip":
    pkg = json.load(open(pkg_path))
    assert pkg["target"]["kind"] == "installer_package"
    assert pkg["container"]["available"] is True
    assert any(item["id"] == "container.app-found" for item in pkg["findings"])
    assert any(item["id"] == "signature.ad-hoc" for item in pkg["findings"])
    print("pkg", pkg["inspectionStatus"], pkg["launchStatus"], [item["id"] for item in pkg["findings"]])
print("real macOS integration assertions passed")
for label, report in (("adhoc", adhoc), ("modified", modified), ("nested", nested)):
    print(label, report["inspectionStatus"], report["launchStatus"], [item["id"] for item in report["findings"]])
PY
