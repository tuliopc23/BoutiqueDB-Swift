import Foundation
import StructuredQueriesCore
import TursoKit

struct TursoQueryDecoder: QueryDecoder {
  let statement: TursoStatement
  var currentIndex: Int = 0

  mutating func next() {
    currentIndex = 0
  }

  mutating func decode(_ columnType: [UInt8].Type) throws -> [UInt8]? {
    defer { currentIndex += 1 }
    let value = statement.value(at: currentIndex)
    guard let data = value.dataValue else { return nil }
    return Array(data)
  }

  mutating func decode(_ columnType: Bool.Type) throws -> Bool? {
    try decode(Int64.self).map { $0 != 0 }
  }

  mutating func decode(_ columnType: Date.Type) throws -> Date? {
    guard let string = try decode(String.self) else { return nil }
    return TursoDateFormatting.date(from: string)
  }

  mutating func decode(_ columnType: Double.Type) throws -> Double? {
    defer { currentIndex += 1 }
    return statement.value(at: currentIndex).doubleValue
  }

  mutating func decode(_ columnType: Int.Type) throws -> Int? {
    try decode(Int64.self).map(Int.init)
  }

  mutating func decode(_ columnType: Int64.Type) throws -> Int64? {
    defer { currentIndex += 1 }
    return statement.value(at: currentIndex).int64Value
  }

  mutating func decode(_ columnType: String.Type) throws -> String? {
    defer { currentIndex += 1 }
    return statement.value(at: currentIndex).stringValue
  }

  mutating func decode(_ columnType: UInt64.Type) throws -> UInt64? {
    guard let n = try decode(Int64.self) else { return nil }
    guard n >= 0 else {
      throw TursoError(code: -1, message: "UInt64 overflow decoding \(n)")
    }
    return UInt64(n)
  }

  mutating func decode(_ columnType: UUID.Type) throws -> UUID? {
    guard let string = try decode(String.self) else { return nil }
    return UUID(uuidString: string)
  }
}

enum TursoDateFormatting {
  static func string(from date: Date) -> String {
    date.formatted(.iso8601.dateTimeSeparator(.standard).time(includingFractionalSeconds: true))
  }

  static func date(from string: String) -> Date? {
    if let date = try? Date(string, strategy: .iso8601) {
      return date
    }
    if let seconds = Double(string) {
      return Date(timeIntervalSince1970: seconds)
    }
    return nil
  }
}
