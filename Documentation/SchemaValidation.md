# Report schema validation

## Purpose

The JSON report is a compatibility surface. Syntax checking the schema file alone does not prove that launchdx emits reports that satisfy it.

`Scripts/validate-report.py` validates an emitted report against `Schemas/diagnosis-v1.json` using Python's standard library only. It checks required properties, enumerations, primitive types, nested references, array items, minimum values, and forbidden additional properties.

This validator is intentionally a CI and release tool. It is not part of the macOS executable and adds no runtime dependency to launchdx.

## Local check

```bash
swift build -c release
sh Scripts/test-schema.sh /tmp/launchdx-schema
```

The script validates a missing-target report and then proves that an unexpected top-level property is rejected.

## CI check

The macOS workflows run the validator against a generated JSON report. The checked-in schema is also parsed independently with Python's JSON parser.

## Scope

The validator implements the subset used by the current schema. If the schema gains constructs outside that subset, extend the validator and add a failing fixture before merging the schema change.

External consumers should use a standards-compliant JSON Schema implementation. The schema declares draft 2020-12 and remains the compatibility contract.
