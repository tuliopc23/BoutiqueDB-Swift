import Foundation
import StructuredQueriesCore

// MARK: - Vector distance (Turso-only)

/// Cosine distance between two vector expressions / values.
public func vectorDistanceCos(
  _ lhs: some QueryExpression,
  _ rhs: some QueryExpression
) -> some QueryExpression<Double> {
  SQLQueryExpression("vector_distance_cos(\(lhs), \(rhs))", as: Double.self)
}

public func vectorDistanceCos(
  _ lhs: some QueryExpression,
  _ rhs: Vector32
) -> some QueryExpression<Double> {
  SQLQueryExpression(
    "vector_distance_cos(\(lhs), vector32(\(quote: rhs.jsonLiteral, delimiter: .text)))",
    as: Double.self
  )
}

public func vectorDistanceL2(
  _ lhs: some QueryExpression,
  _ rhs: some QueryExpression
) -> some QueryExpression<Double> {
  SQLQueryExpression("vector_distance_l2(\(lhs), \(rhs))", as: Double.self)
}

public func vectorDistanceL2(
  _ lhs: some QueryExpression,
  _ rhs: Vector32
) -> some QueryExpression<Double> {
  SQLQueryExpression(
    "vector_distance_l2(\(lhs), vector32(\(quote: rhs.jsonLiteral, delimiter: .text)))",
    as: Double.self
  )
}

public func vectorDistanceDot(
  _ lhs: some QueryExpression,
  _ rhs: some QueryExpression
) -> some QueryExpression<Double> {
  SQLQueryExpression("vector_distance_dot(\(lhs), \(rhs))", as: Double.self)
}

public func vectorDistanceDot(
  _ lhs: some QueryExpression,
  _ rhs: Vector32
) -> some QueryExpression<Double> {
  SQLQueryExpression(
    "vector_distance_dot(\(lhs), vector32(\(quote: rhs.jsonLiteral, delimiter: .text)))",
    as: Double.self
  )
}

public func vectorDistanceJaccard(
  _ lhs: some QueryExpression,
  _ rhs: some QueryExpression
) -> some QueryExpression<Double> {
  SQLQueryExpression("vector_distance_jaccard(\(lhs), \(rhs))", as: Double.self)
}

public func vectorDistanceJaccard(
  _ lhs: some QueryExpression,
  _ rhs: Vector32
) -> some QueryExpression<Double> {
  SQLQueryExpression(
    "vector_distance_jaccard(\(lhs), vector32(\(quote: rhs.jsonLiteral, delimiter: .text)))",
    as: Double.self
  )
}

// MARK: - Full-text search (Turso Tantivy)

extension QueryExpression where QueryValue == String {
  /// Turso `fts_match` predicate for Tantivy FTS indexes.
  public func match(_ query: String) -> some QueryExpression<Bool> {
    SQLQueryExpression("fts_match(\(self), \(bind: query))", as: Bool.self)
  }

  /// Turso `fts_score` BM25 relevance score.
  public func score(_ query: String) -> some QueryExpression<Double> {
    SQLQueryExpression("fts_score(\(self), \(bind: query))", as: Double.self)
  }

  /// Turso `fts_highlight` with before/after tags.
  public func highlight(
    query: String,
    before: String = "<b>",
    after: String = "</b>"
  ) -> some QueryExpression<String> {
    SQLQueryExpression(
      "fts_highlight(\(self), \(bind: before), \(bind: after), \(bind: query))",
      as: String.self
    )
  }

  /// Turso `regexp_like` (regexp extension).
  public func regexp(_ pattern: String) -> some QueryExpression<Bool> {
    SQLQueryExpression("regexp_like(\(self), \(bind: pattern))", as: Bool.self)
  }
}

// MARK: - Scalar extensions

/// SQL `uuid4()` via Turso UUID extension.
public enum TursoSQL {
  /// Random UUID v4 expression (`uuid4()` / `uuid4_str()`).
  public static func uuid4() -> some QueryExpression<String> {
    SQLQueryExpression("uuid4_str()", as: String.self)
  }

  public static func percentile(
    _ column: some QueryExpression,
    _ p: Double
  ) -> some QueryExpression<Double> {
    SQLQueryExpression("percentile(\(column), \(raw: p))", as: Double.self)
  }
}

extension UUID {
  /// Use as a SQL expression generating a new UUID v4 in the engine.
  public static var sqlV4: some QueryExpression<String> {
    TursoSQL.uuid4()
  }
}
