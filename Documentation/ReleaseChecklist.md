# Release Checklist

## Repository quality

1. Confirm the version in `Package.swift` and release metadata.
2. Update `CHANGELOG.md`.
3. Confirm `LICENSE`, `SECURITY.md`, and `CONTRIBUTING.md`.
4. Validate Markdown for broken links and unsupported characters.
5. Confirm that no secrets, private paths, or local artifacts are committed.

## Build validation

```bash
swift package clean
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
```

## Fixture validation

```bash
rm -rf /tmp/launchdx-fixtures
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/MissingExecutable.app --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/BrokenBundle.app --json
```

Expected fixture behavior:

1. `Valid.app`: blocked because the parser fixture is unsigned and not runnable, exit code `1`
2. `MissingExecutable.app`: blocked by bundle structure, exit code `1`
3. `BrokenBundle.app`: blocked by invalid `Info.plist`, exit code `1`

## Real macOS artifact validation

Use disposable copies, never original installed applications.

For each artifact, record:

1. macOS version and host architecture
2. Application path and version
3. Native `codesign --verify --strict --verbose=4` result
4. Native `codesign -dvvv` identity and Team ID
5. Native `xcrun stapler validate` result
6. Native `spctl --assess --type execute --verbose=4 --ignore-cache` result
7. Native quarantine state
8. launchdx JSON report
9. launchdx exit code
10. Wall clock time and nested object count

Required adversarial copies:

1. Unmodified signed application
2. Modified signed `Info.plist`
3. Modified signed resource
4. Removed main executable
5. Unsigned nested code object
6. Malformed Mach O object
7. Present quarantine attribute
8. Malformed quarantine value
9. Inaccessible artifact when permission testing is safe

## Performance validation

Measure cold and warm runs separately. Report the median and the maximum of five samples rather than a universal speed promise.

At minimum measure:

1. A small unsigned fixture
2. A bundle with 5,000 resource files
3. A bundle with 10 nested code containers
4. A bundle with 50 nested code containers
5. One real signed application with at least 20 nested objects
6. One large real signed application

The reproducible harness is:

```bash
swift build -c release
sh Scripts/benchmark.sh /tmp/launchdx-benchmark
```

Investigate any timeout, malformed JSON, leaked child process, or result that differs from native Apple tools without an explanation.

## Distribution validation

1. Build on Apple Silicon macOS.
2. Sign the release executable with the intended Developer ID identity.
3. Enable Hardened Runtime for the release executable.
4. Submit the exact release artifact for notarization.
5. Staple the ticket to the exact distributed artifact.
6. Validate the stapled artifact offline where practical.
7. Test the downloaded release on a clean Apple Silicon Mac.
8. Publish checksums.
9. Publish the supported macOS version range.
10. Publish known limitations.
