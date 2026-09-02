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
        "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.0/AnyDocSwiftBridge.xcframework.zip",
      checksum: "2feaf71ce75dc101ba3c07f065950fb95da72f99c1de1e891d88611814165576"
    )
  let bridgeLinkerSettings: [LinkerSetting] = []
#elseif os(Linux) && (arch(x86_64) || arch(arm64))
  let bridgeTarget: Target
  if useLocallyBuiltBridge {
    bridgeTarget = .binaryTarget(
      name: "AnyDocSwiftBridge",
      path: ".build/artifact/verified/AnyDocSwiftBridge.artifactbundle"
    )
  } else {
    #if arch(x86_64)
      bridgeTarget = .binaryTarget(
        name: "AnyDocSwiftBridge",
        url:
          "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.0/AnyDocSwiftBridge-x86_64-unknown-linux-gnu.artifactbundle.zip",
        checksum: "d9311beacac609e99404e15dfedd3ea0defaa2d48a83cda38f5220067104a3a6"
      )
    #else
      bridgeTarget = .binaryTarget(
        name: "AnyDocSwiftBridge",
        url:
          "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.0/AnyDocSwiftBridge-aarch64-unknown-linux-gnu.artifactbundle.zip",
        checksum: "aafa2ef2e5b20ae5ca4d2ba40f68bf603c8c8dd0f783f918ff816eeac013597f"
      )
    #endif
  }
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
