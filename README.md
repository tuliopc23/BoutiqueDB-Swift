# BoutiqueDB

<p align="center">
  <img src="Assets/BoutiqueDB.png" alt="BoutiqueDB framework icon" width="160" height="160" />
</p>

<p align="center">
  <strong>Local-first Swift persistence on Turso</strong> — SQLiteData-style DX, CDC LiveQuery, CloudKit, official Turso features.
</p>

<p align="center">
  <a href="https://swiftpackageindex.com/tuliopc23/BoutiqueDB-Swift"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftuliopc23%2FBoutiqueDB-Swift%2Fbadge%3Ftype%3Dswift-versions" alt="Swift versions" /></a>
  <a href="https://swiftpackageindex.com/tuliopc23/BoutiqueDB-Swift"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftuliopc23%2FBoutiqueDB-Swift%2Fbadge%3Ftype%3Dplatforms" alt="Platforms" /></a>
  <img src="https://img.shields.io/badge/Swift-6.1-orange" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License" />
</p>

Inspired by [SQLiteData](https://github.com/pointfreeco/sqlite-data) — without GRDB. Engine: [Turso](https://github.com/tursodatabase/turso) via the **official sdk-kit C ABI**.

## Install (Swift Package Manager)

```swift
// Package.swift
dependencies: [
  .package(
    url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git",
    exact: "0.3.0-beta.1"
  ),
],
targets: [
  .target(
    name: "MyApp",
    dependencies: [
      .product(name: "BoutiqueDB", package: "BoutiqueDB-Swift"),
    ]
  ),
]
```

Xcode: **File → Add Package Dependencies…** → `https://github.com/tuliopc23/BoutiqueDB-Swift` → product **BoutiqueDB**.

> **Engine binary:** This beta reuses the verified v0.2.1 multi-arch
> `TursoSDK.xcframework.zip` from GitHub Releases (macOS + iOS device +
> Simulator, sdk-kit, no `unsafeFlags`). Maintainers:
> `./Scripts/build-turso-sdk-xcframework.sh` (always full multi-arch by default).

## Platforms

| Platform | Minimum | Binary slices |
|----------|---------|---------------|
| iOS | 17.0 | device arm64 + Simulator arm64/x86_64 |
| macOS | 14.0 | arm64 + x86_64 universal |

## Products

| Product | Role |
|---------|------|
| **BoutiqueDB** | Container, LiveQuery, migrations, CloudKit façade |
| TursoKit | Engine connection (sdk-kit) |
| StructuredQueriesTurso | `@Table` driver + Turso FTS/vector DSL |
| TursoCKSync | CDC ↔ `CKSyncEngine` |
| TursoObservation | Change streams |

## Quick start

```swift
import BoutiqueDB
import StructuredQueries

let configuration = BoutiqueDBConfiguration(
  url: try BoutiqueDB.applicationSupportURL(),
  concurrentWrites: true,
  migrations: AppMigrations.plan
)
let db = try await BoutiqueDB.open(configuration)

try await db.write { conn in
  try conn.execute(
    "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
    [.text("1"), .text("Hello"), .text("")]
  )
}

let rows = try await db.fetchAll(Note.self)
```

When using `swift-dependencies`, open the database first and then register the
already-created value. `prepareDependencies` is synchronous:

```swift
let database = try await BoutiqueDB.open(url: url, migrations: AppMigrations.plan)
prepareDependencies { $0.boutiqueDB = database }
```

Open options (official Turso flags): see **[docs/getting-started/open-options.md](docs/getting-started/open-options.md)**.

```swift
// Default: .tursoEnhanced (views, index_method, …)
// Cooperative async IO:
let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
```

### Capability matrix

| Feature | Status |
|---------|--------|
| Local CRUD + StructuredQueries | **Ready** |
| LiveQuery / CDC observation | **Ready** |
| Concurrent writes | **Ready** (CDC-safe) |
| CloudKit private sync | **Beta (offline-tested)** — physical-device production-container validation required |
| CloudKit sharing/public DB | **Not included in this beta** |
| Migrations | **Ready** |
| FTS / vector index / MV | **Opt-in** via `TursoOpenOptions` (official `index_method` / `views`) |
| Encryption / multi-process | **Opt-in** official tokens (experimental upstream; Data Protection still recommended) |

## CloudKit

- Entitlements: iCloud + CloudKit container
- Host capabilities: Push Notifications + `remote-notification` background mode
- Container: explicit identifier or injected `CKContainer` (no fallback)
- Attach: `BoutiqueDBSyncEngine.attach(to:automaticallyDrain: true)`
- QA: [docs/contributors/cloudkit-qa-checklist.md](docs/contributors/cloudkit-qa-checklist.md)
- Account switches preserve local rows and reset sync metadata; the host owns account UI/policy.

## Docs (prod-ready)

The `docs/` directory is the source for both Mintlify and GitBook.

| Doc | Topic |
|-----|--------|
| [Introduction](docs/index.md) | What BoutiqueDB is |
| [Stack](docs/stack.md) | Layers & modules |
| [Quick start](docs/getting-started/quick-start.md) | Install, model, migrate, write, observe |
| [Open options](docs/getting-started/open-options.md) | Official feature flags + asyncIO |
| [Architecture](docs/advanced/boutiquedb-architecture.md) | Layers & concurrency |
| [Migrations](docs/guides/migrations.md) | Append-only schema |
| [App template](docs/guides/app-template.md) | Safe app bootstrap |
| [CloudKit QA](docs/contributors/cloudkit-qa-checklist.md) | Sync checklist |
| [DocC catalog](Sources/BoutiqueDB/BoutiqueDB.docc/BoutiqueDB.md) | API, sync, operations |
| [Security policy](SECURITY.md) | Private vulnerability reporting and scope |

## Agent skills

Installable skills for agent users are in [`skills/`](skills/):

```bash
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-getting-started --agent pochi -y --copy
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-architecture --agent pochi -y --copy
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-sync --agent pochi -y --copy
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-open-options --agent pochi -y --copy
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-contributing --agent pochi -y --copy
```

## Build engine (maintainers)

```bash
# Requires Rust + Xcode; defaults to all macOS/iOS device/simulator slices
./Scripts/build-turso-sdk-xcframework.sh

# Then:
swift test
```

## License

MIT — see [LICENSE](LICENSE). Third-party notices: [NOTICE](NOTICE).

## Icon

Package icon: `Assets/BoutiqueDB.png` / `icon.png`.
