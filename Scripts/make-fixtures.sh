#!/bin/sh
set -eu

output_dir="${1:-./Fixtures/Generated}"
mkdir -p "$output_dir"

make_app() {
  app_path="$1"
  executable_name="$2"
  plist_mode="$3"

  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS"

  if [ "$plist_mode" = "malformed" ]; then
    printf '%s\n' 'not a property list' > "$app_path/Contents/Info.plist"
  else
    cat > "$app_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>dev.launchdx.fixture</string>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
</dict>
</plist>
EOF
  fi

  if [ "$plist_mode" = "valid" ]; then
    # Minimal little-endian 64-bit arm64 Mach-O header with no load commands.
    # It is sufficient for parser fixtures; it is not intended to be executable.
    printf '\317\372\355\376\014\000\000\001\000\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$app_path/Contents/MacOS/$executable_name"
    chmod 755 "$app_path/Contents/MacOS/$executable_name"
  fi
}

make_app "$output_dir/Valid.app" "Valid" "valid"
make_app "$output_dir/MissingExecutable.app" "MissingExecutable" "missing"
make_app "$output_dir/BrokenBundle.app" "Broken" "malformed"

if command -v hdiutil >/dev/null 2>&1; then
  src_dir="$output_dir/dmg-src"
  rm -rf "$src_dir"
  mkdir -p "$src_dir"
  cp -R "$output_dir/Valid.app" "$src_dir/Valid.app"
  rm -f "$output_dir/Valid.dmg"
  hdiutil create -volname LaunchDXFixture -srcfolder "$src_dir" -ov -format UDZO "$output_dir/Valid.dmg" >/dev/null
fi

if command -v pkgbuild >/dev/null 2>&1; then
  pkg_root="$output_dir/pkg-root"
  rm -rf "$pkg_root"
  mkdir -p "$pkg_root"
  cp -R "$output_dir/Valid.app" "$pkg_root/Valid.app"
  rm -f "$output_dir/Valid.pkg"
  pkgbuild --root "$pkg_root" --identifier "dev.launchdx.fixture" --version "0.0.1" "$output_dir/Valid.pkg" >/dev/null
fi

printf 'Fixtures written to %s\n' "$output_dir"
