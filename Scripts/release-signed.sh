#!/bin/bash
set -euo pipefail

# The workflow enables this script only when RELEASE_CREDENTIALS_CONFIGURED is true.
# The script still validates every secret independently before touching a keychain.
RELEASE_CREDENTIALS_CONFIGURED=${RELEASE_CREDENTIALS_CONFIGURED:-}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNNER_TEMP=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
OUTPUT_DIR=${1:-"$ROOT/.build/release-artifacts"}
IDENTITY=${DEVELOPER_ID_APPLICATION:-}
CERTIFICATE_P12_BASE64=${APPLE_CERTIFICATE_P12_BASE64:-}
CERTIFICATE_PASSWORD=${APPLE_CERTIFICATE_PASSWORD:-}
KEYCHAIN_PASSWORD=${KEYCHAIN_PASSWORD:-}
API_KEY_ID=${APPLE_API_KEY_ID:-}
API_ISSUER_ID=${APPLE_API_ISSUER_ID:-}
API_KEY_CONTENT=${APPLE_API_KEY_CONTENT:-}

for name in RELEASE_CREDENTIALS_CONFIGURED IDENTITY CERTIFICATE_P12_BASE64 CERTIFICATE_PASSWORD KEYCHAIN_PASSWORD API_KEY_ID API_ISSUER_ID API_KEY_CONTENT; do
  if [[ -z "${!name}" ]]; then
    echo "signed release credentials are incomplete: missing $name" >&2
    exit 78
  fi
done

for tool in swift security codesign xcrun hdiutil shasum; do
  command -v "$tool" >/dev/null || { echo "missing required release tool: $tool" >&2; exit 69; }
done

KEYCHAIN="$RUNNER_TEMP/launchdx-build.keychain-db"
ORIGINAL_KEYCHAINS="$RUNNER_TEMP/launchdx-original-keychains.txt"
ORIGINAL_KEYCHAIN_ARGS=()
CERTIFICATE="$RUNNER_TEMP/launchdx-developer-id.p12"
API_KEY="$RUNNER_TEMP/AuthKey_${API_KEY_ID}.p8"
STAGING="$RUNNER_TEMP/launchdx-staging"
DMG="$OUTPUT_DIR/launchdx-${GITHUB_REF_NAME:-local}.dmg"
ZIP="$OUTPUT_DIR/launchdx-${GITHUB_REF_NAME:-local}.zip"

cleanup() {
  if [[ ${#ORIGINAL_KEYCHAIN_ARGS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAIN_ARGS[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$CERTIFICATE" "$API_KEY" "$ORIGINAL_KEYCHAINS"
  rm -rf "$STAGING"
}
trap cleanup EXIT

rm -rf "$OUTPUT_DIR" "$STAGING"
mkdir -p "$OUTPUT_DIR" "$STAGING/bin"
security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"$//' > "$ORIGINAL_KEYCHAINS"
while IFS= read -r keychain; do
  [[ -n "$keychain" ]] && ORIGINAL_KEYCHAIN_ARGS+=("$keychain")
done < "$ORIGINAL_KEYCHAINS"
printf '%s' "$CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE"
printf '%s' "$API_KEY_CONTENT" | base64 --decode > "$API_KEY"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"

swift build -c release
cp "$ROOT/.build/arm64-apple-macosx/release/launchdx" "$STAGING/bin/launchdx"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$STAGING/bin/launchdx"
codesign --verify --strict --verbose=4 "$STAGING/bin/launchdx"

cat > "$STAGING/README.txt" <<'EOF'
launchdx is a read-only macOS application launch diagnostic tool.
Run bin/launchdx diagnose /path/to/MyApp.app
EOF
hdiutil create -volname launchdx -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
xcrun notarytool submit "$DMG" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --key "$API_KEY" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Keep a companion source archive. The DMG is the notarized distribution artifact.
# The ZIP is deliberately labeled as a non-notarized convenience archive because
# it is created after DMG notarization and is not published as the primary artifact.
ditto -c -k --sequesterRsrc --keepParent "$STAGING" "$ZIP"
printf 'The DMG is the notarized distribution artifact. The ZIP is a non-notarized convenience archive.\n' > "$OUTPUT_DIR/ARTIFACTS.txt"
shasum -a 256 "$DMG" "$ZIP" > "$OUTPUT_DIR/SHA256SUMS"
printf 'signed and notarized artifacts written to %s\n' "$OUTPUT_DIR"
