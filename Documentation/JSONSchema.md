# JSON output

`--json` prints a report whose shape is versioned separately from the `launchdx` version. If we ever break that shape, the schema version changes.

The file that defines the shape is [Schemas/diagnosis-v1.json](../Schemas/diagnosis-v1.json).

The `$id` inside that file (`https://launchdx.dev/schema/diagnosis/v1`) is a namespace name for the schema. It is not a website you have to visit.

Field names and key order are stable. Prefer finding IDs such as `signature.invalid` over the English sentences, which can change.

New raw Apple tool text should be attached as evidence. It should not replace the normalized fields.
