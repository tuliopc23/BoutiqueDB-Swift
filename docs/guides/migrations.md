---
title: "Schema Migrations"
sidebarTitle: "Migrations"
description: "Safely evolve your SQLite database schema using append-only, versioned BoutiqueDB migrations."
---

As your application evolves, your underlying database tables must adapt safely without causing data loss for existing users. BoutiqueDB provides an append-only, version-controlled migration system.

---

## Creating a Migration Plan

Define your migration steps in a `MigrationPlan`. Migrations are identified by unique string identifiers (e.g. `"v1_initial_schema"`, `"v2_add_avatar_url"`).

<Steps>
  <Step title="Define Version 1 Initial Schema">
    Create initial tables when the app is first launched.

    ```swift Migrations.swift
    import BoutiqueDB

    enum AppMigrations {
        static let plan = MigrationPlan([
            Migration("v1_create_users") { conn in
                try conn.execute("""
                    CREATE TABLE user_profile (
                        id TEXT PRIMARY KEY NOT NULL,
                        username TEXT NOT NULL UNIQUE,
                        createdAt REAL NOT NULL
                    )
                """)
            }
        ])
    }
    ```
  </Step>

  <Step title="Add Version 2 Migration Step">
    When adding new features in a app update, append a new migration step to the end of the array.

    ```swift Migrations.swift
    enum AppMigrations {
        static let plan = MigrationPlan([
            Migration("v1_create_users") { conn in
                try conn.execute("""
                    CREATE TABLE user_profile (
                        id TEXT PRIMARY KEY NOT NULL,
                        username TEXT NOT NULL UNIQUE,
                        createdAt REAL NOT NULL
                    )
                """)
            },
            
            Migration("v2_add_avatar_and_bio") { conn in
                try conn.execute("""
                    ALTER TABLE user_profile ADD COLUMN avatarUrl TEXT;
                    ALTER TABLE user_profile ADD COLUMN bio TEXT DEFAULT '';
                """)
            }
        ])
    }
    ```
  </Step>

  <Step title="Pass Migration Plan to Database Initialization">
    Pass the plan into `BoutiqueDB.open`:

    ```swift AppStore.swift
    let db = try await BoutiqueDB.open(
        url: storeURL,
        migrations: AppMigrations.plan
    )
    ```
  </Step>
</Steps>

---

## Migration Safety & Transactions

<CardGroup cols={2}>
  <Card title="Transactional Execution" icon="lock">
    All steps within a single `Migration` run inside a dedicated SQLite transaction. If a statement fails, changes are completely rolled back.
  </Card>
  <Card title="Internal Bookkeeping" icon="book">
    BoutiqueDB tracks executed migration IDs in a system table (`_boutiquedb_migrations`). Executed migrations are never re-run.
  </Card>
</CardGroup>

<Warning>
**Never Remove or Reorder Migrations**: Migrations are strictly append-only. Never modify or delete previously shipped migration IDs once an app version has been released to users!
</Warning>
