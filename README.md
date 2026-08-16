<div align="center">
  <h1>launchdx</h1>

  <p>Find the evidence behind a macOS launch failure.</p>

  <p>
    <a href="https://github.com/ChloeVPin/launchdx/actions/workflows/macos.yml"><img src="https://github.com/ChloeVPin/launchdx/actions/workflows/macos.yml/badge.svg" alt="CI" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license" /></a>
    <a href="https://github.com/ChloeVPin/launchdx/releases/latest"><img src="https://img.shields.io/github/v/release/ChloeVPin/launchdx?label=latest%20release" alt="Latest release" /></a>
  </p>
</div>

`launchdx` inspects a macOS application bundle and explains the strongest evidence behind a launch blocker.

It is designed for modern Apple Silicon Macs and applications distributed outside the Mac App Store.

> `launchdx` is an evidence collector and diagnosis engine. It is not a Gatekeeper bypass and it does not modify the inspected application or system policy.

## Current release scope

The current release supports `.app` bundles only.

It checks the following areas:

1. Application bundle structure
2. `Contents/Info.plist` readability and validity
3. `CFBundleIdentifier`
4. `CFBundleExecutable`
5. Main executable presence and readability
6. Bounded Mach O parsing
7. `arm64` and `x86_64` slices
8. Minimum macOS and SDK versions when encoded in load commands
9. `LC_CODE_SIGNATURE` presence and bounds
10. Public Security.framework static code validation on macOS
11. Strict `codesign` verification
12. Nested frameworks, helpers, plug ins, applications, XPC services, and extensionless Mach O objects in common locations
13. Signing identity and Team ID
14. Hardened Runtime metadata
15. Entitlements
16. Stapled notarization ticket validation
17. Gatekeeper assessment
18. `com.apple.quarantine` metadata
19. Structured findings, evidence references, confidence, and suggested repairs

The default behavior is read only.

## Quick start

### Homebrew

```bash
brew tap ChloeVPin/launchdx
brew install launchdx
launchdx diagnose /Applications/Notion.app
```

The formula builds the current release from source with the system Swift toolchain and requires macOS 13 or newer. It also installs shell completions and the man page.

For manual completion setup from the repository:

```bash
source completions/launchdx.bash        # bash
source completions/_launchdx             # zsh
source completions/launchdx.fish         # fish
```

The man page is available as `man/launchdx.1` in the repository or through `man launchdx` after Homebrew installation.

### From source

```bash
swift build -c release
.build/release/launchdx diagnose /Applications/Notion.app
```

For a machine readable report:

```bash
.build/release/launchdx diagnose /Applications/Notion.app --json
```

For evidence without the diagnosis summary:

```bash
.build/release/launchdx evidence /Applications/Notion.app
```

For additional repair guidance:

```bash
.build/release/launchdx diagnose /Applications/Notion.app --verbose
```

## Example output

```text
Launch status: NO BLOCKER FOUND

Target:
  /Applications/Notion.app

Bundle:
  Info.plist: valid
  Executable exists: yes
  Mach-O: thin
  Architectures: arm64
  Signature: valid
  Stapled ticket: valid
  Gatekeeper: accepted
  Quarantine: present

Diagnosis:
  No confirmed launch blocker was found.
```

The exact text depends on the macOS version, artifact, installed policy services, and available permissions.

## Causal diagnosis

launchdx distinguishes a trigger from a defect.

When the evidence supports it, a report can explain the relationship like this:

```text
Primary cause:
  The signed app contents are invalid or were modified after signing.

Trigger:
  The quarantine attribute caused macOS to perform an additional assessment.

Evidence:
  Strict signature validation failed and Gatekeeper rejected the app.
```

Quarantine is not automatically treated as the root cause. Missing tools, timeouts, permission failures, and unsupported environments are reported as unavailable or inconclusive evidence.

## JSON output

The stable report schema is available at:

```text
Schemas/diagnosis-v1.json
```

A report contains:

1. Target information
2. Host architecture and operating system information
3. Inspection status
4. Launch status
5. Bundle facts
6. Mach O facts
7. Security facts
8. Findings
9. Diagnosis classification
10. Evidence records
11. Suggested actions

The schema is versioned independently from terminal wording. Consumers should use stable identifiers such as `signature.invalid`, `gatekeeper.assessment`, and `quarantine.present`.

## Exit codes

1. Code `0`: inspection completed without a confirmed blocker
2. Code `1`: a confirmed blocker was found
3. Code `64`: command usage error
4. Code `65`: target type is outside the `.app` MVP
5. Code `66`: target path does not exist
6. Code `69`: required security evidence is unavailable
7. Code `70`: internal tool error
8. Code `77`: inspection is limited by permissions

A clean result can still contain warnings. A nonzero result does not mean that every possible launch gate was inspected.

## Safety model

launchdx does not perform any of the following actions:

1. Remove quarantine automatically
2. Change Gatekeeper settings
3. Modify TCC databases
4. Disable SIP or other system protections
5. Install certificates
6. Re sign applications
7. Change application files
8. Upload artifacts

Suggested actions are plans for the developer. They are not executed by the tool.

## Supported platform

The release target is macOS 13 or newer on Apple Silicon.

The source contains explicit unavailable behavior for non macOS builds so portable parser work does not pretend to have Apple security evidence.

The following macOS areas are intentionally outside this release:

1. TCC feature failures
2. Sandbox denial analysis
3. App Translocation reconstruction
4. Unified log correlation
5. Disk image inspection
6. ZIP inspection
7. Installer package inspection
8. Automatic fixes
9. Notarization submission log retrieval

## Test the project

```bash
swift package clean
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
```

Generate disposable parser fixtures:

```bash
rm -rf /tmp/launchdx-fixtures
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
```

The generated `Valid.app` is intentionally not a runnable application. It contains a minimal arm64 Mach O header and no valid signing identity.

## Real artifact validation

Use copies of installed applications. Do not modify originals.

Native comparison commands:

```bash
codesign --verify --deep --strict --verbose=4 MyApp.app
codesign -dvvv MyApp.app
xcrun stapler validate MyApp.app
spctl --assess --type execute --verbose=4 --ignore-cache MyApp.app
xattr -p com.apple.quarantine MyApp.app
```

launchdx normalizes those results and adds public Security.framework evidence, nested code records, confidence, and causal interpretation.

See the full process in:

```text
Documentation/ReleaseChecklist.md
Documentation/Benchmarking.md
```

## Measured local observations

The following measurements were collected on an arm64 Mac with Apple Swift 6.4 and macOS 27.0 build 26A5388g.

1. Small generated fixture with zero nested objects: about 98 milliseconds median
2. Generated fixture with ten nested objects: about 207 milliseconds median
3. Generated fixture with fifty nested objects: about 644 milliseconds median
4. Google Chrome: about 9.5 seconds observed
5. Cursor: about 7.9 seconds observed
6. Notion: about 4.1 seconds observed
7. Freebuff: about 2.7 seconds observed

These are observations, not universal performance guarantees. Real applications depend on nested object count, signature complexity, Apple policy services, filesystem state, and system caches.

Run the benchmark yourself:

```bash
swift build -c release
sh Scripts/benchmark.sh /tmp/launchdx-benchmark
```

## Repository map

1. `Sources/LaunchDXCore` contains models, bundle inspection, Mach O parsing, security checkers, diagnosis, and renderers.
2. `Sources/launchdx` contains the executable entry point.
3. `Tests/LaunchDXCoreTests` contains parser, bundle, renderer, CLI, and security tests.
4. `Scripts` contains fixture generation and benchmarking.
5. `Schemas` contains the versioned JSON schema.
6. `Documentation` contains architecture, rules, assumptions, benchmarking, fixture, and release guidance.
7. `.github/workflows` contains macOS validation.

## Contributing

Read:

```text
CONTRIBUTING.md
SECURITY.md
Documentation/Architecture.md
Documentation/ReleaseChecklist.md
```

## License

launchdx is released under the MIT License. See `LICENSE`.

## Project status

This is a focused first release for `.app` diagnosis on Apple Silicon macOS. It intentionally favors evidence quality and honest uncertainty over claims that it reproduces every internal macOS launch decision.
