# JSON output

The report schema is versioned independently from the executable:

```text
https://launchdx.dev/schema/diagnosis/v1
```

The checked-in schema is `Schemas/diagnosis-v1.json`. Swift's `JSONEncoder` uses the model's stable property names and sorted keys for deterministic output.

Breaking changes require a new schema version. Raw tool output must be added as evidence later rather than replacing normalized fields.
