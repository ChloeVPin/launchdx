# Technical Assumptions

These assumptions require testing on current Apple Silicon macOS releases.

## Filesystem and bundles

1. `PropertyListSerialization` can parse supported `Contents/Info.plist` files.
2. Symlink resolution should occur before inspection while the original path remains in the report.
3. A structurally valid application can still fail Mach O, signing, notarization, or policy checks.
4. Readability and regular file checks are meaningful for the current user and filesystem.

## Mach O

1. Bounded range checks prevent malformed offsets from causing a crash.
2. Unsupported load commands are skipped rather than interpreted.
3. A non Mach O main executable is a confirmed format blocker.
4. An x86_64 only executable is reported without assuming Rosetta availability.
5. A valid Mach O header does not prove that the process can execute.

## Apple security evidence

1. Apple command output and exit codes are version dependent.
2. Security.framework API creation failures must not be treated as invalid signatures without corroborating evidence.
3. `codesign` is used as supporting evidence and strict nested objects are inspected explicitly.
4. Gatekeeper policy services may be slow, unavailable, or influenced by system state.
5. Stapled ticket validation does not replace testing the final downloaded artifact.
6. A quarantine attribute is a trigger for additional assessment, not automatically a defect.

## Reports and compatibility

1. The JSON schema is a compatibility contract after external release.
2. Stable finding identifiers are more reliable than terminal wording.
3. Raw evidence may contain local paths and signing metadata and must be sanitized before publication.
4. Non macOS builds report Apple security evidence as unavailable rather than simulated.

## Performance

1. Nested code count is a larger controlled cost than resource file count in the current implementation.
2. Real application timings vary with Apple policy services, filesystem state, caches, and artifact complexity.
3. No universal diagnosis time is promised.
4. Benchmark results must include machine, macOS version, artifact, nested object count, and method.
