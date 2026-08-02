# Diagnosis rules

The rule engine is intentionally separate from evidence collection. Checkers produce normalized facts; rules decide severity, causality, and repair guidance.

## Initial catalog

1. A missing target is unavailable evidence, not a launch diagnosis.
2. A target that is not a `.app` directory is outside the MVP and invalid input.
3. An unreadable target is permission-limited evidence.
4. A missing `Contents` directory is a confirmed bundle blocker.
5. A missing `Contents/Info.plist` is a confirmed bundle blocker.
6. A malformed `Info.plist` is a confirmed bundle blocker.
7. A missing or empty `CFBundleIdentifier` is a confirmed bundle blocker.
8. A missing or empty `CFBundleExecutable` is a confirmed bundle blocker.
9. A path-valued `CFBundleExecutable` is a confirmed bundle blocker.
10. A missing or non-regular main executable is a confirmed bundle blocker.
11. An unreadable main executable is unavailable evidence, not proof of a malformed executable.
12. An unreadable required bundle file is permission-limited evidence and exits with `EX_NOPERM`.
13. `Contents` must be a directory.
14. `Contents/Info.plist` must be a regular file.
15. A non-Mach-O main executable is a confirmed executable-format blocker.
16. A malformed Mach-O header, load-command region, slice, or code-signature range is a confirmed executable-format blocker.
17. An arm64 slice is required for native Apple Silicon support; an x86_64-only binary is reported as a warning because Rosetta availability is not inferred.
18. A valid Mach-O with no `LC_CODE_SIGNATURE` is supporting evidence; the macOS signature checker determines whether the app is unsigned, invalid, or otherwise unavailable.

## First cross-checker causal rule

When later checkers observe all of the following:

```text
quarantine present
signature invalid
Gatekeeper rejected
```

The diagnosis must say:

```text
Primary cause:
  The signed app contents are invalid or were modified after signing.

Trigger:
  The quarantine attribute caused macOS to perform an additional assessment.

Evidence:
  The signature failed validation and Gatekeeper rejected the app.
```

Quarantine is not itself the root defect in this rule.
