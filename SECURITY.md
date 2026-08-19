# Security Policy

launchdx only inspects files. It must never remove quarantine, change Gatekeeper, edit privacy databases, disable system protections, install certificates, re-sign apps, or upload what you point it at.

## Report a vulnerability

Do not file a public issue for an undisclosed vulnerability.

Use GitHub’s private security advisory on this repository. Include:

1. A short description
2. The affected version or commit
3. Steps to reproduce that do not need private data
4. What you expected
5. What happened
6. A JSON report or other evidence, with secrets removed

Strip personal paths, signing identities, certificate material, private source, and proprietary app data before you attach anything.

## Safe testing

Work on copies. Do not turn Gatekeeper off, disable system protections, strip quarantine from production files, change TCC, or launch unknown apps in order to test launchdx.

## Limits

A report is only as complete as the tools and permissions on that Mac. It is not a substitute for trying the real download on a clean Apple Silicon Mac.
