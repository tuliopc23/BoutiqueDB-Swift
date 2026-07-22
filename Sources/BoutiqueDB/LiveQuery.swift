import Foundation
import Observation
import StructuredQueries
import StructuredQueriesCore
import StructuredQueriesTurso
import TursoKit

/// A SwiftUI/``@Observable``-friendly property wrapper that keeps an array of
/// ``Table`` rows up to date by observing the database change stream.
@MainActor
@Observable
@propertyWrapper
public final class LiveQuery<Element: Table & Sendable>
where Element == Element.QueryOutput {
  public private(set) var wrappedValue: [Element]
  public private(set) var loadError: (any Error)?
  public private(set) var isLoading: Bool = false

  private let db: BoutiqueDB
  private var query: @Sendable () -> SelectOf<Element>
  @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

  public init(
    wrappedValue: [Element] = [],
    _ db: BoutiqueDB,
    query: @escaping @Sendable () -> SelectOf<Element> = { Element.all.asSelect() }
  ) {
    self.wrappedValue = wrappedValue
    self.db = db
    self.query = query
    startObserving()
  }

  deinit {
    observationTask?.cancel()
  }

  /// Replace the query factory (e.g. new FTS search text) and reload.
  public func setQuery(_ query: @escaping @Sendable () -> SelectOf<Element>) {
    self.query = query
    forceRefresh()
  }

  public func forceRefresh() {
    Task { await load() }
  }

  public func load() async {
    isLoading = true
    defer { isLoading = false }
    let q = query
    do {
      let rows = try await db.read { try q().fetchAll($0.connection) }
      wrappedValue = rows
      loadError = nil
    } catch {
      loadError = error
    }
  }

  public func refresh() {
    forceRefresh()
  }

  private func startObserving() {
    observationTask = Task { [weak self] in
      await self?.load()
      guard let self else { return }
      for await _ in self.db.store.subscribe() {
        await self.load()
      }
    }
  }
}
