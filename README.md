<div align="center">
  <img src="assets/readme-icon.svg" alt="launchdx" width="120" />

  <h1>launchdx</h1>

  <p>Find out why macOS blocked your app.</p>

  <p>
    <a href="https://github.com/ChloeVPin/launchdx/actions/workflows/macos.yml"><img src="https://github.com/ChloeVPin/launchdx/actions/workflows/macos.yml/badge.svg" alt="CI" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license" /></a>
    <a href="https://github.com/ChloeVPin/launchdx/releases/latest"><img src="https://img.shields.io/github/v/release/ChloeVPin/launchdx?label=latest%20release" alt="Latest release" /></a>
  </p>
</div>

When a Mac says an app is damaged, can’t be opened, or must be moved to the Trash, the alert usually does not say *why*. launchdx inspects the file you downloaded and reports the strongest evidence.

Point it at an `.app`, or at the `.dmg` / `.pkg` that contained it. It opens those downloads read-only, finds the app inside, and runs the same checks. The original file is never changed.

It does not bypass Gatekeeper, remove quarantine, or rewrite signatures. It only looks.

Works on Apple Silicon Macs running macOS 13 or newer, for apps distributed outside the Mac App Store.

## Install

```bash
brew tap ChloeVPin/launchdx
brew install launchdx
```

macOS 13 or newer is required. Homebrew builds the current release from source and installs tab-completion plus a man page (`man launchdx`).

From this repository:

```bash
swift build -c release
.build/release/launchdx diagnose /Applications/MyApp.app
```

## Use it

```bash
launchdx diagnose /Applications/MyApp.app
launchdx diagnose ~/Downloads/MyApp.dmg
launchdx diagnose ~/Downloads/MyApp.pkg
```

Useful flags:

```bash
launchdx diagnose ~/Downloads/MyApp.dmg --json      # machine-readable report
launchdx diagnose ~/Downloads/MyApp.dmg --verbose   # include repair suggestions
launchdx evidence /Applications/MyApp.app           # facts only, no diagnosis summary
launchdx --version
```

## Example

```text
Launch status: NO BLOCKER FOUND

Target:
  /Applications/Notion.app

Bundle:
  Info.plist: valid
  Executable exists: yes
  Mach-O: thin
  Architectures: arm64
  Signature: valid
  Stapled ticket: valid
  Gatekeeper: accepted
  Quarantine: present

Diagnosis:
  No confirmed launch blocker was found.
```

Wording changes with the macOS version, the file, and which Apple tools are available on the machine.

## Trigger vs defect

macOS often *looks* because the file was downloaded (quarantine). That is not always *why* it blocked the app.

When the evidence supports it, launchdx separates those two things:

```text
Primary cause:
  The signed app contents are invalid or were modified after signing.

Trigger:
  The quarantine attribute caused macOS to perform an additional assessment.

Evidence:
  Strict signature validation failed and Gatekeeper rejected the app.
```

If a tool is missing, a command times out, or permissions get in the way, that is reported as unavailable or inconclusive. It is not treated as proof the app is broken.

## What it looks at

- The app bundle is complete and readable (Info.plist, identifier, main executable)
- The main program is a Mac binary, including Apple Silicon and Intel slices when present
- The code signature is present and valid, including nested helpers and frameworks
- Hardened Runtime, Team ID, and entitlements
- A stapled notarization ticket
- Gatekeeper’s assessment
- The download quarantine flag
- For `.dmg` and `.pkg`: the file is opened read-only, then the app inside is checked the same way

Default behavior is read-only.

## GitHub Action

Fail a macOS CI job when launchdx finds a confirmed blocker:

```yaml
- uses: ChloeVPin/launchdx@v1
  with:
    path: dist/MyApp.dmg
```

Needs a `macos-*` runner. If you do not pass `binary`, the action uses `launchdx` on PATH or installs it with Homebrew.

Inputs, outputs, and a local `uses: ./` example are in [action/README.md](action/README.md). The action runs the real CLI. It does not change the file.

## JSON reports

`--json` writes a stable report. The schema is [Schemas/diagnosis-v1.json](Schemas/diagnosis-v1.json).

Use the finding IDs, not the English sentences, if you parse the file. Examples: `signature.invalid`, `gatekeeper.assessment`, `quarantine.present`, `container.app-found`.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Finished. No confirmed blocker. Warnings may still be present. |
| `1` | A confirmed blocker was found. |
| `64` | Bad command usage. |
| `65` | Not a usable `.app`, `.dmg`, or `.pkg` (wrong type, empty container, or the file could not be opened). |
| `66` | Path does not exist. |
| `69` | Needed security evidence could not be collected. |
| `70` | Internal tool error. |
| `77` | The current user cannot read the file. |
| `78` | GitHub Action is not running on macOS. The CLI never returns this. |

A nonzero exit does not mean every possible macOS check was run.

## What it will not do

launchdx will not:

- Remove quarantine
- Change Gatekeeper settings
- Change privacy (TCC) databases
- Disable SIP or other system protections
- Install certificates
- Re-sign apps
- Edit the files you point it at
- Upload anything

Suggested repairs are for you to apply. The tool does not apply them.

## Requirements and limits

Release target: macOS 13 or newer on Apple Silicon.

This release does not cover:

- Privacy permission failures (TCC)
- App sandbox denials
- App Translocation
- Unified logs
- `.zip` downloads
- Automatic fixes
- Apple’s notarization *submission* logs (it only checks a ticket already stapled to the file)

A report is evidence from this Mac, not a guarantee of what every other Mac will do. Test the real download on a clean machine before you ship.

## Tests

```bash
swift test
swift build -c release
python3 -m json.tool Schemas/diagnosis-v1.json >/dev/null
sh Scripts/test-action.sh
```

Generated fixtures (unsigned on purpose, not runnable apps):

```bash
sh Scripts/make-fixtures.sh /tmp/launchdx-fixtures
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.app --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.dmg --json
.build/release/launchdx diagnose /tmp/launchdx-fixtures/Valid.pkg --json
```

Compare against Apple’s own tools on *copies* of real apps, never originals. Details: [CONTRIBUTING.md](CONTRIBUTING.md), [Documentation/ReleaseChecklist.md](Documentation/ReleaseChecklist.md).

## License

MIT. See [LICENSE](LICENSE).
