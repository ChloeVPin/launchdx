# launchdx 0.1.0

## Find out why macOS rejected an application

launchdx is a read only diagnostic CLI for modern Apple Silicon macOS systems. It inspects `.app` bundles, collects evidence from public Apple APIs and Apple provided tools, and explains the most likely launch blocker.

## Included in this release

1. `.app` bundle structure validation
2. `Info.plist` and `CFBundleExecutable` validation
3. Bounded Mach O inspection
4. `arm64` and `x86_64` detection
5. Public Security.framework static code validation
6. Strict code signature validation
7. Nested code inspection with bounded parallelism
8. Signing identity, Team ID, Hardened Runtime, and entitlement evidence
9. Stapled ticket validation
10. Gatekeeper assessment
11. Quarantine metadata parsing
12. Root cause and trigger separation
13. Human readable and JSON output
14. Stable exit codes
15. Read only operation

## Verification completed

The release was validated on an arm64 Mac with Apple Swift 6.4 and macOS 27.0 build 26A5388g.

1. 38 Swift tests passed before release automation additions
2. Release build completed without compiler warnings
3. JSON schema syntax validation passed
4. Generated fixture smoke tests passed with expected blocker exit codes
5. Google Chrome produced a complete clean report in about 9.5 seconds in the earlier local run
6. Cursor produced a complete clean report in about 7.9 seconds in the earlier local run
7. Notion produced a complete clean report in about 4.1 seconds in the earlier local run
8. Freebuff was correctly identified as blocked by invalid sealed resource evidence in about 2.7 seconds in the earlier local run
9. Native `codesign`, `stapler`, `spctl`, and `xattr` comparisons agreed for clean and damaged real applications in the earlier local run
10. Generated bundles with fifty nested containers completed in about 644 milliseconds median in the earlier local benchmark

These values are observations from one machine. They are not universal performance guarantees.

## Quick start

```bash
swift build -c release
.build/release/launchdx diagnose /Applications/Notion.app
```

Machine readable output:

```bash
.build/release/launchdx diagnose /Applications/Notion.app --json
```

Reproduce the benchmark:

```bash
sh Scripts/benchmark.sh /tmp/launchdx-benchmark
```

## Safety

launchdx does not remove quarantine, change Gatekeeper settings, modify TCC state, disable system protections, re sign applications, install certificates, or upload inspected artifacts.

## Release artifact note

The notarized distribution artifact is the DMG. The companion ZIP is a non-notarized convenience archive and is labeled accordingly in `ARTIFACTS.txt`; consumers must not treat the ZIP as notarized.

## Known limitations

1. TCC, sandbox, App Translocation, and unified log correlation are outside this release
2. DMG, ZIP, and PKG inspection are outside this release
3. Notarization submission log retrieval is outside this release
4. Gatekeeper and Apple policy services can be unavailable or version dependent
5. Final distribution should be tested on a clean Apple Silicon Mac with the exact downloaded artifact

## Documentation

1. `README.md` explains installation, usage, output, safety, and scope
2. `Documentation/Architecture.md` explains the implementation
3. `Documentation/DiagnosisRules.md` explains causal findings
4. `Documentation/Benchmarking.md` explains measured performance
5. `Documentation/ReleaseChecklist.md` explains distribution validation
6. `SECURITY.md` explains safe vulnerability reporting
7. `CONTRIBUTING.md` explains development and testing
8. `LICENSE` contains the MIT License
