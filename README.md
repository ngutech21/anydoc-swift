# AnyDocSwift

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/anydoc-swift/ci.yml?branch=master&event=push&label=CI)](https://github.com/ngutech21/anydoc-swift/actions/workflows/ci.yml)

AnyDocSwift converts Word, PowerPoint, Excel, OpenDocument, PDF, EPUB, RTF,
and CSV data into GitHub-Flavored Markdown in macOS Swift applications.
Conversion runs locally and in-process through the Rust
[Firecrawl anydoc](https://github.com/firecrawl/anydoc) engine. Applications
install the package through SwiftPM and do not need Rust, Cargo, or an external
service.

The package intentionally keeps a small asynchronous Swift interface while
handling native packaging, scheduling, cancellation, limits, and typed errors.
It does not reimplement AnyDoc's parsers or conversion logic.

This independent community project is not affiliated with, endorsed by, or maintained by
Firecrawl.

## Requirements

- macOS 13 or later on Apple Silicon
- Swift 6.1 or later

## Installation

Add AnyDocSwift to your Swift package dependencies and include the
`AnyDocSwift` product in your target:

```swift
dependencies: [
  .package(
    url: "https://github.com/ngutech21/anydoc-swift.git",
    exact: "0.1.4"
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
`https://github.com/ngutech21/anydoc-swift.git`, select version `0.1.4`, and
add the `AnyDocSwift` library to your application target.

SwiftPM downloads and verifies the checksum-pinned native artifact
automatically.

## Quick start

Load a document into `Data`, then pass its extension as a format hint:

```swift
import AnyDocSwift
import Foundation

let url = URL(fileURLWithPath: "/path/to/document.docx")
let data = try Data(contentsOf: url)

let converter = AnyDocConverter()
let markdown = try await converter.markdown(
  from: data,
  fileExtension: url.pathExtension
)

print(markdown)
```

A complete command-line consumer is available in
[`Examples/AnyDocSwiftExample`](Examples/AnyDocSwiftExample). Run it from the
repository root with:

```sh
cd Examples/AnyDocSwiftExample
swift run AnyDocSwiftExample /path/to/document.docx
```

## Supported formats

| Format           | Extensions                                                 |
| ---------------- | ---------------------------------------------------------- |
| Word             | `.doc`, `.docx`, `.docm`                                   |
| PowerPoint       | `.ppt`, `.pps`, `.pot`, `.pptx`, `.pptm`, `.ppsx`, `.ppsm` |
| Excel            | `.xls`, `.xlsx`, `.xlsm`, `.xlsb`                          |
| OpenDocument     | `.odt`, `.ods`, `.odp`                                     |
| Rich Text Format | `.rtf`                                                     |
| EPUB             | `.epub`                                                    |
| CSV              | `.csv`                                                     |
| PDF              | `.pdf`                                                     |

Detection examines content first and uses the extension hint only as a
fallback. CSV requires the `csv` hint. The API returns Markdown only; it does
not expose AnyDoc's internal document model or extract embedded assets.

## Behavior and limitations

### Loading and limits

The converter accepts complete in-memory documents. Its standard limits are
64 MiB of input and 16 MiB of UTF-8 Markdown, both measured in bytes.
Applications handling untrusted or very large files should check file size
before loading the complete contents into `Data`.

Configure different limits when creating a converter:

```swift
let converter = AnyDocConverter(
  limits: .init(
    maximumInputBytes: 20 * 1024 * 1024,
    maximumOutputBytes: 5 * 1024 * 1024
  )
)
```

### Concurrency and cancellation

Each converter performs native calls in FIFO order on its own serial queue.
Separate converter instances may convert concurrently without blocking the
main actor.

Cancellation before native work starts skips the call. An active native parser
call cannot be interrupted; conversion and cleanup finish before the awaiting
task receives `CancellationError`.

### Errors

Conversion failures use `AnyDocConversionError`, including invalid or
oversized input, oversized output, unsupported, malformed, encrypted, missing,
resource-limited, and I/O cases. Unknown future engine codes remain observable
through `unrecognizedUpstream(code:message:)`. Task cancellation uses Swift's
`CancellationError` instead.

### PDFs and unsupported features

Text-based PDFs can be converted. Image-only and scanned PDFs require OCR and
are unsupported. Mixed PDFs may omit pages that require OCR, so successful
conversion does not guarantee that every page was extracted.

The package currently does not provide streaming output, progress reporting,
active-parser interruption, file-path or security-scoped URL handling,
persistence, caching, or embedded asset extraction.

## Architecture and contributing

See the [architecture guide](docs/architecture.md) for the project structure,
runtime path, ownership model, and binary distribution design. See
[CONTRIBUTING](CONTRIBUTING.md) for local setup, validation commands, native
artifact generation, and dependency changes.

Ordinary `swift build` and `swift test` commands resolve the released
XCFramework without invoking Cargo.

## Licensing

AnyDocSwift is distributed under the [MIT License](LICENSE). The native
bridge incorporates third-party Rust crates whose exact licenses and
attribution notices are recorded in
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).

The checksum-pinned `binary-0.1.4` archive embeds both files in the signed
framework's `Resources` directory. Distributors must retain those resources
when copying or embedding the framework. Notice maintenance is documented in
[CONTRIBUTING](CONTRIBUTING.md#dependency-and-abi-changes).
