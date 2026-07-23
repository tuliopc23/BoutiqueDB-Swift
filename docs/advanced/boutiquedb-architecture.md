---
title: "BoutiqueDB Architecture"
sidebarTitle: "Architecture"
description: "Deep dive into BoutiqueDB target modules, swift-structured-queries driver integration, and DatabaseActor thread isolation."
---

`BoutiqueDB` is organized into focused Swift targets, balancing SQLite-compatible C APIs with high-level Swift ergonomics.

---

## Target Layer Architecture

```
BoutiqueDB/
├── Package.swift
├── Sources/
│   ├── BoutiqueDB/                     # Main public framework API & DatabaseActor
│   ├── TursoKit/                       # Native C ABI handles, Statement execution, CDC
│   ├── StructuredQueriesTurso/         # StructuredQueries driver integration
│   ├── TursoCKSync/                    # CKSyncEngine CloudKit synchronizer
│   └── TursoObservation/               # CDC change token invalidation engine
└── Vendor/
    └── TursoSDK.xcframework            # Prebuilt libturso_sdk_kit multi-arch binary
```

---

## Component Responsibilities

<CardGroup cols={2}>
  <Card title="BoutiqueDB Target" icon="cubes">
    Public API umbrella containing `BoutiqueDB`, `@LiveQuery`, `@LiveQueryOne`, and `@BoutiqueTable` macro wrappers.
  </Card>
  <Card title="StructuredQueriesTurso" icon="magnifying-glass">
    Swift driver mapping `StructuredQueries` expressions (`@Table`) to Turso SQLite database connections.
  </Card>
  <Card title="TursoObservation" icon="bolt">
    Monitors `turso_cdc` table change counters and dispatches change token invalidations to active subscriber queries.
  </Card>
  <Card title="TursoCKSync" icon="cloud">
    Serializes changed CDC rows into CloudKit `CKRecord` structures for `CKSyncEngine` processing.
  </Card>
</CardGroup>
