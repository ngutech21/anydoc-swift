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
      "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.1.4/AnyDocSwiftBridge.xcframework.zip",
    checksum: "031c5c6d2c318be9ebe1f369469e357d727eef71ff05e6277c8817f1521b967f"
  )

let package = Package(
  name: "AnyDocSwift",
  platforms: [
    .macOS(.v13),
    .iOS(.v15),
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
      dependencies: ["AnyDocSwift"],
      path: "Tests",
      exclude: ["ArtifactSmoke", "PublicConsumerSmoke"],
      sources: ["AnyDocSwiftTests"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
