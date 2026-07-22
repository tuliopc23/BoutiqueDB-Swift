# ``BoutiqueDB``

Build local-first Swift applications on Turso with typed queries, observable
results, migrations, and optional private CloudKit synchronization.

## Overview

BoutiqueDB keeps the local database authoritative. Reads and writes pass through
a serialized database actor, successful local commits invalidate observations,
and the optional `TursoCKSync` layer durably stages CDC changes before advancing
its cursor.

Open a store from one configuration value so production, previews, tests, and
debug rebuilds use the same engine settings:

```swift
let configuration = BoutiqueDBConfiguration(
  url: try BoutiqueDB.applicationSupportURL(filename: "app.db"),
  concurrentWrites: true,
  migrations: AppMigrations.plan
)
let database = try await BoutiqueDB.open(configuration)
```

Install the opened instance into Dependencies only after the asynchronous open
has completed:

```swift
let database = try await BoutiqueDB.open(configuration)
prepareDependencies {
  $0.boutiqueDB = database
}
```

Call ``BoutiqueDB/close()`` before replacing or deleting a database. The method
is idempotent and closes observation, the connection, and the native
database in dependency order.

## Topics

### Opening and lifecycle

- ``BoutiqueDBConfiguration``
- ``BoutiqueDB/open(_:)``
- ``BoutiqueDB/close()``

### Persistence

- ``BoutiqueDB/read(_:)``
- ``BoutiqueDB/write(_:)``
- ``BoutiqueDB/writeConcurrent(maxAttempts:_:)``
- ``BoutiqueMigration``
- ``BoutiqueMigrationPlan``

### Schema and queries

- ``BoutiqueSchema``
- ``BoutiqueSchemaColumns``
- ``LiveQuery``
- ``LiveQueryOne``

### Synchronization

- <doc:CloudKitSynchronization>
- <doc:ProductionOperations>
