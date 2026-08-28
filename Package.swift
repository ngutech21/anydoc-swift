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
        "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.1.2/AnyDocSwiftBridge.xcframework.zip",
      checksum: "b24ec29d9b468b1ee2cbae6626a0bc8ca0d8136e6ea3aac4eb148d16721f0b76"
    ),
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
