#!/usr/bin/env python3
"""Small dependency-free validator for the JSON Schema subset used by launchdx."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


class ValidationError(Exception):
    pass


def fail(path: str, message: str) -> None:
    raise ValidationError(f"{path or '$'}: {message}")


def json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def resolve_ref(root: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ValidationError(f"unsupported external schema reference: {reference}")
    value: Any = root
    for component in reference[2:].split("/"):
        value = value[component.replace("~1", "/").replace("~0", "~")]
    if not isinstance(value, dict):
        raise ValidationError(f"schema reference is not an object: {reference}")
    return value


def validate(value: Any, schema: dict[str, Any], root: dict[str, Any], path: str = "") -> None:
    if "$ref" in schema:
        validate(value, resolve_ref(root, schema["$ref"]), root, path)
        return

    if "const" in schema and value != schema["const"]:
        fail(path, f"expected constant {schema['const']!r}, got {value!r}")

    if "enum" in schema and value not in schema["enum"]:
        fail(path, f"expected one of {schema['enum']!r}, got {value!r}")

    expected = schema.get("type")
    if expected is not None:
        allowed = expected if isinstance(expected, list) else [expected]
        actual = json_type(value)
        compatible_number = "number" in allowed and actual == "integer"
        if actual not in allowed and not compatible_number:
            fail(path, f"expected type {allowed!r}, got {actual}")

    if isinstance(value, dict):
        for required in schema.get("required", []):
            if required not in value:
                fail(path, f"missing required property {required!r}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            unknown = sorted(set(value) - set(properties))
            if unknown:
                fail(path, f"unexpected properties {unknown!r}")
        for key, child in properties.items():
            if key in value:
                child_path = f"{path}.{key}" if path else key
                validate(value[key], child, root, child_path)

    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            validate(item, schema["items"], root, f"{path}[{index}]")

    if isinstance(value, (int, float)) and not isinstance(value, bool) and "minimum" in schema:
        if value < schema["minimum"]:
            fail(path, f"must be at least {schema['minimum']}")


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"usage: {Path(sys.argv[0]).name} REPORT.json [SCHEMA.json]", file=sys.stderr)
        return 64
    report_path = Path(sys.argv[1])
    schema_path = Path(sys.argv[2]) if len(sys.argv) == 3 else Path("Schemas/diagnosis-v1.json")
    try:
        report = json.loads(report_path.read_text())
        schema = json.loads(schema_path.read_text())
        validate(report, schema, schema)
    except (OSError, json.JSONDecodeError, KeyError, ValidationError) as error:
        print(f"schema validation failed: {error}", file=sys.stderr)
        return 1
    print(f"schema valid: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
