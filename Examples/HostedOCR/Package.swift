// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "HostedOCRExample",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(
      url: "https://github.com/ngutech21/anydoc-swift.git",
      exact: "0.2.2"
    )
  ],
  targets: [
    .executableTarget(
      name: "HostedOCRExample",
      dependencies: [.product(name: "AnyDocSwift", package: "anydoc-swift")]
    )
  ]
)
