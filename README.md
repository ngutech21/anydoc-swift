# AnyDocSwift

AnyDocSwift is a macOS Swift package for converting supported document bytes
to GitHub-Flavored Markdown through the pinned Rust `anydoc` engine.

The implementation contract and acceptance criteria live in
[`docs/spec.md`](docs/spec.md). The repository is currently at the package
bootstrap stage: the Swift library and test targets are usable, while the Rust
bridge and verified XCFramework have not been implemented yet.

## Requirements

- macOS 13 or later on Apple Silicon
- Swift 6.1 or later
- Rust 1.88.0 when rebuilding the native bridge

## Development

Open `Package.swift` directly in Xcode or use SwiftPM from the repository root:

```sh
swift build
swift test
```

Consuming applications will not require Rust or Cargo once the release
XCFramework is available.
