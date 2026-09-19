// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "HostedOCRExample",
  platforms: [.macOS(.v13)],
  // Pending release: compile against the candidate checkout.
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "HostedOCRExample",
      dependencies: [.product(name: "AnyDocSwift", package: "anydoc-swift")]
    )
  ]
)
