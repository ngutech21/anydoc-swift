// swift-tools-version: 6.2

import PackageDescription

let useLocallyBuiltBridge =
  Context.environment["ANYDOC_SWIFT_USE_LOCAL_BRIDGE"] == "1"

// SwiftPM evaluates this manifest for the host process, which may run under
// Rosetta even when the build targets arm64. The macOS binary is arm64-only.
#if os(macOS)
  let bridgeTarget: Target =
    useLocallyBuiltBridge
    ? .binaryTarget(
      name: "AnyDocSwiftBridge",
      path: ".build/artifact/verified/AnyDocSwiftBridge.xcframework"
    )
    : .binaryTarget(
      name: "AnyDocSwiftBridge",
      url:
        "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.1/AnyDocSwiftBridge.xcframework.zip",
      checksum: "ec81289086e0ef7f23212172433ea184b8f634e55f757a825210e2a91fd4f6f6"
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
          "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.1/AnyDocSwiftBridge-x86_64-unknown-linux-gnu.artifactbundle.zip",
        checksum: "520d353696ee28d63d7406be053af56a388b894676f3c493cd2b37b4df9260ad"
      )
    #else
      bridgeTarget = .binaryTarget(
        name: "AnyDocSwiftBridge",
        url:
          "https://github.com/ngutech21/anydoc-swift/releases/download/binary-0.2.1/AnyDocSwiftBridge-aarch64-unknown-linux-gnu.artifactbundle.zip",
        checksum: "f8b35c5b20c32535ad2eb055a94cc7fb965e9b517461f3be627f065d247b5358"
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

let swiftSettings: [SwiftSetting] = [
  .treatAllWarnings(as: .error),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
  name: "AnyDocSwift",
  platforms: [
    .macOS(.v13),
    .iOS(.v17),
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
      swiftSettings: swiftSettings,
      linkerSettings: bridgeLinkerSettings
    ),
    bridgeTarget,
    .testTarget(
      name: "AnyDocSwiftTests",
      dependencies: ["AnyDocSwift"],
      path: "Tests",
      exclude: ["ArtifactSmoke", "LinuxRustComposition", "MemoryProbe", "PublicConsumerSmoke"],
      sources: ["AnyDocSwiftTests"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ]
)
