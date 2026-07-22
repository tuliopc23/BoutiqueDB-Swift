import BoutiqueDB
import Foundation

@main
@MainActor
struct BoutiqueDBConsumer {
  static func main() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("boutiquedb-consumer-\(UUID().uuidString).db")
    let database = try await BoutiqueDB.open(
      BoutiqueDBConfiguration(url: url, startListening: false)
    )
    defer {
      database.close()
      try? FileManager.default.removeItem(at: url)
    }
    try await database.execute("CREATE TABLE smoke (id TEXT PRIMARY KEY NOT NULL)")
  }
}
