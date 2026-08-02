# Security Policy

## Scope

`launchdx` is a read-only diagnostic tool for application bundles on modern Apple Silicon macOS systems.

The tool must not remove quarantine, change Gatekeeper policy, modify TCC databases, disable system protections, install certificates, re-sign applications, or upload inspected artifacts.

## Reporting a vulnerability

Please do not disclose an undisclosed vulnerability in a public issue.

Open a private security report through the repository security advisory workflow when it is available. Include:

1. A concise description of the issue
2. The affected version or commit
3. Reproduction steps that do not require private data
4. The expected behavior
5. The observed behavior
6. Any relevant JSON report or sanitized evidence

Remove personal paths, signing identities, certificate details, private source code, and proprietary application data before sharing artifacts.

## Safe testing

Use disposable copies of application bundles. Do not test by changing Gatekeeper settings, disabling system protections, removing quarantine from production artifacts, modifying TCC state, or executing unknown applications.

## Limitations

A launchdx report is evidence based and may be incomplete when macOS tools, permissions, policy services, or system APIs are unavailable. A report is not a replacement for testing the final downloaded artifact on a clean Apple Silicon Mac.
