import Foundation
import TursoKit

/// Serializes all database I/O for a single ``TursoConnection``.
///
/// ``BoutiqueDB`` stays `@MainActor` for SwiftUI integration; engine work runs here.
///
/// When the connection uses cooperative ``TursoOpenOptions/asyncIO``, methods
/// suspend on `TURSO_IO` via `Task.yield()` while holding an exclusive depth
/// counter so actor reentrancy cannot interleave two statements on one handle.
actor DatabaseActor {
  let connection: TursoConnection
  private enum ManualTransactionState {
    case idle
    case active
    case poisoned(String)
  }
  private var manualTransactionState = ManualTransactionState.idle
  /// Non-zero while a read/write is in progress (blocks re-entrant actor work).
  private var exclusiveDepth = 0

  init(connection: TursoConnection) {
    self.connection = connection
  }

  func read<T: Sendable>(
    _ body: @Sendable (BoutiqueDBConnection) async throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      return try await connection.readAsync { @Sendable in
        let conn = BoutiqueDBConnection(connection)
        return try await body(conn)
      }
    }
  }

  func write<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) async throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      return try await connection.writeAsync { @Sendable in
        var conn = BoutiqueDBConnection(connection)
        return try await body(&conn)
      }
    }
  }

  func transaction<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) async throws -> T
  ) async throws -> T {
    try await write(body)
  }

  func writeConcurrent<T: Sendable>(
    maxAttempts: Int,
    baseDelayNanoseconds: UInt64,
    _ body: @Sendable (inout BoutiqueDBConnection) async throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      var attempt = 0
      var delay = baseDelayNanoseconds
      while true {
        attempt += 1
        do {
          return try await connection.writeConcurrentAsync { @Sendable in
            var conn = BoutiqueDBConnection(connection)
            return try await body(&conn)
          }
        } catch let error as TursoError
          where error.code == TursoError.busy.code && attempt < maxAttempts
        {
          try await Task.sleep(nanoseconds: delay)
          delay = min(delay &* 2, 200_000_000)
          continue
        }
      }
    }
  }

  func writeWithBusyRetry<T: Sendable>(
    maxAttempts: Int,
    baseDelayNanoseconds: UInt64,
    _ body: @Sendable (inout BoutiqueDBConnection) async throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      var attempt = 0
      var delay = baseDelayNanoseconds
      while true {
        attempt += 1
        do {
          return try await connection.writeAsync { @Sendable in
            var conn = BoutiqueDBConnection(connection)
            return try await body(&conn)
          }
        } catch let error as TursoError
          where error.code == TursoError.busy.code && attempt < maxAttempts
        {
          try await Task.sleep(nanoseconds: delay)
          delay = min(delay &* 2, 200_000_000)
          continue
        }
      }
    }
  }

  func beginConcurrent() async throws {
    try await withExclusive {
      if case .idle = manualTransactionState {
        // continue
      } else {
        throw BoutiqueError.transactionInProgress
      }
      try await connection.executeAsync("BEGIN CONCURRENT")
      manualTransactionState = .active
    }
  }

  func commitConcurrent() async throws {
    try await withExclusive {
      guard case .active = manualTransactionState else {
        throw BoutiqueError.invalidTransactionState("commitConcurrent without beginConcurrent")
      }
      do {
        try await connection.executeAsync("COMMIT")
        manualTransactionState = .idle
      } catch let commitError {
        do {
          try await connection.executeAsync("ROLLBACK")
          manualTransactionState = .idle
        } catch let rollbackError {
          manualTransactionState = .poisoned(
            "commit failed: \(commitError); rollback failed: \(rollbackError)"
          )
          throw BoutiqueError.invalidTransactionState(
            "Transaction is poisoned after commit and rollback failures"
          )
        }
        throw commitError
      }
    }
  }

  func rollbackConcurrent() async throws {
    try await withExclusive {
      guard case .active = manualTransactionState else {
        throw BoutiqueError.invalidTransactionState("rollbackConcurrent without beginConcurrent")
      }
      do {
        try await connection.executeAsync("ROLLBACK")
        manualTransactionState = .idle
      } catch {
        manualTransactionState = .poisoned("rollback failed: \(error)")
        throw BoutiqueError.invalidTransactionState(
          "Transaction is poisoned because rollback failed"
        )
      }
    }
  }

  private func withExclusive<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
    while exclusiveDepth > 0 {
      await Task.yield()
    }
    exclusiveDepth += 1
    defer { exclusiveDepth -= 1 }
    return try await body()
  }

  private func rejectIfManualTxn() throws {
    switch manualTransactionState {
    case .idle:
      return
    case .active:
      throw BoutiqueError.transactionInProgress
    case .poisoned(let message):
      throw BoutiqueError.invalidTransactionState(message)
    }
  }
}
