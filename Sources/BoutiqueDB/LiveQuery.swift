import Foundation
import Observation
import StructuredQueries
import StructuredQueriesCore
import StructuredQueriesTurso
import TursoKit

/// A SwiftUI/`@Observable`-friendly property wrapper that keeps an array of
/// `Table` rows up to date by observing the database change stream.
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
  @ObservationIgnored nonisolated(unsafe) private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var queryRevision: UInt64 = 0
  @ObservationIgnored private var loadRevision: UInt64 = 0
  @ObservationIgnored private var loadContinuations: [UInt64: CheckedContinuation<Void, Never>] = [:]

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
    refreshTask?.cancel()
  }

  /// Replace the query factory (e.g. new FTS search text) and reload.
  public func setQuery(_ query: @escaping @Sendable () -> SelectOf<Element>) {
    self.query = query
    queryRevision &+= 1
    forceRefresh()
  }

  public func forceRefresh() {
    refreshTask?.cancel()
    loadRevision &+= 1
    let queryRevision = queryRevision
    let loadRevision = loadRevision
    refreshTask = Task { [weak self] in
      await self?.load(queryRevision: queryRevision, loadRevision: loadRevision)
    }
  }

  /// Awaitable reload of the current query. Returns once the result for this
  /// call (or a newer in-flight load) has been applied to ``wrappedValue``.
  public func load() async {
    refreshTask?.cancel()
    loadRevision &+= 1
    let awaited = loadRevision
    let queryRevision = queryRevision
    await withCheckedContinuation { continuation in
      loadContinuations[awaited] = continuation
      Task { [weak self] in
        await self?.load(queryRevision: queryRevision, loadRevision: awaited)
      }
    }
  }

  private func load(queryRevision: UInt64, loadRevision: UInt64) async {
    isLoading = true
    let q = query
    do {
      let rows = try await db.read { try await q().fetchAll($0.connection) }
      guard
        !Task.isCancelled, queryRevision == self.queryRevision,
        loadRevision == self.loadRevision
      else { return }
      wrappedValue = rows
      loadError = nil
    } catch {
      guard
        !Task.isCancelled, queryRevision == self.queryRevision,
        loadRevision == self.loadRevision
      else { return }
      loadError = error
    }
    if queryRevision == self.queryRevision, loadRevision == self.loadRevision {
      isLoading = false
      signalLoadCompletion()
    }
  }

  private func signalLoadCompletion() {
    let current = loadRevision
    let ready = loadContinuations.filter { $0.key <= current }
    for (_, continuation) in ready {
      continuation.resume()
    }
    loadContinuations = loadContinuations.filter { $0.key > current }
  }

  public func refresh() {
    forceRefresh()
  }

  private func startObserving() {
    forceRefresh()
    observationTask = Task { [weak self] in
      guard let self else { return }
      for await _ in self.db.store.subscribe() {
        await self.load()
      }
    }
  }
}
