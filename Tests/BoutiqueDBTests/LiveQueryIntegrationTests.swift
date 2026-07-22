import BoutiqueDB
import Foundation
import Observation
import StructuredQueries
import Testing

@Table
struct IntegrationNote: Sendable {
  @Column(primaryKey: true) let id: String
  var title: String
  var body: String
}

@MainActor
@Observable
final class NotesModel {
  let db: BoutiqueDB
  @ObservationIgnored
  private let liveNotes: LiveQuery<IntegrationNote>

  var notes: [IntegrationNote] { liveNotes.wrappedValue }

  init(db: BoutiqueDB) {
    self.db = db
    self.liveNotes = LiveQuery(db) { IntegrationNote.all.asSelect() }
  }
}

@Suite("LiveQuery SwiftUI / Observation integration")
@MainActor
struct LiveQueryIntegrationTests {
  private func waitFor(
    timeout: Duration = .seconds(1),
    poll: Duration = .milliseconds(10),
    _ condition: @MainActor () async -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: poll)
    }
    return await condition()
  }

  @Test func liveQueryUpdatesWithinOneSecond() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("boutique-int-\(UUID().uuidString).db")
    let db = try BoutiqueDB(url: url, startListening: true)
    defer { try? FileManager.default.removeItem(at: url) }
    defer { db.close() }

    // Match StructuredQueries default table naming for `IntegrationNote`.
    try await db.execute(
      """
      CREATE TABLE "integrationNotes" (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL
      )
      """
    )

    let model = NotesModel(db: db)
    _ = await waitFor(timeout: .milliseconds(500)) {
      model.notes.isEmpty
    }

    try await db.write { conn in
      try IntegrationNote.insert {
        IntegrationNote(id: "i1", title: "SwiftUI", body: "ok")
      }.execute(conn.connection)
    }

    let updated = await waitFor(timeout: .seconds(1)) {
      model.notes.map(\.id) == ["i1"]
    }
    #expect(updated)
    #expect(model.notes.first?.title == "SwiftUI")
  }
}
