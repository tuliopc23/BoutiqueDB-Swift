---
name: boutiquedb-getting-started
description: |
  Helps users install BoutiqueDB, run the first migration, insert data, and choose open options.
  Use when the user says "how do I install BoutiqueDB", "quick start", "getting started",
  "BoutiqueDB open options", or "BoutiqueDB SPM".
---

# BoutiqueDB getting started

Guide the user through installing BoutiqueDB-Swift via Swift Package Manager, opening a database, running migrations, and performing basic reads and writes.

## Trigger phrases

- "install BoutiqueDB"
- "BoutiqueDB quick start"
- "how do I open BoutiqueDB"
- "BoutiqueDB SPM"
- "BoutiqueDB open options"

## Workflow

1. **Check requirements**: iOS 17+ / macOS 14+, Swift 6.1+, Xcode 16+.
2. **Provide the Package.swift snippet**:
   ```swift
   .package(
     url: "https://github.com/tuliopc23/BoutiqueDB-Swift.git",
     exact: "0.3.0-beta.1"
   )
   ```
3. **Show the quick-start model, migration plan, open, and write/read example** from `docs/getting-started/quick-start.md`.
4. **Explain `TursoOpenOptions`**: default `.tursoEnhanced`, `.tursoEnhancedAsync`, `asyncIO`, `multiProcess`, `encryption`.
5. **Point to `docs/getting-started/`** for the full installation, quick-start, and open-options pages.
6. If the user is asking about local engine builds, route to the `boutiquedb-contributing` skill.

## Key files

- `Package.swift`
- `Sources/BoutiqueDB/BoutiqueDB.swift`
- `docs/getting-started/installation.md`
- `docs/getting-started/quick-start.md`
- `docs/getting-started/open-options.md`
