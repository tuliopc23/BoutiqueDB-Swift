// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "BoutiqueDBConsumer",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "BoutiqueDBConsumer",
      dependencies: [.product(name: "BoutiqueDB", package: "BoutiqueDB-Swift")]
    )
  ]
)
