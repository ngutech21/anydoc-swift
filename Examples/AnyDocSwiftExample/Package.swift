// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AnyDocSwiftExample",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(
      url: "https://github.com/ngutech21/anydoc-swift.git",
      exact: "0.2.0"
    )
  ],
  targets: [
    .executableTarget(
      name: "AnyDocSwiftExample",
      dependencies: [
        .product(
          name: "AnyDocSwift",
          package: "anydoc-swift"
        )
      ]
    )
  ]
)
