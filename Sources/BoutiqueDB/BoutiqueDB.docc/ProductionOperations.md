# Production Operations

Operate database files, logs, migrations, and packaged binaries safely.

## Database files and migrations

Treat the database, `-wal`, and `-shm` files as one persistence unit. Close the
store and use supported checkpoint/backup flows before copying or deleting it.
Never unlink a live file. Prefer transactional migrations; asynchronous
migrations must be idempotent because arbitrary suspension cannot be held inside
one native transaction.

Migration identifiers are append-only. Startup rejects duplicates, reordered
history, and removed identifiers. Test every released schema upgrade with data
preservation and foreign-key checks.

## Privacy and diagnostics

Do not log row values, encryption keys, CloudKit assets, record payloads, or user
identifiers. Log lifecycle transitions, durations, counts, cursor positions,
and stable error categories with private values redacted. Surface observation
and sync failures through their status APIs instead of discarding them.

## Binary compatibility

The bundled TursoSDK XCFramework must include universal macOS, iOS device, and
iOS Simulator slices. Each object member must target macOS 14 or iOS 17 or
earlier. Release automation verifies architectures, deployment metadata,
archive checksum, clean URL consumption, and Swift Package Index builds.
