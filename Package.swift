// swift-tools-version: 6.1

import PackageDescription

let useLocallyBuiltBridge =
  Context.environment["ANYDOC_SWIFT_USE_LOCAL_BRIDGE"] == "1"

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
    .target(
      name: "AnyDocSwift",
      dependencies: useLocallyBuiltBridge ? [] : ["AnyDocSwiftBridge"],
      linkerSettings: [
        .linkedFramework("CoreFoundation"),
        .linkedLibrary("iconv"),
      ]
    ),
    .binaryTarget(
      name: "AnyDocSwiftBridge",
      url:
        "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.1.1/AnyDocSwiftBridge.xcframework.zip",
      checksum: "7877370f0ffe12181cc9e7605698f34895cc195020d0fcb8e82fa4f1e970658b"
    ),
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
