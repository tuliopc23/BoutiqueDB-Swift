import Foundation
import Observation
import StructuredQueries
import StructuredQueriesCore
import StructuredQueriesTurso

/// A SwiftUI/``@Observable``-friendly property wrapper that keeps an optional
/// single row up to date by observing the database change stream.
///
/// ```swift
/// @Observable final class NoteModel {
///   @ObservationIgnored @LiveQueryOne(model.db) { Note.where { $0.id.eq(id) }.asSelect() } var note: Note?
/// }
/// ```
@MainActor
@Observable
@propertyWrapper
public final class LiveQueryOne<Element: Table & Sendable>
where Element == Element.QueryOutput {
  public private(set) var wrappedValue: Element?
  public private(set) var loadError: (any Error)?
  public private(set) var isLoading: Bool = false

  private let db: BoutiqueDB
  private var query: @Sendable () -> SelectOf<Element>
  @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

  public init(
    wrappedValue: Element? = nil,
    _ db: BoutiqueDB,
    query: @escaping @Sendable () -> SelectOf<Element> = { Element.all.asSelect() }
  ) {
    self.wrappedValue = wrappedValue
    self.db = db
    self.query = query
    observationTask = Task { [weak self] in
      await self?.load()
      guard let self else { return }
      for await _ in self.db.store.subscribe() {
        await self.load()
      }
    }
  }

  deinit {
    observationTask?.cancel()
  }

  /// Replace the query factory and reload (parity with ``LiveQuery/setQuery``).
  public func setQuery(_ query: @escaping @Sendable () -> SelectOf<Element>) {
    self.query = query
    forceRefresh()
  }

  /// Manually re-runs the query and updates ``wrappedValue``.
  public func forceRefresh() {
    Task { await load() }
  }

  /// Awaitable reload of the current query.
  public func load() async {
    isLoading = true
    defer { isLoading = false }
    let q = query
    do {
      let row = try await db.read { try q().fetchOne($0.connection) }
      wrappedValue = row
      loadError = nil
    } catch {
      loadError = error
    }
  }

  /// Backward-compatible alias for ``forceRefresh()``.
  public func refresh() {
    forceRefresh()
  }
}
