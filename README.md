# AnyDocSwift

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/anydoc-swift/ci.yml?branch=master&event=push&label=CI)](https://github.com/ngutech21/anydoc-swift/actions/workflows/ci.yml)

AnyDocSwift is a macOS Swift package and an intentionally shallow wrapper around
[AnyDoc](https://github.com/firecrawl/anydoc), the Rust document-to-Markdown
conversion library. It does not reimplement AnyDoc's parsers or conversion
logic. Instead, it exposes the pinned AnyDoc engine through a small asynchronous
Swift interface and handles the Swift integration boundary, including binary
packaging, scheduling, cancellation, limits, and typed errors.

The project structure, runtime path, native ownership model, and contributor
workflow are explained in [`docs/spec.md`](docs/spec.md). The Rust bridge and
Swift public interface are implemented and tested against a verified
XCFramework. Its immutable release archive is integrated as a checksum-pinned
SwiftPM binary target, so ordinary package consumers do not need a Rust
toolchain.

## Requirements

- macOS 13 or later on Apple Silicon
- Swift 6.1 or later
- Rust 1.88.0 when rebuilding the native bridge

## Installation

Add AnyDocSwift to your Swift package dependencies and include the
`AnyDocSwift` product in your target:

```swift
dependencies: [
  .package(
    url: "https://github.com/ngutech21/anydoc-swift.git",
    exact: "0.1.2"
  )
],
targets: [
  .target(
    name: "YourTarget",
    dependencies: [
      .product(name: "AnyDocSwift", package: "anydoc-swift")
    ]
  )
]
```

In Xcode, choose **File > Add Package Dependencies**, enter
`https://github.com/ngutech21/anydoc-swift.git`, select version `0.1.2`, and
add the `AnyDocSwift` library to your application target.

SwiftPM downloads the checksum-pinned native artifact automatically. Consumer
applications do not need Rust, Cargo, or another runtime.

## Usage

Conversion uses one actor with a small public interface:

```swift
import AnyDocSwift

let converter = AnyDocConverter()
let markdown = try await converter.markdown(
  from: documentData,
  fileExtension: "docx"
)
```

A complete command-line consumer is available in
[`Examples/AnyDocSwiftExample`](Examples/AnyDocSwiftExample). From the
repository root, run it with a document path:

```sh
cd Examples/AnyDocSwiftExample
swift run AnyDocSwiftExample /path/to/document.docx
```

## Behavior

Each converter runs native calls in FIFO order on its own serial queue; separate
instances may run concurrently. Cancellation before native work starts skips
the call. Once parsing begins, cleanup completes before `CancellationError` is
thrown. The standard limits are 64 MiB of input and 16 MiB of UTF-8 Markdown.
Failures use `AnyDocConversionError`; unknown future engine codes remain
observable through `unrecognizedUpstream`.

Supported hints are `doc`, `docx`, `docm`, `ppt`, `pps`, `pot`, `pptx`, `pptm`,
`ppsx`, `ppsm`, `xls`, `xlsx`, `xlsm`, `xlsb`, `odt`, `ods`, `odp`, `rtf`,
`epub`, `csv`, and `pdf`. Detection examines content first and uses the hint
only as a fallback. CSV requires its extension hint.

Text-based PDFs can be converted. Image-only and scanned PDFs require OCR and
are unsupported. Mixed PDFs may omit pages that require OCR, and successful
conversion does not guarantee that every page was extracted.

Plain `swift build` and `swift test` resolve the published, checksum-pinned
`AnyDocSwiftBridge` artifact without invoking Cargo. The development recipes
also build and verify the local dynamic framework before selecting that
XCFramework through the same private SwiftPM binary-target seam.

Run the same complete validation used by GitHub Actions with:

```sh
just ci
```

The Rust and Swift suites can run independently:

```sh
just ci-rust
just ci-swift
```

Focused build and test entrypoints are also available as `just build-rust`,
`just test-rust`, `just build-swift`, and `just test-swift`. The Swift build
recipe covers debug and release configurations; the Swift test recipe runs
against the same verified local XCFramework.

Build and verify the ignored native release archive with:

```sh
just artifact
```

`just build-artifact` and `just verify-artifact` expose the two steps
separately. The resulting archive is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`; SwiftPM prints its
checksum after both commands. Artifact validation also links a test-only second
Rust static library to prove that both Rust runtimes can coexist in one
consumer process.

Consuming applications do not require Rust or Cargo. SwiftPM downloads and
verifies the released XCFramework through the package manifest.
