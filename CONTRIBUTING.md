# Contributing

## Development requirements

1. macOS 13 or newer
2. Apple Silicon recommended
3. Swift 5.9 or newer
4. Apple command line tools for macOS integration tests

Linux builds may be useful for portable parser work, but they cannot provide Apple signing, Gatekeeper, notarization, or quarantine evidence.

## Before opening a pull request

Run:

```bash
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
sh Scripts/test-action.sh
```

Generate and inspect parser fixtures:

```bash
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.dmg --json
```

For changes to macOS security behavior, also test disposable copies of real applications with native `codesign`, `spctl`, `xcrun stapler`, and `xattr` commands. Never modify an original installed application.

## Test design

Prefer normalized evidence and deterministic fake command runners for unit tests. Add real artifact tests only when the fixture can be generated safely and the expected result is stable on supported macOS versions.

Tests must distinguish:

1. Confirmed facts
2. Inferences
3. Warnings
4. Unavailable evidence
5. Inconclusive evidence

Do not turn command failure, timeout, or missing permissions into a confirmed security defect.

## Documentation style

Use GitHub Flavored Markdown. Keep prose direct. Do not use emoji characters or em dash characters. State version dependent behavior and unsupported cases explicitly.
