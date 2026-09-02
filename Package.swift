// swift-tools-version: 6.2

import PackageDescription

let useLocallyBuiltBridge =
  Context.environment["ANYDOC_SWIFT_USE_LOCAL_BRIDGE"] == "1"

#if os(macOS) && arch(arm64)
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
  let bridgeLinkerSettings: [LinkerSetting] = []
#elseif os(Linux) && (arch(x86_64) || arch(arm64))
  guard useLocallyBuiltBridge else {
    fatalError(
      "Linux artifact support is staged but not published. "
        + "Build the native artifact and set ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1, "
        + "or use a package release that pins binary-0.2.0."
    )
  }

  let bridgeTarget: Target = .binaryTarget(
    name: "AnyDocSwiftBridge",
    path: ".build/artifact/verified/AnyDocSwiftBridge.artifactbundle"
  )
  // Mirrors the non-default entries in Native/linux/native-static-libs.txt.
  let bridgeLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("rt", .when(platforms: [.linux])),
    .linkedLibrary("util", .when(platforms: [.linux])),
  ]
#else
  fatalError(
    "AnyDocSwift supports only macOS 13+ on arm64 and GNU/Linux on x86_64 or arm64."
  )
#endif

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
      dependencies: ["AnyDocSwiftBridge"],
      linkerSettings: bridgeLinkerSettings
    ),
    bridgeTarget,
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"]
    ),
  ]
)
