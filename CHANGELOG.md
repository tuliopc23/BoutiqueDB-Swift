# Changelog

All notable changes to the **BoutiqueDB** Swift package are documented here.

## Unreleased

### Planned
- DocC polish and broader public docs

## 0.2.1 — 2026-07-22

### Packaging (SPI iOS + macOS)
- **Multi-arch `TursoSDK.xcframework`:** macOS (arm64+x86_64), iOS device (arm64), iOS Simulator (arm64+x86_64)
- Default `./Scripts/build-turso-sdk-xcframework.sh` always builds full SPI set (`SLICES=all`)
- `.spi.yml` enables **macos-xcodebuild** and **ios**
- CI: multi-arch engine build + iOS Simulator job
- Permanent agent rule: `AGENTS.md` — never ship macOS-only for public/SPI
- Engine: pure-rust crypto path for `target_os = "ios"` (BoutiqueDB core)

## 0.2.0 — 2026-07-22

### Packaging (SPI-ready)
- **No `unsafeFlags`:** `Package.swift` uses `binaryTarget` `TursoSDK` (release zip URL + optional local path)
- GitHub Release asset: `TursoSDK.xcframework.zip` (sdk-kit, macOS arm64 only)
- `Scripts/build-turso-sdk-xcframework.sh` for maintainer/CI builds
- `LICENSE`, `NOTICE`, `.spi.yml`, `docs/Publishing.md`
- Public repo: [tuliopc23/BoutiqueDB-Swift](https://github.com/tuliopc23/BoutiqueDB-Swift)
- CI: build xcframework when engine available; `release.yml` on `v*` tags

### Changed
- **Engine binding:** TursoKit now uses official **sdk-kit** C ABI (`turso.h` / `libturso_sdk_kit`) instead of sqlite3-compat for open/step.
- Experimental features enabled via official `experimental_features` CSV (`TursoOpenOptions`).
- Default open preset ``TursoOpenOptions/tursoEnhanced`` (views, index_method, generated_columns, vacuum, without_rowid).
- Encryption / multi-process map to official tokens + config fields (no longer always throw).
- Cooperative async: ``TursoOpenOptions/asyncIO`` / ``TursoOpenOptions/tursoEnhancedAsync`` drives official `TURSO_IO` with `Task.yield()` under `DatabaseActor` exclusive sections.

### Added
- `Scripts/build-turso-sdk-kit.sh`, `Sources/CTursoSDK`, `docs/Turso-Open-Options.md`
- `TursoStatement.stepOnce` / `stepAsync`, `TursoConnection.executeAsync` / `writeAsync` / `readAsync`
- Framework icon (`Assets/BoutiqueDB.png`, `icon.png`)
- Architecture doc (`docs/Architecture.md`)
- Migration stack: `BoutiqueMigrationPlan`, `open(migrations:)`, `ensureColumn`, additive schema sync
- Turso feature surface: MVCC dual connection, Vector32, FTS/vector DSL, capabilities probe
- CloudKit: `SyncAdapter` / `CloudKitSyncAdapter`, `SyncStatus` stream
- LiveQuery / LiveQueryOne `setQuery` for dynamic reloads
- `beginConcurrent` / `commitConcurrent` / `rollbackConcurrent` (session-guarded)
- `BoutiqueDBSyncEngine.attach(to:)` auto-drain via `onLocalCommit`
- `BoutiqueSchemaColumns` for additive column ensure in `syncSchema`
- Account status → `SyncStatus.needsAuthentication` (`applyAccountStatus` / inject)
- CI workflow `.github/workflows/swift.yml`

### Fixed (prod readiness)
- Concurrent writes always CDC-captured when CDC is enabled (MVCC+CDC writer or busy-retry IMMEDIATE fallback — no silent sync loss)
- `fetchOne` propagates SQL/decode errors; `nil` only for missing row
- `StringQueryBindable` no longer `preconditionFailure`s on invalid DB data
- `isSynchronizing` locked; prefer `isApplyingRemoteChanges` / `withSynchronizingFlag`
- Conflict LWW no longer upserts empty table/rowPK meta
- `Vector32Sparse` parses `[[i,v],…]` JSON
- Canonical Application Support dir: `BoutiqueDB/`

### Breaking
- Primary connection is package-visible; apps use `unsafeConnection` for advanced attachment
- `fetchOne` is now `throws`
- `StringQueryBindable.queryOutput` is `Self` (not `String`)

## 0.1.0 — 2026-07-22

- Initial v2 implementation cycle (OpenSpec `boutiquedb-v2` archived)
