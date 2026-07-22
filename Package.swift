// swift-tools-version: 6.1
import CompilerPluginSupport
import Foundation
import PackageDescription

// Turso engine: official sdk-kit, binary xcframework (no unsafeFlags).
//
// Distribution (SPI / consumers):
//   GitHub Release asset TursoSDK.xcframework.zip + checksum below.
// Local maintainer (before/without network release):
//   ./Scripts/build-turso-sdk-xcframework.sh
//   BOUTIQUE_LOCAL_TURSO_SDK=1 swift test

let tursoSDKVersion = "0.2.0"
let tursoSDKChecksum = "78f162a2763cdd843c6860652b667e53c9c257ed9f1bb0e64830a10650432fb2"
// Release tag is `v0.2.0` (release.yml); asset path must include the `v` prefix.
let tursoSDKURL =
  "https://github.com/tuliopc23/BoutiqueDB-Swift/releases/download/v\(tursoSDKVersion)/TursoSDK.xcframework.zip"

let forceLocal = ProcessInfo.processInfo.environment["BOUTIQUE_LOCAL_TURSO_SDK"] == "1"
let localXCFramework = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .appendingPathComponent("Vendor/TursoSDK.xcframework")
  .path
let useLocalTursoSDK = forceLocal || FileManager.default.fileExists(atPath: localXCFramework)

var packageTargets: [Target] = [
  useLocalTursoSDK
    ? .binaryTarget(name: "TursoSDK", path: "Vendor/TursoSDK.xcframework")
    : .binaryTarget(name: "TursoSDK", url: tursoSDKURL, checksum: tursoSDKChecksum),
  .target(
    name: "CTursoSDK",
    dependencies: ["TursoSDK"],
    path: "Sources/CTursoSDK",
    publicHeadersPath: "include",
    linkerSettings: [
      .linkedFramework("CoreFoundation"),
      .linkedFramework("Security"),
      .linkedFramework("SystemConfiguration"),
      .linkedLibrary("c++"),
    ]
  ),
  .target(name: "TursoKit", dependencies: ["CTursoSDK"]),
  .target(
    name: "StructuredQueriesTurso",
    dependencies: [
      "TursoKit",
      .product(name: "StructuredQueries", package: "swift-structured-queries"),
      .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
    ]
  ),
  .target(
    name: "TursoCKSync",
    dependencies: ["TursoKit", "StructuredQueriesTurso"]
  ),
  .target(
    name: "TursoObservation",
    dependencies: ["TursoKit", "StructuredQueriesTurso"]
  ),
  .macro(
    name: "BoutiqueDBMacros",
    dependencies: [
      .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    ]
  ),
  .testTarget(
    name: "TursoKitTests",
    dependencies: ["TursoKit", "StructuredQueriesTurso"]
  ),
  .testTarget(
    name: "TursoCKSyncTests",
    dependencies: [
      "TursoCKSync", "TursoKit", "StructuredQueriesTurso", "TursoObservation",
    ]
  ),
  .testTarget(
    name: "BoutiqueDBTests",
    dependencies: [
      "BoutiqueDB",
      .product(name: "StructuredQueries", package: "swift-structured-queries"),
      .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ]
  ),
  .testTarget(
    name: "BoutiqueDBMacrosTests",
    dependencies: [
      "BoutiqueDBMacros",
      .product(name: "MacroTesting", package: "swift-macro-testing"),
      .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    ]
  ),
  .target(
    name: "BoutiqueDB",
    dependencies: [
      "TursoKit",
      "StructuredQueriesTurso",
      "TursoCKSync",
      "TursoObservation",
      "BoutiqueDBMacros",
      .product(name: "Dependencies", package: "swift-dependencies"),
      .product(name: "Perception", package: "swift-perception"),
    ]
  ),
]

let package = Package(
  name: "BoutiqueDB",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "BoutiqueDB", targets: ["BoutiqueDB"]),
    .library(name: "TursoKit", targets: ["TursoKit"]),
    .library(name: "StructuredQueriesTurso", targets: ["StructuredQueriesTurso"]),
    .library(name: "TursoCKSync", targets: ["TursoCKSync"]),
    .library(name: "TursoObservation", targets: ["TursoObservation"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.33.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"605.0.0"),
  ],
  targets: packageTargets
)
