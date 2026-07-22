import CloudKit
import Foundation
import TursoKit

enum RecordMapper {
  static func makeRecord(
    table: SyncedTable,
    rowPK: String,
    row: [String: TursoValue],
    zoneID: CKRecordZone.ID,
    systemFields: Data?
  ) throws -> CKRecord {
    let recordID = CKRecord.ID(
      recordName: try table.recordName(forRowPK: rowPK),
      zoneID: zoneID
    )
    let record: CKRecord
    if let systemFields, let decoded = decodeSystemFields(systemFields) {
      record = decoded
    } else {
      record = CKRecord(recordType: table.recordType, recordID: recordID)
    }

    for column in table.columns {
      record[column] = ckValue(from: row[column] ?? .null)
    }
    // Always mirror PK for debugging / inbound rebuilds.
    record[table.primaryKeyColumn] = rowPK as CKRecordValue
    return record
  }

  static func encodeSystemFields(_ record: CKRecord) -> Data {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    coder.finishEncoding()
    return coder.encodedData
  }

  static func decodeSystemFields(_ data: Data) -> CKRecord? {
    do {
      let coder = try NSKeyedUnarchiver(forReadingFrom: data)
      coder.requiresSecureCoding = true
      let record = CKRecord(coder: coder)
      coder.finishDecoding()
      return record
    } catch {
      return nil
    }
  }

  static func ckValue(from value: TursoValue) -> CKRecordValue? {
    switch value {
    case .null:
      return nil
    case .integer(let v):
      return NSNumber(value: v)
    case .double(let v):
      return NSNumber(value: v)
    case .text(let s):
      return s as NSString
    case .blob(let data):
      return data as NSData
    }
  }

  static func tursoValue(from ckValue: CKRecordValue?, field: String) throws -> TursoValue {
    guard let ckValue else { return .null }
    switch ckValue {
    case let number as NSNumber:
      // Prefer integer when the number is integral.
      let double = number.doubleValue
      if double.rounded() == double, double >= Double(Int64.min), double <= Double(Int64.max) {
        return .integer(number.int64Value)
      }
      return .double(double)
    case let string as NSString:
      return .text(string as String)
    case let data as NSData:
      return .blob(data as Data)
    case let date as NSDate:
      return .text(
        (date as Date).formatted(
          .iso8601.dateTimeSeparator(.standard).time(includingFractionalSeconds: true)
        )
      )
    case let asset as CKAsset:
      guard let url = asset.fileURL else {
        throw TursoCKSyncError.assetReadFailed(field: field, message: "missing file URL")
      }
      do {
        return .blob(try Data(contentsOf: url))
      } catch {
        throw TursoCKSyncError.assetReadFailed(
          field: field,
          message: String(describing: error)
        )
      }
    default:
      throw TursoCKSyncError.unsupportedRemoteValue(
        field: field,
        type: String(reflecting: type(of: ckValue))
      )
    }
  }

  static func rowDictionary(from record: CKRecord, table: SyncedTable) throws
    -> [String: TursoValue]
  {
    var row: [String: TursoValue] = [:]
    if let pk = RecordIdentity.rowPK(table: table.name, recordName: record.recordID.recordName) {
      row[table.primaryKeyColumn] = .text(pk)
    } else if let pk = record[table.primaryKeyColumn] {
      row[table.primaryKeyColumn] = try tursoValue(from: pk, field: table.primaryKeyColumn)
    }
    for column in table.columns {
      row[column] = try tursoValue(from: record[column], field: column)
    }
    return row
  }
}
