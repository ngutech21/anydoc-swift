// swift-tools-version: 6.2

import PackageDescription

guard let anyDocSwiftRoot = Context.environment["ANYDOC_SWIFT_PACKAGE_ROOT"] else {
  fatalError("ANYDOC_SWIFT_PACKAGE_ROOT is required")
}

let package = Package(
  name: "AnyDocSwiftMemoryProbe",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "AnyDocSwiftMemoryProbe",
      targets: ["AnyDocSwiftMemoryProbe"]
    )
  ],
  dependencies: [
    .package(name: "AnyDocSwift", path: anyDocSwiftRoot)
  ],
  targets: [
    .executableTarget(
      name: "AnyDocSwiftMemoryProbe",
      dependencies: [
        .product(name: "AnyDocSwift", package: "AnyDocSwift")
      ]
    )
  ]
)
