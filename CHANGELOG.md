# Changelog

All notable changes to launchdx are documented here.

## 0.1.1

### Added

1. Bash completion script in `completions/launchdx.bash`
2. Zsh completion script in `completions/_launchdx`
3. Fish completion script in `completions/launchdx.fish`
4. Man page in `man/launchdx.1`
5. Homebrew formula installs completions and the man page

## 0.1.0

### Added

1. Read-only `.app` bundle diagnosis for Apple Silicon macOS
2. Bundle structure and `Info.plist` validation
3. Bounded Mach-O inspection with arm64 and x86_64 detection
4. Public Security.framework static code validation on macOS
5. Strict code-signature evidence from `codesign`
6. Explicit nested code inspection with bounded parallelism
7. Signing identity, Team ID, Hardened Runtime, and entitlement evidence
8. Stapled ticket validation through `xcrun stapler`
9. Gatekeeper assessment through `spctl`
10. Quarantine parsing through `xattr`
11. Causal diagnosis fields that separate primary findings from triggers
12. Stable JSON output and exit codes
13. Generated parser fixtures and macOS CI validation
14. MIT licensing and contributor security guidance

### Known limitations

1. TCC, sandbox, App Translocation, and unified log correlation are not implemented
2. DMG, ZIP, and PKG inspection are not implemented
3. Notarization submission logs are not queried
4. A clean external Mac is still required for final distribution validation
5. Gatekeeper and Apple policy services may be unavailable or version dependent
