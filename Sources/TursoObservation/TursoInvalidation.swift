import Foundation
import Observation
import TursoKit

/// A change notification emitted by ``TursoStore``.
public enum ChangeEvent: Sendable, Equatable {
  case generation(UInt64)
}

/// Observes `turso_cdc` (and accepts manual invalidation) so SwiftUI / LiveQuery
/// can refresh after writes.
///
/// - Important: The in-memory ``lastChangeID`` cursor is independent of
///   TursoCKSync's persistent `ck_cdc_cursor`. Observation never advances sync state.
///
/// Prefer calling ``invalidate()`` after local writes when you already know data
/// changed. The CDC listener covers mutations from other connections.
@MainActor
@Observable
public final class TursoStore {
  public private(set) var generation: UInt64 = 0
  public private(set) var lastChangeID: Int64 = 0

  /// Convenience multi-consumer stream (each access creates a new subscription).
  public var changes: AsyncStream<ChangeEvent> { subscribe() }

  private let connection: TursoConnection
  private let idlePollInterval: Duration
  /// Stored for cancellation from nonisolated `deinit`.
  @ObservationIgnored nonisolated(unsafe) private var listenerTask: Task<Void, Never>?
  @ObservationIgnored nonisolated(unsafe) private var continuations:
    [UUID: AsyncStream<ChangeEvent>.Continuation] = [:]

  public init(
    connection: TursoConnection,
    idlePollInterval: Duration = .milliseconds(50)
  ) {
    self.connection = connection
    self.idlePollInterval = idlePollInterval
    self.lastChangeID = (try? Self.maxChangeID(on: connection)) ?? 0
  }

  deinit {
    listenerTask?.cancel()
    for continuation in continuations.values {
      continuation.finish()
    }
  }

  /// Bumps ``generation`` and yields ``ChangeEvent/generation(_:)`` to all subscribers.
  public func invalidate() {
    generation &+= 1
    let event = ChangeEvent.generation(generation)
    for continuation in continuations.values {
      continuation.yield(event)
    }
  }

  /// Creates a new multi-consumer subscription. Each LiveQuery should call this once.
  public func subscribe() -> AsyncStream<ChangeEvent> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let id = UUID()
      self.continuations[id] = continuation
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { @MainActor [weak self] in
          self?.continuations[id] = nil
        }
      }
    }
  }

  /// Starts a cooperative CDC listener (no `Timer` / `RunLoop`).
  public func startListening() {
    stopListening()
    let connection = self.connection
    let idlePollInterval = self.idlePollInterval
    var last = lastChangeID

    listenerTask = Task { [weak self] in
      while !Task.isCancelled {
        let maxID = (try? Self.maxChangeID(on: connection)) ?? last
        if maxID > last {
          last = maxID
          await MainActor.run { [weak self] in
            guard let self else { return }
            self.lastChangeID = maxID
            self.invalidate()
          }
        } else {
          try? await Task.sleep(for: idlePollInterval)
        }
      }
    }
  }

  public func stopListening() {
    listenerTask?.cancel()
    listenerTask = nil
  }

  /// Advances from CDC once and invalidates if new rows appeared.
  /// Useful for tests that drive a single connection without waiting on the listener.
  public func advanceFromCDC() {
    guard let maxID = try? Self.maxChangeID(on: connection) else { return }
    if maxID > lastChangeID {
      lastChangeID = maxID
      invalidate()
    }
  }

  private nonisolated static func maxChangeID(on connection: TursoConnection) throws -> Int64 {
    try connection.queryOne("SELECT COALESCE(MAX(change_id), 0) AS m FROM turso_cdc")?["m"]?
      .int64Value ?? 0
  }
}

/// Re-runs a fetch whenever `TursoStore.generation` changes.
@MainActor
@Observable
public final class TursoQueryBox<Value> {
  public private(set) var value: Value

  private let store: TursoStore
  private let fetch: () throws -> Value
  private var lastGeneration: UInt64
  @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

  public init(store: TursoStore, initial: Value, fetch: @escaping () throws -> Value) {
    self.store = store
    self.fetch = fetch
    self.value = initial
    self.lastGeneration = store.generation
    observe()
  }

  deinit {
    observationTask?.cancel()
  }

  public func refreshIfNeeded() {
    guard store.generation != lastGeneration else { return }
    forceRefresh()
  }

  public func forceRefresh() {
    lastGeneration = store.generation
    if let next = try? fetch() {
      value = next
    }
  }

  private func observe() {
    observationTask = Task { [weak self] in
      guard let self else { return }
      for await _ in self.store.subscribe() {
        self.forceRefresh()
      }
    }
  }
}
