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
  .package(url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git", from: "0.2.0"),
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

> **Engine binary:** SPM downloads `TursoSDK.xcframework.zip` from GitHub Releases (sdk-kit, no `unsafeFlags`). Maintainers: `./Scripts/build-turso-sdk-xcframework.sh` then set `BOUTIQUE_LOCAL_TURSO_SDK=1` for local path override.

## Platforms

| Platform | Minimum |
|----------|---------|
| iOS | 17.0 |
| macOS | 14.0 |

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

let db = try await BoutiqueDB.open(
  url: try BoutiqueDB.applicationSupportURL(),
  migrations: AppMigrations.plan
)

try await db.write { conn in
  try conn.execute(
    "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
    [.text("1"), .text("Hello"), .text("")]
  )
}

let rows = try await db.fetchAll(Note.self)
```

Open options (official Turso flags): see **[docs/Turso-Open-Options.md](docs/Turso-Open-Options.md)**.

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
| CloudKit sync | **Ready (offline-tested)** — live multi-device: validate in app |
| Migrations | **Ready** |
| FTS / vector index / MV | **Opt-in** via `TursoOpenOptions` (official `index_method` / `views`) |
| Encryption / multi-process | **Opt-in** official tokens (experimental upstream; Data Protection still recommended) |

## CloudKit

- Entitlements: iCloud + CloudKit container  
- Attach: `BoutiqueDBSyncEngine.attach(to:automaticallyDrain: true)`  
- QA: [docs/CloudKit-QA-Checklist.md](docs/CloudKit-QA-Checklist.md)

## Docs (prod-ready)

| Doc | Topic |
|-----|--------|
| [Turso-Open-Options](docs/Turso-Open-Options.md) | Official feature flags + asyncIO |
| [Architecture](docs/Architecture.md) | Layers & concurrency |
| [Migrations](docs/Migrations.md) | Append-only schema |
| [App-Template](docs/App-Template.md) | Safe app bootstrap |
| [CloudKit QA](docs/CloudKit-QA-Checklist.md) | Sync checklist |

## Build engine (maintainers)

```bash
# Requires Rust + Xcode; default slice: macos-arm64
./Scripts/build-turso-sdk-xcframework.sh

# Then:
swift test
```

## License

MIT — see [LICENSE](LICENSE). Third-party notices: [NOTICE](NOTICE).

## Icon

Package icon: `Assets/BoutiqueDB.png` / `icon.png`.
