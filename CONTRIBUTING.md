# Contributing

## What you need

1. macOS 13 or newer
2. Apple Silicon recommended
3. Swift 5.9 or newer
4. Xcode Command Line Tools, for tests that call Apple’s signing tools

You can compile parser tests on Linux. Those builds cannot collect real signing, Gatekeeper, notarization, or quarantine evidence.

## Before a pull request

```bash
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
sh Scripts/test-action.sh
```

Generated fixtures (unsigned on purpose):

```bash
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.dmg --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.pkg --json
```

If you change how macOS security evidence is collected, also run Apple’s own tools on *copies* of real apps: `codesign`, `spctl`, `xcrun stapler`, and `xattr`. Do not modify an installed original.

## Tests

Prefer stable fixtures and fake command runners. Add a real-app test only when the fixture is safe to generate and the result is stable on supported macOS versions.

Keep these apart in reports and assertions:

1. Confirmed facts
2. Inferences
3. Warnings
4. Evidence that could not be collected
5. Inconclusive evidence

A missing tool, a timeout, or a permission error is not proof the app is malicious or unsigned.

## Docs

GitHub Flavored Markdown. Direct sentences. No emoji. No em dash. Say when behavior depends on the macOS version, and say what this release does not cover.
