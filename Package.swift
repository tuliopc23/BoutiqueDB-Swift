// swift-tools-version: 6.1
import PackageDescription

let tursoLibDir = Context.packageDirectory + "/Vendor/turso/lib"

let package = Package(
  name: "TursoCloudKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "TursoKit", targets: ["TursoKit"]),
    .library(name: "StructuredQueriesTurso", targets: ["StructuredQueriesTurso"]),
    .library(name: "TursoCKSync", targets: ["TursoCKSync"]),
    .library(name: "TursoObservation", targets: ["TursoObservation"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.33.0"),
  ],
  targets: [
    .target(
      name: "CTursoSQLite3",
      path: "Sources/CTursoSQLite3",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("CoreFoundation"),
        .linkedFramework("Security"),
        .linkedFramework("SystemConfiguration"),
        .linkedLibrary("c++"),
        .unsafeFlags([
          "-L\(tursoLibDir)",
          "-lturso_sqlite3",
        ]),
      ]
    ),
    .target(
      name: "TursoKit",
      dependencies: ["CTursoSQLite3"]
    ),
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
      dependencies: [
        "TursoKit",
        "StructuredQueriesTurso",
      ]
    ),
    .target(
      name: "TursoObservation",
      dependencies: [
        "TursoKit",
        "StructuredQueriesTurso",
      ]
    ),
    .testTarget(
      name: "TursoKitTests",
      dependencies: ["TursoKit", "StructuredQueriesTurso"]
    ),
    .testTarget(
      name: "TursoCKSyncTests",
      dependencies: [
        "TursoCKSync",
        "TursoKit",
        "StructuredQueriesTurso",
        "TursoObservation",
      ]
    ),
  ]
)
