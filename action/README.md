# launchdx GitHub Action

Runs the real `launchdx diagnose` CLI on a `.app`, `.dmg`, or `.pkg`. The job fails when launchdx finds a confirmed launch blocker. The artifact is not modified.

```yaml
- uses: ChloeVPin/launchdx@v1
  with:
    path: dist/MyApp.dmg
```

Requires a `macos-*` runner. When `binary` is empty, the action uses PATH or installs launchdx from Homebrew (`ChloeVPin/launchdx`).

A local checkout can run the same action without Homebrew:

```yaml
- uses: ./
  with:
    path: dist/MyApp.dmg
    binary: .build/release/launchdx
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

## License

MIT. Same terms as launchdx.
