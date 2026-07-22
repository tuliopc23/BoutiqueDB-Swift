# Security Policy

## Supported versions

Security fixes are provided for the latest published beta line. Consumers
should update to the newest patch before reporting a vulnerability.

## Reporting

Do not open a public issue for a suspected vulnerability. Use GitHub's private
security advisory workflow for this repository and include a minimal reproducer,
affected version, platform, and impact. Never include production database files,
CloudKit credentials, encryption keys, or user records.

## Scope notes

Host applications own Apple signing, entitlements, Keychain access, Data
Protection, CloudKit container policy, and production schema promotion. The
package must not log row payloads or secrets. Turso experimental encryption and
multi-process features remain subject to the engine's documented stability.
