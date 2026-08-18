# Fixture Strategy

## Purpose

Fixtures make parser and diagnosis behavior reproducible without requiring a Developer ID certificate or a notarization account.

## Generated structural fixtures

`Scripts/make-fixtures.sh` creates disposable bundles:

1. `Valid.app` with a valid property list and minimal arm64 Mach O header
2. `MissingExecutable.app` with `CFBundleExecutable` pointing to a missing file
3. `BrokenBundle.app` with malformed `Info.plist`
4. `Valid.dmg` wrapping `Valid.app` when `hdiutil` is available

The generated `Valid.app` is a parser fixture. It is not a complete runnable application, it is not signed, and it must not be described as a valid production application. `Valid.dmg` exists so container unpack can be tested without a Developer ID.

## Unit fixture classes

Mach O tests construct bounded data for:

1. Thin arm64
2. Thin x86_64
3. Universal binaries
4. Truncated headers
5. Invalid load commands
6. Out of bounds code signature ranges
7. Minimum OS and SDK load commands

Security tests use injected command runners and framework checkers for:

1. Valid signatures
2. Invalid signatures
3. Ad hoc signatures
4. Missing tools
5. Timeouts
6. Malformed quarantine values
7. Empty Gatekeeper output
8. Strict verification precedence
9. Nested inspection failures

## Real artifact fixtures

Protected macOS validation uses disposable copies of installed applications.

Required variants:

1. Unmodified signed application
2. Modified signed `Info.plist`
3. Modified signed resource
4. Removed main executable
5. Unsigned nested code object
6. Malformed Mach O object
7. Present quarantine value
8. Malformed quarantine value
9. Permission limited copy when safe

The original application must never be modified.

## Credential dependent fixtures

Developer ID and notarized fixtures require an Apple developer environment. They should be generated in protected Apple Silicon CI or a controlled manual environment. Credentials must never be committed or printed in reports.

## Expected evidence

Each fixture test should assert:

1. Finding identifiers
2. Status
3. Severity
4. Confidence
5. Evidence references
6. Suggested repair actions
7. Diagnosis classification
8. Exit code

A test must not assert only terminal prose.
