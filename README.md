# AnyDocSwift

AnyDocSwift is a macOS Swift package for converting supported document bytes
to GitHub-Flavored Markdown through the pinned Rust `anydoc` engine.

The implementation contract and acceptance criteria live in
[`docs/spec.md`](docs/spec.md). The repository is currently at the native
artifact stage: the Rust bridge pins AnyDoc to an exact crates.io release
and proves real byte-to-Markdown conversion. Its C ABI and Rust-owned result
lifetime are implemented and tested. The Justfile builds and verifies the
release XCFramework locally using the standard Cargo, Xcode, and SwiftPM tools;
publishing that archive, wiring the remote binary target, and implementing the
Swift public interface remain later milestones.

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

Build and verify the ignored native release archive with:

```sh
just artifact
```

`just build-artifact` and `just verify-artifact` expose the two steps
separately. The resulting archive is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`; SwiftPM prints its
checksum after both commands.

Consuming applications will not require Rust or Cargo once the release
XCFramework has been published and added as a checksum-pinned remote binary
target.
