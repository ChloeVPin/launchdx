# Benchmarking

## Purpose

launchdx is an evidence collector. Performance matters because a diagnosis should be practical during development, but speed must not be claimed without measurements.

The benchmark measures process wall clock time for the complete command:

```bash
launchdx diagnose TARGET.app --json
```

The measurement includes bundle inspection, Mach O parsing, nested code checks, signing evidence, stapled ticket validation, Gatekeeper assessment, quarantine inspection, JSON encoding, and process startup.

## Reproduce

Build once, then run the harness:

```bash
swift build -c release
sh Scripts/benchmark.sh /tmp/launchdx-benchmark
```

The harness creates disposable parser fixtures with zero or 5,000 resource files and zero, ten, or fifty nested framework containers. On a matching machine it also measures selected installed applications when they exist.

The harness reports the median and the maximum of five runs for each generated fixture. Five samples are not enough to claim a statistically stable percentile. Real application rows are single observations and are not a statistical benchmark.

## Local Apple Silicon observations

These observations were collected on an arm64 Mac with Apple Swift 6.4 and macOS 27.0 build 26A5388g. They are examples, not product guarantees.

1. Generated fixture with zero nested containers: blocked as unsigned or invalid, 98 milliseconds median
2. Generated fixture with ten nested containers: blocked as unsigned or invalid, 207 milliseconds median
3. Generated fixture with fifty nested containers: blocked as unsigned or invalid, 644 milliseconds median
4. Generated fixture with 5,000 resource files and zero nested containers: blocked as unsigned or invalid, 98 milliseconds median
5. Generated fixture with 5,000 resource files and fifty nested containers: blocked as unsigned or invalid, 649 milliseconds median
6. Google Chrome: clean, 9.5 seconds observed
7. Cursor: clean, 7.9 seconds observed
8. Notion: clean, 4.1 seconds observed
9. Freebuff: blocked by invalid sealed resource evidence, 2.7 seconds observed

## Interpretation

1. Resource file count alone did not dominate these runs because launchdx does not independently hash every resource file. Apple signing and policy tools remain the authoritative sources for sealed resource validation.
2. Nested code count is the main controlled cost in the current MVP.
3. Real applications vary widely because Apple tools may consult policy services, examine signatures, and access system caches.
4. Gatekeeper assessment may be slower or unavailable depending on system policy services and the target artifact.
5. Cold and warm process startup are not separated by the current harness. Repeat measurements on the intended release machine before publishing a performance claim.

## Performance policy

The project does not promise a universal diagnosis time. Release notes should report the tested machine, macOS version, target application, nested object count, and measurement method.

Any future optimization must preserve:

1. Explicit nested code validation
2. Stable evidence references
3. Correct timeout and unavailable semantics
4. Read only behavior
5. JSON schema compatibility
