import BoutiqueDB
import Foundation
import Testing
import TursoKit

@Suite("BoutiqueDB migrations")
@MainActor
struct MigrationTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("migrate-\(UUID().uuidString).db")
  }

  @Test func openAppliesMigrationsIdempotently() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration("v1_create_items") { db in
        try await db.execute(
          """
          CREATE TABLE items (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL
          )
          """
        )
      }
      BoutiqueMigration("v2_add_body") { db in
        try await db.ensureColumn(table: "items", name: "body", sqlType: "TEXT", default: "''")
      }
    }

    let db1 = try await BoutiqueDB.open(
      url: url,
      startListening: false,
      migrations: plan)
    defer { db1.close() }
    let applied1 = try await db1.appliedMigrations()
    #expect(applied1 == ["v1_create_items", "v2_add_body"])
    #expect(try await db1.tableExists("items"))
    #expect(try await db1.columnExists(table: "items", name: "body"))

    // Re-open: no double-apply
    let db2 = try await BoutiqueDB.open(
      url: url,
      startListening: false,
      migrations: plan)
    defer { db2.close() }
    let applied2 = try await db2.appliedMigrations()
    #expect(applied2 == applied1)
  }

  @Test func ensureColumnIsIdempotent() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let db = try BoutiqueDB(url: url, startListening: false)
    defer { db.close() }
    try await db.execute(
      "CREATE TABLE t (id TEXT PRIMARY KEY NOT NULL)"
    )
    try await db.ensureColumn(table: "t", name: "x", sqlType: "TEXT", default: "''")
    try await db.ensureColumn(table: "t", name: "x", sqlType: "TEXT", default: "''")
    #expect(try await db.columnExists(table: "t", name: "x"))
  }

  @Test func onlyNewMigrationsRun() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let v1 = BoutiqueMigrationPlan {
      BoutiqueMigration("v1") { db in
        try await db.execute("CREATE TABLE t (id TEXT PRIMARY KEY NOT NULL)")
      }
    }
    _ = try await BoutiqueDB.open(url: url, startListening: false, migrations: v1)

    let v2 = BoutiqueMigrationPlan {
      BoutiqueMigration("v1") { _ in
        Issue.record("v1 should not re-run")
      }
      BoutiqueMigration("v2") { db in
        try await db.ensureColumn(table: "t", name: "n", sqlType: "INTEGER", default: "0")
      }
    }
    let db = try await BoutiqueDB.open(url: url, startListening: false, migrations: v2)
    defer { db.close() }
    #expect(try await db.appliedMigrations() == ["v1", "v2"])
    #expect(try await db.columnExists(table: "t", name: "n"))
  }

  @Test func failedMigrationIsNotRecorded() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration("bad") { db in
        try await db.execute("THIS IS NOT SQL")
      }
    }
    let db = try BoutiqueDB(url: url, startListening: false)
    defer { db.close() }
    do {
      _ = try await db.migrate(using: plan)
      Issue.record("expected failure")
    } catch {
      // expected
    }
    let applied = try await db.appliedMigrations()
    #expect(!applied.contains("bad"))
  }

  @Test func schemaSyncAdditiveCreatesMissingTable() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    enum ItemsSchema: BoutiqueSchema {
      static var boutiqueTableName: String { "items" }
      static var boutiqueCreateStatements: [String] {
        [
          """
          CREATE TABLE IF NOT EXISTS "items" (
            "id" TEXT PRIMARY KEY NOT NULL,
            "title" TEXT NOT NULL
          )
          """
        ]
      }
    }

    let db = try await BoutiqueDB.open(
      url: url,
      startListening: false,
      schemaModels: [ItemsSchema.self],
      schemaSync: .additiveOnly)
    defer { db.close() }
    #expect(try await db.tableExists("items"))
  }

  @Test func migrateUsingManualConformanceCreate() async throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    enum NotesSchema: BoutiqueSchema {
      static var boutiqueTableName: String { "manual_notes" }
      static var boutiqueCreateStatements: [String] {
        [
          """
          CREATE TABLE IF NOT EXISTS "manual_notes" (
            "id" TEXT PRIMARY KEY NOT NULL,
            "title" TEXT NOT NULL
          )
          """
        ]
      }
    }

    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration("create_notes") { db in
        try await db.create(NotesSchema.self)
      }
    }
    let db = try await BoutiqueDB.open(url: url, startListening: false, migrations: plan)
    defer { db.close() }
    #expect(try await db.tableExists("manual_notes"))
  }

  @Test func duplicateMigrationIdentifiersAreRejected() async throws {
    let url = tempURL()
    let db = try BoutiqueDB(url: url, startListening: false)
    defer { db.close() }
    defer {
      db.close()
      try? FileManager.default.removeItem(at: url)
    }
    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration("duplicate", transaction: { _ in })
      BoutiqueMigration("duplicate", transaction: { _ in })
    }
    await #expect(throws: BoutiqueError.self) {
      try await db.migrate(using: plan)
    }
  }

  @Test func transactionalMigrationRollsBackBodyAndTrackingTogether() async throws {
    let url = tempURL()
    let db = try BoutiqueDB(url: url, startListening: false)
    defer { db.close() }
    defer {
      db.close()
      try? FileManager.default.removeItem(at: url)
    }
    let plan = BoutiqueMigrationPlan {
      BoutiqueMigration(
        "atomic",
        transaction: { connection in
          try connection.execute("CREATE TABLE atomic_items (id INTEGER PRIMARY KEY)")
          try connection.execute("THIS IS NOT SQL")
        })
    }
    await #expect(throws: BoutiqueError.self) {
      try await db.migrate(using: plan)
    }
    #expect(!(try await db.tableExists("atomic_items")))
    #expect(!(try await db.appliedMigrations().contains("atomic")))
  }

  @Test func appliedMigrationHistoryCannotBeReordered() async throws {
    let url = tempURL()
    let initial = BoutiqueMigrationPlan {
      BoutiqueMigration(
        "v1",
        transaction: { connection in
          try connection.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY)")
        })
      BoutiqueMigration("v2", transaction: { _ in })
    }
    let db = try await BoutiqueDB.open(url: url, startListening: false, migrations: initial)
    defer { db.close() }
    defer {
      db.close()
      try? FileManager.default.removeItem(at: url)
    }
    let reordered = BoutiqueMigrationPlan {
      BoutiqueMigration("v2", transaction: { _ in })
      BoutiqueMigration("v1", transaction: { _ in })
    }
    await #expect(throws: BoutiqueError.self) {
      try await db.migrate(using: reordered)
    }
  }
}
