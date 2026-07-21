import Foundation
import Observation
import TursoKit

/// Polls `turso_cdc` (or accepts manual invalidation) so SwiftUI can refresh after writes.
///
/// Prefer calling `invalidate()` after local writes when you already know data changed.
/// Polling is a fallback when another connection mutates the file.
@MainActor
@Observable
public final class TursoStore {
  public private(set) var generation: UInt64 = 0
  public private(set) var lastChangeID: Int64 = 0

  private let connection: TursoConnection
  private var timer: Timer?
  private let pollInterval: TimeInterval

  public init(connection: TursoConnection, pollInterval: TimeInterval = 0.5) {
    self.connection = connection
    self.pollInterval = pollInterval
    self.lastChangeID = (try? Self.maxChangeID(on: connection)) ?? 0
  }

  public func invalidate() {
    generation &+= 1
  }

  /// Starts a RunLoop timer that advances `generation` when new CDC rows appear.
  public func startPolling() {
    stopPolling()
    let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.poll()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  public func stopPolling() {
    timer?.invalidate()
    timer = nil
  }

  public func poll() {
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

  public init(store: TursoStore, initial: Value, fetch: @escaping () throws -> Value) {
    self.store = store
    self.fetch = fetch
    self.value = initial
    self.lastGeneration = store.generation
  }

  public func refreshIfNeeded() {
    guard store.generation != lastGeneration else { return }
    lastGeneration = store.generation
    if let next = try? fetch() {
      value = next
    }
  }

  public func forceRefresh() {
    lastGeneration = store.generation
    if let next = try? fetch() {
      value = next
    }
  }
}
