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
    // Add the remote AnyDocSwiftBridge binary target and this target's
    // dependency together once its immutable release archive is verified.
    .target(name: "AnyDocSwift"),
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
