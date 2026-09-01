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
      "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.1.5/AnyDocSwiftBridge.xcframework.zip",
    checksum: "75b006807443a1195ae9a8ee37b504e7fe336cfe06d29e2bb4a6ca563bece98d"
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
