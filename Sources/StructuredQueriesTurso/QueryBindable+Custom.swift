import Foundation
import StructuredQueriesCore

/// Helpers for mapping domain enums into Turso/SQLite columns.
///
/// Prefer:
/// ```swift
/// enum Status: String, QueryBindable { case open, closed }
/// ```
/// StructuredQueries already provides `QueryBindable` for many primitives; for
/// custom raw enums, conform explicitly:
/// ```swift
/// extension Status: QueryBindable {}
/// ```
/// when `RawValue` is `String`/`Int` and the synthesized path is available, or
/// implement `queryBinding` / `queryOutput` manually.

/// Example pattern for string-backed domain enums.
///
/// Decoding invalid stored strings **throws** (via StructuredQueries
/// `RawRepresentable` + `QueryDecodable`); it does not abort the process.
///
/// Prefer:
/// ```swift
/// enum Status: String, StringQueryBindable, Sendable { case open, closed }
/// ```
public protocol StringQueryBindable: RawRepresentable, QueryBindable
where RawValue == String, QueryValue == Self {
}

extension StringQueryBindable {
  public var queryBinding: QueryBinding { .text(rawValue) }

  /// Convenience for known-good raw values (e.g. round-trip of ``rawValue``).
  /// Prefer `Self(rawValue:)` when the string may be invalid.
  public init(queryOutput: Self) {
    self = queryOutput
  }

  public var queryOutput: Self { self }
}
