// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "BoutiqueDBiOSConsumer",
  platforms: [.iOS(.v17), .macOS(.v14)],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .target(
      name: "BoutiqueDBiOSConsumer",
      dependencies: [.product(name: "BoutiqueDB", package: "BoutiqueDB-Swift")]
    )
  ]
)
