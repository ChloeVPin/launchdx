# GitHub Action

Run launchdx in CI so a macOS job fails when the built `.app`, `.dmg`, or `.pkg` would be blocked. The file is not modified.

```yaml
- uses: ChloeVPin/launchdx@v1
  with:
    path: dist/MyApp.dmg
```

Use a `macos-*` runner.

If `binary` is empty, the action uses `launchdx` already on PATH. If it is not installed, the action installs it with Homebrew (`ChloeVPin/launchdx`).

From a checkout of this repo you can skip Homebrew:

```yaml
- uses: ./
  with:
    path: dist/MyApp.dmg
    binary: .build/release/launchdx
```

`v1` is the Action pin. The CLI version (for example 0.2.2) is the tool release.

## Inputs

| Name | Required | Default | Meaning |
| --- | --- | --- | --- |
| `path` | yes | | Path to an `.app`, `.dmg`, or `.pkg` |
| `binary` | no | empty | Path to a `launchdx` executable. Empty uses PATH or Homebrew |
| `json` | no | `true` | Write a JSON report |
| `report-path` | no | `launchdx-report.json` | Where to write the report |
| `fail-on-blocker` | no | `true` | Fail the job when launchdx exits `1` |
| `fail-on-error` | no | `true` | Fail the job on usage or tool errors |

## Outputs

| Name | Meaning |
| --- | --- |
| `exit-code` | launchdx process exit code |
| `launch-status` | `clean`, `blocked`, or `inconclusive` when the report is JSON |
| `report-path` | Path to the written report |

## License

MIT. Same terms as launchdx.
