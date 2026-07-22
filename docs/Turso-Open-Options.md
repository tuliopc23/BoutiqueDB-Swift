# Turso open options (official sdk-kit path)

BoutiqueDB opens the engine through Turso’s **language-binding C ABI** (`sdk-kit` / `turso.h`), not the limited sqlite3-compat experimental toggle.

## Surfaces

| Surface | Use |
|---------|-----|
| **sdk-kit** (`CTursoSDK` / `libturso_sdk_kit`) | **Primary** — `experimental_features`, encryption, `async_io` |
| sqlite3 C (`libturso_sqlite3`) | Legacy only; not used for feature flags |

## Official feature tokens

From Turso docs (`experimental-features.mdx`):

`views` · `custom_types` · `encryption` · `index_method` · `autovacuum` · `vacuum` · `attach` · `generated_columns` · `without_rowid` · `multiprocess_wal` · `mvcc_passive_checkpoint`

Mapped in Swift as ``TursoExperimentalFeature``.

## BoutiqueDB defaults

```swift
// Default open uses .tursoEnhanced:
// views, index_method, generated_columns, vacuum, without_rowid
let db = try BoutiqueDB(url: url)

// Minimal (no experimental SQL features):
let db = try BoutiqueDB(url: url, openOptions: TursoOpenOptions())

// Multi-process WAL (App Group for extensions):
let db = try BoutiqueDB(url: url, multiProcess: true)

// Engine encryption (Keychain-held key recommended):
let db = try BoutiqueDB(
  url: url,
  encryption: .aegis256(key: keyData) // 32 bytes
)
```

## Rebuild vendor lib

```bash
./Scripts/build-turso-sdk-kit.sh
# optional: TURSO_SDK_FEATURES=fts,encryption
```

## Async (cooperative IO)

`TursoOpenOptions.asyncIO` maps to official sdk-kit `async_io`.

| Mode | Behavior |
|------|----------|
| `asyncIO: false` (default / `.tursoEnhanced`) | `step()` drives `TURSO_IO` in a tight loop (no Swift suspension) |
| `asyncIO: true` / `.tursoEnhancedAsync` | `DatabaseActor` uses `stepAsync()` → `run_io` + `await Task.yield()` between IO ticks, with exclusive depth so the actor does not interleave two statements |

```swift
let db = try BoutiqueDB(url: url, openOptions: .tursoEnhancedAsync)
try await db.write { conn in
  try conn.execute("INSERT …")
}
```

Import/markdown: parse off MainActor, then `await db.write` — UI stays free; engine IO cooperates with Swift concurrency.

## Policy

- No private `DatabaseOpts` hacks on sqlite3 open.
- Experimental flags are opt-in (except curated `.tursoEnhanced` default for product DX).
- Capability probes remain a runtime safety net.
