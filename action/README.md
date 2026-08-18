# launchdx GitHub Action

Runs the real `launchdx diagnose` CLI on a `.app`, `.dmg`, or `.pkg`. The job fails when launchdx finds a confirmed launch blocker. The artifact is not modified.

Preferred name:

```yaml
- uses: ChloeVPin/launchdx-action@v1
  with:
    path: dist/MyApp.dmg
```

This repository also exposes the same action:

```yaml
- uses: ChloeVPin/launchdx@v0.2.1
  with:
    path: dist/MyApp.dmg
```

## Inputs

| Name | Required | Default | Meaning |
| --- | --- | --- | --- |
| `path` | yes | | Path to a `.app`, `.dmg`, or `.pkg` |
| `binary` | no | empty | Existing `launchdx` executable. Empty uses PATH or Homebrew |
| `json` | no | `true` | Write a JSON report |
| `report-path` | no | `launchdx-report.json` | Report file |
| `fail-on-blocker` | no | `true` | Fail the job on launchdx exit code 1 |
| `fail-on-error` | no | `true` | Fail the job on usage or tool errors |

## Outputs

| Name | Meaning |
| --- | --- |
| `exit-code` | launchdx process exit code |
| `launch-status` | `clean`, `blocked`, or `inconclusive` when the report is JSON |
| `report-path` | Path to the written report |

Requires a `macos-*` runner.