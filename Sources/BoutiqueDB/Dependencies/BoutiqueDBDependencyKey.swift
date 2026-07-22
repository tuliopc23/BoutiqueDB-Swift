import Dependencies
import Foundation

extension DependencyValues {
  /// Application default ``BoutiqueDB`` (set in `prepareDependencies` at launch).
  ///
  /// ```swift
  /// prepareDependencies {
  ///   $0.boutiqueDB = try await BoutiqueDB.open(url: url, migrations: plan)
  /// }
  /// ```
  public var boutiqueDB: BoutiqueDB {
    get { self[BoutiqueDBKey.self] }
    set { self[BoutiqueDBKey.self] = newValue }
  }
}

private enum BoutiqueDBKey: DependencyKey {
  static var liveValue: BoutiqueDB {
    fatalError(
      """
      Dependency \\.boutiqueDB is not configured.
      Register it at app launch with prepareDependencies { $0.boutiqueDB = … }.
      """
    )
  }

  static var testValue: BoutiqueDB {
    fatalError(
      """
      Override \\.boutiqueDB in withDependencies for tests.
      """
    )
  }
}
