// swift-tools-version: 6.1

import PackageDescription

let useLocallyBuiltBridge =
  Context.environment["ANYDOC_SWIFT_USE_LOCAL_BRIDGE"] == "1"

let bridgeTarget: Target =
  useLocallyBuiltBridge
  ? .binaryTarget(
    name: "AnyDocSwiftBridge",
    path: ".build/artifact/verified/AnyDocSwiftBridge.xcframework"
  )
  : .binaryTarget(
    name: "AnyDocSwiftBridge",
    url:
      "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.1.3/AnyDocSwiftBridge.xcframework.zip",
    checksum: "c706e21d73c93808e259c4778fb694f40dd84b0aa59c5f756c45567f585d993a"
  )

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
      dependencies: ["AnyDocSwiftBridge"]
    ),
    bridgeTarget,
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
