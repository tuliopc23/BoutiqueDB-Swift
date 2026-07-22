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
  private var manualConcurrentTxn = false
  /// Non-zero while a read/write is in progress (blocks re-entrant actor work).
  private var exclusiveDepth = 0

  init(connection: TursoConnection) {
    self.connection = connection
  }

  func read<T: Sendable>(
    _ body: @Sendable (BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      if connection.usesAsyncIO {
        return try await connection.readAsync { @Sendable in
          let conn = BoutiqueDBConnection(connection)
          return try body(conn)
        }
      } else {
        let conn = BoutiqueDBConnection(connection)
        return try connection.read {
          try body(conn)
        }
      }
    }
  }

  func write<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      if connection.usesAsyncIO {
        return try await connection.writeAsync { @Sendable in
          var conn = BoutiqueDBConnection(connection)
          return try body(&conn)
        }
      } else {
        var conn = BoutiqueDBConnection(connection)
        return try connection.write {
          try body(&conn)
        }
      }
    }
  }

  func transaction<T: Sendable>(
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await write(body)
  }

  func writeConcurrent<T: Sendable>(
    maxAttempts: Int,
    baseDelayNanoseconds: UInt64,
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      var attempt = 0
      var delay = baseDelayNanoseconds
      while true {
        attempt += 1
        do {
          if connection.usesAsyncIO {
            return try await connection.writeConcurrentAsync { @Sendable in
              var conn = BoutiqueDBConnection(connection)
              return try body(&conn)
            }
          } else {
            var conn = BoutiqueDBConnection(connection)
            return try connection.writeConcurrent {
              try body(&conn)
            }
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
    _ body: @Sendable (inout BoutiqueDBConnection) throws -> T
  ) async throws -> T {
    try await withExclusive {
      try rejectIfManualTxn()
      var attempt = 0
      var delay = baseDelayNanoseconds
      while true {
        attempt += 1
        do {
          if connection.usesAsyncIO {
            return try await connection.writeAsync { @Sendable in
              var conn = BoutiqueDBConnection(connection)
              return try body(&conn)
            }
          } else {
            var conn = BoutiqueDBConnection(connection)
            return try connection.write {
              try body(&conn)
            }
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
      if manualConcurrentTxn {
        throw BoutiqueError.transactionInProgress
      }
      if connection.usesAsyncIO {
        try await connection.executeAsync("BEGIN CONCURRENT")
      } else {
        try connection.execute("BEGIN CONCURRENT")
      }
      manualConcurrentTxn = true
    }
  }

  func commitConcurrent() async throws {
    try await withExclusive {
      guard manualConcurrentTxn else {
        throw BoutiqueError.invalidTransactionState("commitConcurrent without beginConcurrent")
      }
      do {
        if connection.usesAsyncIO {
          try await connection.executeAsync("COMMIT")
        } else {
          try connection.execute("COMMIT")
        }
        manualConcurrentTxn = false
      } catch {
        manualConcurrentTxn = false
        throw error
      }
    }
  }

  func rollbackConcurrent() async throws {
    try await withExclusive {
      guard manualConcurrentTxn else {
        throw BoutiqueError.invalidTransactionState("rollbackConcurrent without beginConcurrent")
      }
      do {
        if connection.usesAsyncIO {
          try await connection.executeAsync("ROLLBACK")
        } else {
          try connection.execute("ROLLBACK")
        }
        manualConcurrentTxn = false
      } catch {
        manualConcurrentTxn = false
        throw error
      }
    }
  }

  private func withExclusive<T: Sendable>(_ body: () async throws -> T) async throws -> T {
    while exclusiveDepth > 0 {
      await Task.yield()
    }
    exclusiveDepth += 1
    defer { exclusiveDepth -= 1 }
    return try await body()
  }

  private func rejectIfManualTxn() throws {
    if manualConcurrentTxn {
      throw BoutiqueError.transactionInProgress
    }
  }
}
