# launchdx

## Find the evidence behind a macOS launch failure

`launchdx` inspects a macOS application bundle and explains the strongest evidence behind a launch blocker.

It is built for Apple Silicon Macs and applications distributed outside the Mac App Store. The default behavior is read-only: launchdx does not modify the inspected application or system policy.

## Install

```bash
brew tap ChloeVPin/launchdx
brew install launchdx
launchdx diagnose /Applications/Notion.app
```

The Homebrew formula builds the current release from source with the system Swift toolchain and requires macOS 13 or newer. It also installs shell completions and the man page.

Build from source with:

```bash
swift build -c release
.build/release/launchdx diagnose /Applications/Notion.app
```

## Example

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

The exact report depends on the macOS version, inspected artifact, available policy services, and permissions.

## What it inspects

launchdx combines bundle inspection, Mach-O parsing, and public macOS security evidence. It checks:

- bundle structure, `Info.plist`, bundle identity, and executable metadata;
- `arm64` and `x86_64` Mach-O slices, minimum OS metadata, and code-signature bounds;
- nested frameworks, helpers, applications, XPC services, and other common embedded code;
- signing identity, Team ID, hardened runtime metadata, and entitlements;
- stapled notarization tickets, Gatekeeper assessment, and quarantine metadata;
- structured findings with evidence references, confidence, and suggested repairs.

The current release supports `.app` bundles only.

## Causal diagnosis

launchdx distinguishes a **trigger** from the underlying **defect**. Quarantine, for example, is not automatically treated as the root cause of a launch failure.

When the evidence supports it, a report can separate the two:

```text
Primary cause:
  The signed app contents are invalid or were modified after signing.

Trigger:
  The quarantine attribute caused macOS to perform an additional assessment.

Evidence:
  Strict signature validation failed and Gatekeeper rejected the app.
```

Missing tools, timeouts, permission failures, and unsupported environments are reported as unavailable or inconclusive evidence rather than converted into certainty.

## Machine-readable output

Use `--json` for a stable report:

```bash
launchdx diagnose /Applications/Notion.app --json
```

The schema lives at [`Schemas/diagnosis-v1.json`](Schemas/diagnosis-v1.json) and is versioned independently from terminal wording. Consumers should rely on stable identifiers such as `signature.invalid`, `gatekeeper.assessment`, and `quarantine.present`.

Use `evidence` when you want collected evidence without the diagnosis summary:

```bash
launchdx evidence /Applications/Notion.app
```

Use `--verbose` for additional repair guidance:

```bash
launchdx diagnose /Applications/Notion.app --verbose
```

## Safety

launchdx is an evidence collector and diagnosis engine, not a Gatekeeper bypass or repair utility.

It does not:

- remove quarantine automatically;
- change Gatekeeper, SIP, TCC, or other system protections;
- install certificates or re-sign applications;
- modify application files;
- upload inspected artifacts.

Suggested actions are plans for the developer. They are not executed by the tool.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Inspection completed without a confirmed blocker |
| `1` | A confirmed blocker was found |
| `64` | Command usage error |
| `65` | Unsupported target type |
| `66` | Target path does not exist |
| `69` | Required security evidence is unavailable |
| `70` | Internal tool error |
| `77` | Inspection is limited by permissions |

A clean result can still contain warnings, and a nonzero result does not imply that every possible macOS launch gate was inspected.

## Platform and scope

The release target is Apple Silicon on macOS 13 or newer. Non-macOS builds expose explicit unavailable behavior so portable parsing code does not pretend to have Apple security evidence.

This release intentionally does not attempt TCC feature-failure diagnosis, sandbox-denial analysis, App Translocation reconstruction, unified-log correlation, DMG/ZIP/PKG inspection, automatic fixes, or notarization submission-log retrieval.

## Development

Run the local verification suite with:

```bash
swift package clean
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
```

Generate disposable parser fixtures with:

```bash
rm -rf /tmp/launchdx-fixtures
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
```

For comparison against native tools, use copies of installed applications and see [`Documentation/Benchmarking.md`](Documentation/Benchmarking.md).

Measured observations are intentionally kept as observations rather than performance claims: results vary with nested object count, signature complexity, Apple policy services, filesystem state, and caches.

## Documentation

- [Architecture](Documentation/Architecture.md)
- [Release checklist](Documentation/ReleaseChecklist.md)
- [Benchmarking](Documentation/Benchmarking.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE).
