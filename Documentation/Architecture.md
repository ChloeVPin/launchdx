# Architecture

This file is for people changing the code. It describes how launchdx is put together.

The short version: the tool first collects facts, then decides what those facts mean, then prints a report. Those three steps stay separate so a wording change cannot silently change a diagnosis.

## Design goals

launchdx separates evidence collection from diagnosis and presentation.

The implementation must satisfy five rules:

1. Inspect without modifying the target
2. Keep raw evidence available
3. Normalize tool and API results into stable models
4. Distinguish facts, warnings, unavailable evidence, and inferences
5. Keep terminal wording separate from machine readable output

## Pipeline

### 1. Target inspection

`BundleInspector` resolves the input path, identifies the artifact kind, and checks readability.

`.app` directories are inspected in place. `.dmg` and `.pkg` files are handed to `ContainerInspector`, which mounts or expands them read-only, finds a nested `.app`, and then reuses the same application diagnosis. The original container is never written.

For an application bundle it validates the `.app` directory shape, reads `Contents/Info.plist`, resolves `CFBundleExecutable`, and records structural findings.

### 2. Mach O inspection

`MachOInspector` reads bounded file ranges and parses thin or universal Mach O headers. It records:

1. Architecture slices
2. 64 bit state
3. Minimum OS version
4. SDK version
5. Code signature load command
6. Code signature data range
7. Malformed or unreadable states

The parser does not execute the file and does not trust offsets before checking them against the file size.

### 3. Security.framework inspection

`SecurityFrameworkInspector` uses public static code APIs on macOS:

1. `SecStaticCodeCreateWithPath`
2. `SecStaticCodeCheckValidity`
3. `SecCodeCopySigningInformation`
4. Strict validation flags
5. Nested code validation flags

API creation failures are not automatically classified as invalid signatures. They become unavailable evidence unless another source confirms the failure.

### 4. Apple command evidence

The read only command runner invokes Apple provided tools with fixed executable paths and bounded timeouts:

1. `codesign`
2. `xcrun stapler`
3. `spctl`
4. `xattr`

Standard output and standard error are drained while the child runs. Timed out children are terminated and reaped.

### 5. Nested code inspection

Nested code is discovered under common application locations:

1. `Contents/Frameworks`
2. `Contents/Helpers`
3. `Contents/PlugIns`
4. `Contents/XPCServices`
5. `Contents/Library/LoginItems`

Known code containers and extensionless Mach O candidates are recorded. Each discovered object is validated explicitly. A bounded worker pool limits concurrent `codesign` processes to four. Each result retains its source path, Team ID when available, and inspection status.

### 6. Staple, Gatekeeper, and quarantine inspection

The current checkers record:

1. Stapled ticket status from `xcrun stapler validate`
2. Execute assessment from `spctl --assess --type execute --verbose=4 --ignore-cache`
3. Quarantine fields from `xattr -p com.apple.quarantine`

A nonzero command status is interpreted only when the output provides enough evidence. Empty or ambiguous output becomes inconclusive. Tool launch failure and timeout become unavailable.

### 7. Diagnosis

The report builder applies causal rules after evidence collection.

A confirmed blocker requires a failed finding with blocker severity. Quarantine can be a trigger. It is not automatically the root cause. A clean result requires complete security inspection and no confirmed blocker.

### 8. Rendering

`ReportRenderer` supports:

1. Normal terminal output
2. Verbose suggested actions
3. Evidence only output
4. JSON output with sorted keys

The renderer does not change findings or diagnosis semantics.

## Public data model

The report is composed of:

1. `TargetInspection`
2. `BundleInspection`
3. `ContainerInspection`
4. `MachOInspection`
5. `SecurityInspection`
6. `Finding`
7. `Evidence`
8. `Diagnosis`
9. `DiagnosticReport`

Every finding has a stable identifier, status, severity, confidence, explanation, evidence references, and suggested actions.

## Failure semantics

The implementation uses these categories:

1. `passed` means the check observed the expected condition
2. `failed` means the check observed a confirmed defect
3. `warning` means the condition deserves attention but is not proven to block launch
4. `skipped` means the check was intentionally not run
5. `unavailable` means required evidence could not be obtained
6. `inconclusive` means evidence was obtained but did not support a reliable conclusion

The report also distinguishes:

1. Confirmed blocker
2. Likely blocker
3. Warning
4. Unrelated issue
5. Unavailable evidence
6. Post launch problem

## Compatibility strategy

1. The package declares macOS 13 as the minimum platform.
2. macOS only code is guarded with platform checks.
3. Apple tool output is treated as version dependent evidence.
4. Raw evidence is retained for investigation when parsers need updates.
5. JSON schema changes require an explicit schema version decision.
6. Private APIs are not required.

## Future additions

The next additions may include:

1. Unified log correlation
2. Sandbox and TCC feature failure context
3. App Translocation evidence
4. ZIP inspection

These are not required for the current `.app` / `.dmg` / `.pkg` release.
