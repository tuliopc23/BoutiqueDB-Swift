import Foundation
import StructuredQueriesCore

/// A dense 32-bit float embedding for Turso `vector32(...)` / distance functions.
///
/// First-class Turso advantage over stock SQLite: store embeddings and run
/// on-device similarity search without a separate vector DB.
public struct Vector32: Sendable, Hashable, Codable, RawRepresentable {
  public var values: [Float]

  public init(_ values: [Float]) {
    self.values = values
  }

  public init(arrayLiteral elements: Float...) {
    self.values = elements
  }

  /// JSON-like literal accepted by Turso `vector32('[...]')`.
  public var jsonLiteral: String {
    "[" + values.map { String($0) }.joined(separator: ",") + "]"
  }

  public var rawValue: String { jsonLiteral }

  public init?(rawValue: String) {
    guard let parsed = Self.parse(rawValue) else { return nil }
    self.values = parsed
  }

  private static func parse(_ text: String) -> [Float]? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
    let inner = trimmed.dropFirst().dropLast()
    if inner.isEmpty { return [] }
    let parts = inner.split(separator: ",")
    var out: [Float] = []
    out.reserveCapacity(parts.count)
    for part in parts {
      guard let f = Float(part.trimmingCharacters(in: .whitespaces)) else { return nil }
      out.append(f)
    }
    return out
  }
}

extension Vector32: QueryBindable {
  public var queryBinding: QueryBinding { .text(jsonLiteral) }
}

/// Sparse vector payload for Turso `vector32_sparse(...)`.
public struct Vector32Sparse: Sendable, Hashable, Codable, RawRepresentable {
  public var entries: [Int: Float]

  public init(_ entries: [Int: Float]) {
    self.entries = entries
  }

  public var jsonLiteral: String {
    let parts = entries.keys.sorted().map { i in
      "[\(i),\(entries[i]!)]"
    }
    return "[" + parts.joined(separator: ",") + "]"
  }

  public var rawValue: String { jsonLiteral }

  /// Parses `[[index,value],...]` JSON matching ``jsonLiteral``.
  public init?(rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
    guard let data = trimmed.data(using: .utf8),
      let array = try? JSONSerialization.jsonObject(with: data) as? [[Any]]
    else { return nil }
    var parsed: [Int: Float] = [:]
    for pair in array {
      guard pair.count >= 2 else { return nil }
      let index: Int?
      if let i = pair[0] as? Int {
        index = i
      } else if let d = pair[0] as? Double {
        index = Int(d)
      } else if let n = pair[0] as? NSNumber {
        index = n.intValue
      } else {
        index = nil
      }
      let value: Float?
      if let f = pair[1] as? Float {
        value = f
      } else if let d = pair[1] as? Double {
        value = Float(d)
      } else if let n = pair[1] as? NSNumber {
        value = n.floatValue
      } else {
        value = nil
      }
      guard let index, let value else { return nil }
      parsed[index] = value
    }
    self.entries = parsed
  }
}

extension Vector32Sparse: QueryBindable {
  public var queryBinding: QueryBinding { .text(jsonLiteral) }
}
