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
  /// Latest CDC listener failure. A later successful poll clears it.
  public private(set) var listenerError: String?

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
    idlePollInterval: Duration = .milliseconds(250)
  ) async throws {
    self.connection = connection
    self.idlePollInterval = idlePollInterval
    self.lastChangeID = try await Self.maxChangeID(on: connection)
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

    listenerTask = Task.detached(priority: .utility) { [weak self] in
      while !Task.isCancelled {
        do {
          let maxID = try await Self.maxChangeID(on: connection)
          if maxID > last {
            last = maxID
            await MainActor.run { [weak self] in
              guard let self else { return }
              self.listenerError = nil
              self.lastChangeID = maxID
              self.invalidate()
            }
          } else {
            await MainActor.run { [weak self] in self?.listenerError = nil }
            try await Task.sleep(for: idlePollInterval)
          }
        } catch is CancellationError {
          return
        } catch {
          await MainActor.run { [weak self] in
            self?.listenerError = String(describing: error)
          }
          try? await Task.sleep(for: .seconds(1))
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
  public func advanceFromCDC() async {
    do {
      let maxID = try await Self.maxChangeID(on: connection)
      listenerError = nil
      if maxID > lastChangeID {
        lastChangeID = maxID
        invalidate()
      }
    } catch {
      listenerError = String(describing: error)
    }
  }

  private nonisolated static func maxChangeID(on connection: TursoConnection) async throws -> Int64
  {
    do {
      return
        (try await connection.queryOne(
          "SELECT COALESCE(MAX(change_id), 0) AS m FROM turso_cdc"
        ))?["m"]?
        .int64Value ?? 0
    } catch let error as TursoError where error.message.contains("no such table: turso_cdc") {
      return 0
    }
  }
}

/// Re-runs a fetch whenever `TursoStore.generation` changes.
@MainActor
@Observable
public final class TursoQueryBox<Value> {
  public private(set) var value: Value
  /// Latest refresh failure. A successful refresh clears it.
  public private(set) var fetchError: String?

  private let store: TursoStore
  private let fetch: () async throws -> Value
  private var lastGeneration: UInt64
  @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

  public init(store: TursoStore, initial: Value, fetch: @escaping () async throws -> Value) {
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
    Task { await forceRefresh() }
  }

  public func forceRefresh() async {
    lastGeneration = store.generation
    do {
      let next = try await fetch()
      value = next
      fetchError = nil
    } catch {
      fetchError = String(describing: error)
    }
  }

  private func observe() {
    observationTask = Task { [weak self] in
      guard let self else { return }
      for await _ in self.store.subscribe() {
        await self.forceRefresh()
      }
    }
  }
}
