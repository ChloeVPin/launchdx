# launchdx

launchdx diagnoses why macOS rejected an application. It inspects an `.app`, or an application inside a `.dmg` or `.pkg`, and reports evidence from the bundle, signature, notarization ticket, Gatekeeper assessment, and quarantine metadata.

The command is read-only. It does not bypass Gatekeeper, remove quarantine, or rewrite signatures.

## Install

```sh
brew tap ChloeVPin/launchdx
brew install launchdx
```

Build from this repository with Swift Package Manager:

```sh
swift build -c release
.build/release/launchdx diagnose /Applications/MyApp.app
```

## Use

```sh
launchdx diagnose /Applications/MyApp.app
launchdx diagnose ~/Downloads/MyApp.dmg
launchdx diagnose ~/Downloads/MyApp.pkg
launchdx diagnose ~/Downloads/MyApp.dmg --json
launchdx evidence /Applications/MyApp.app
```

Use finding IDs from the JSON report when integrating the command into another tool. The report schema is [Schemas/diagnosis-v1.json](Schemas/diagnosis-v1.json). The GitHub Action documentation is in [action/README.md](action/README.md).

## Requirements

The supported command line workflow targets macOS 13 or newer. The available checks depend on the macOS version, permissions, and Apple tools installed on the machine.

## License

launchdx is available under the [MIT license](LICENSE).
