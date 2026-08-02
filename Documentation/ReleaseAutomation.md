# Release automation

## Credential-free behavior

The release workflow always runs source tests, release compilation, emitted-report schema validation, and real macOS integration fixtures.

The signed release job is gated by the repository variable `RELEASE_CREDENTIALS_CONFIGURED` set to `true`. When enabled, the first signed-release step checks every required secret, including `KEYCHAIN_PASSWORD`, without printing values. Without the variable, the workflow succeeds with an explicit message that Developer ID signing and notarization were skipped. This is the expected state for a repository without an Apple Developer account.

## Required configuration for a signed release

Set these GitHub Actions secrets:

1. `APPLE_CERTIFICATE_P12_BASE64`
2. `APPLE_CERTIFICATE_PASSWORD`
3. `APPLE_API_KEY_ID`
4. `APPLE_API_ISSUER_ID`
5. `APPLE_API_KEY_CONTENT`
6. `KEYCHAIN_PASSWORD`

Set this repository variable:

1. `DEVELOPER_ID_APPLICATION`, for example `Developer ID Application: Example Company (TEAMID)`
2. `RELEASE_CREDENTIALS_CONFIGURED=true`

The workflow passes `RELEASE_CREDENTIALS_CONFIGURED` into the release script, and the script still checks that flag and every secret before touching a keychain. The certificate must be a Developer ID Application certificate. The API key must be authorized for notarization and its base64 value must contain the private `.p8` key. Do not commit any of these values.

## Workflow behavior

`.github/workflows/release.yml` performs the following sequence:

1. Test and compile on an Apple Silicon macOS runner.
2. Validate generated JSON reports against the checked-in schema.
3. Run credential-free real macOS integration fixtures.
4. When the credential gate is enabled, create an ephemeral keychain.
5. Import the Developer ID certificate only into that keychain.
6. Build the release executable with Hardened Runtime signing options.
7. Verify the executable with strict `codesign`.
8. Create a DMG.
9. Submit the exact DMG to `notarytool` with the App Store Connect API key.
10. Staple and validate the exact DMG.
11. Create a companion ZIP and SHA-256 checksums.
12. Upload artifacts and publish a tag release.
13. Restore the original keychain search list, then delete temporary keychain and credential files in cleanup.

The script is `Scripts/release-signed.sh`. It exits with configuration code `78` when credentials are missing rather than silently producing an unsigned release.

## Important boundary

No local notarization claim is made without the required Apple credentials. A successful credential-free CI run means the source and diagnostic behavior passed validation, not that a distributed binary is notarized.
