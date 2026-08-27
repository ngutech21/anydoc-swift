// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "AnyDocSwift",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "AnyDocSwift",
      targets: ["AnyDocSwift"]
    )
  ],
  targets: [
    // Add the local AnyDocSwiftBridge binary target and this target's
    // dependency together once the first real XCFramework is verified.
    .target(name: "AnyDocSwift"),
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
