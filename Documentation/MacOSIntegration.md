# Real macOS integration testing

## Purpose

Unit tests use deterministic command stubs so parser and rules tests remain repeatable. `Scripts/integration-macos.sh` complements them with disposable real application bundles and native Apple tools.

It requires:

1. macOS
2. Apple Silicon arm64
3. clang
4. codesign
5. spctl
6. xattr
7. plutil
8. A release build of launchdx

It does not require a Developer ID certificate, Apple Developer membership, notarization credentials, or administrator privileges. The fixtures use ad hoc signing only.

## Run locally

```bash
swift build -c release
sh Scripts/integration-macos.sh /tmp/launchdx-real-integration
```

The script creates and removes only its output directory. It never modifies installed applications. It verifies native strict signing behavior, then validates launchdx JSON reports with the repository schema validator.

## Cases

1. `AdHoc.app` is a real arm64 executable with an ad hoc signature. Ad hoc signing is reported as a distribution warning. If Gatekeeper rejects it, that policy result is the launch blocker.
2. `Modified.app` is signed, then a sealed resource is changed. Native `codesign` must reject it and launchdx must identify invalid signature evidence.
3. `NestedUnsigned.app` contains an unsigned nested helper before the host is signed. Native strict signing and launchdx must identify the nested defect.
4. `Modified.app` receives a quarantine attribute so the report can prove that quarantine is a trigger and not automatically the root cause.
5. `AdHoc.dmg` wraps `AdHoc.app` so container unpack reuses the nested application diagnosis.

## What this does not prove

Ad hoc signing cannot prove Developer ID certificate trust, notarization, stapling, offline ticket behavior, or a clean downloaded release. Those require a Developer ID account and, for final confidence, a separate clean Apple Silicon Mac.
