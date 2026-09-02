# AnyDocSwift

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/anydoc-swift/ci.yml?branch=master&event=push&label=CI)](https://github.com/ngutech21/anydoc-swift/actions/workflows/ci.yml)

AnyDocSwift 0.2.0 converts Word, PowerPoint, Excel, OpenDocument, PDF, EPUB, RTF,
and CSV data to GitHub-Flavored Markdown in Swift applications. It also
exposes AnyDoc's complete read-only document graph, including
styles, links, canonical tables, notes, and embedded asset bytes.

Conversion runs locally and in-process through the Rust
[Firecrawl anydoc](https://github.com/firecrawl/anydoc) engine. Applications
install the package through SwiftPM and do not need Rust, Cargo, or an external
service. This independent community project is not affiliated with, endorsed
by, or maintained by Firecrawl.

## Requirements and release status

- Swift 6.2 or later
- macOS 13 or later on Apple Silicon, or GNU/Linux on `x86_64` or `aarch64`
  with glibc 2.26 or later

This README documents **AnyDocSwift 0.2.0**, which embeds **AnyDoc 0.2.4** with
bridge ABI v3. Its manifest pins the published immutable
[`binary-0.2.0`](https://github.com/ngutech21/anydoc-swift/releases/tag/binary-0.2.0)
artifacts for all three platforms. 

## Installation

```swift
dependencies: [
  .package(
    url: "https://github.com/ngutech21/anydoc-swift.git",
    exact: "0.2.0"
  )
]
```

Add `.product(name: "AnyDocSwift", package: "anydoc-swift")` to the consuming
target. SwiftPM downloads and verifies the checksum-pinned native artifact.
Swift package and native binary tags are separate: `binary-0.2.0` is the
artifact release, not a Swift package version. Until `0.2.0` is tagged, the
published dependency is `exact: "0.1.5"`; it does not include the structured
document API or Linux support described here.

## Quick start

Load a file into `Data` or pass bytes you already have:

```swift
import AnyDocSwift
import Foundation

let converter = AnyDocConverter()

// From a file path:
let bytes = try Data(contentsOf: URL(fileURLWithPath: "report.docx"))
let markdown = try await converter.markdown(from: bytes)

// From bytes, with the format detected from the content:
let fromBytes = try await converter.markdown(from: bytes)

// Or name it, which signature-less formats (CSV) need:
let csvBytes = Data("name,value\nexample,42\n".utf8)
let fromCsv = try await converter.markdown(from: csvBytes, format: .csv)

// Or stop at the document model, which also carries embedded assets:
let document = try await converter.document(from: bytes)
```

Passing `format: nil` delegates detection to AnyDoc. A supplied format is
authoritative and selects that parser even when the bytes resemble another
format.

To select a parser from a filename extension, use the library's lookup:

```swift
let url = URL(fileURLWithPath: "/path/to/workbook.xlsm")
let data = try Data(contentsOf: url)
let format = AnyDocFormat(fileExtension: url.pathExtension) // .xlsx
let markdown = try await converter.markdown(from: data, format: format)
```

The lookup does not read the file or inspect its bytes. An unknown extension
returns `nil`, so passing that result to either conversion method enables
automatic detection. Unwrap the result first if your application instead needs
to reject unknown extensions.

The returned `AnyDocDocument` is immutable parser output. Its public graph
contains:

- headings, paragraphs, lists, tables, block quotes, code blocks, rules, and
  display math;
- styled text, links, images, anchors, note references, line breaks, inline
  math, and checkboxes;
- canonical table grids with origin/covered slots and spans, including 1-by-1
  empty filler cells;
- footnotes and endnotes; and
- self-contained assets with stable integer IDs, media type, origin part, and
  copied `Data` bytes.

A command-line consumer using the public filename-extension lookup is in
[`Examples/AnyDocSwiftExample`](Examples/AnyDocSwiftExample).

## Supported formats

`AnyDocFormat` contains parser identities, not every filename alias:

| Canonical format | Document family | Recognized bare extensions |
| --- | --- | --- |
| `.doc` | Binary Word | `doc` |
| `.docx` | Open XML Word | `docx`, `docm` |
| `.odt` | OpenDocument text | `odt` |
| `.pdf` | PDF, Markdown only | `pdf` |
| `.ppt` | Binary PowerPoint | `ppt`, `pps`, `pot` |
| `.pptx` | Open XML PowerPoint | `pptx`, `pptm`, `ppsx`, `ppsm` |
| `.rtf` | Rich Text Format | `rtf` |
| `.epub` | EPUB | `epub` |
| `.xlsx` | Excel | `xls`, `xlsx`, `xlsm`, `xlsb` |
| `.ods` | OpenDocument spreadsheet | `ods` |
| `.odp` | OpenDocument presentation | `odp` |
| `.csv` | CSV | `csv` |

`AnyDocFormat(fileExtension:)` matches bare extensions case-insensitively using
ASCII characters only. It does not remove leading dots or whitespace or extract
extensions from full filenames. Unrecognized input, including `potx` and
`potm`, returns `nil`, matching pinned AnyDoc 0.2.4's extension lookup.

The `.xlsx` case selects the whole upstream Excel parser family, not a file
conversion to XLSX. Raw values remain canonical: `AnyDocFormat(rawValue: "xlsm")`
returns `nil`. Signature-less CSV data normally needs the explicit `.csv` format,
which the extension lookup also provides.

## Behavior and limitations

### Loading and limits

The converter accepts complete in-memory documents. Standard limits are 64 MiB
of input, 16 MiB of UTF-8 Markdown, and 128 MiB for a structured result. The
structured limit counts the encoded manifest plus every retained asset buffer.

```swift
let converter = AnyDocConverter(
  limits: .init(
    maximumInputBytes: 20 * 1024 * 1024,
    maximumOutputBytes: 5 * 1024 * 1024,
    maximumDocumentBytes: 64 * 1024 * 1024
  )
)
```

Applications handling untrusted or very large files should check file size
before loading the complete contents into `Data`.

### Concurrency and cancellation

Markdown and document operations share one FIFO queue per converter. Separate
converter instances may convert concurrently without blocking the main actor.

Cancellation before native work starts skips the call. An active native parser
call cannot be interrupted; conversion and cleanup finish before the awaiting
task receives `CancellationError`.

### Errors

Conversion failures use `AnyDocConversionError`, including invalid or oversized
input, oversized Markdown, oversized structured documents, unsupported,
OCR-required, malformed, encrypted, missing, resource-limited, and I/O cases.
Unknown future engine codes remain observable through
`unrecognizedUpstream(code:message:)`. Corrupt bridge transport becomes
`bridgeFailure`; task cancellation uses Swift's `CancellationError`.

### PDFs

Text-based PDFs can be converted to Markdown. An image-only, scanned, or mixed
PDF with any page requiring OCR fails with
`AnyDocConversionError.needsOCR(pages:pageCount:)`; no partial Markdown is
returned. Page numbers are sorted, unique, and one-based.

AnyDoc 0.2.4 intentionally has no structured document-model representation for
PDF. `document(from:format:)` therefore rejects `.pdf`; the package does not
synthesize a lossy graph.

The package does not provide OCR, streaming output, progress reporting,
active-parser interruption, file-path or security-scoped URL handling,
persistence, mutation/builders, or custom rendering.

## Architecture and contributing

See the [architecture guide](docs/architecture.md) for the runtime path,
ownership model, manifest validation, and binary distribution design. See
[CONTRIBUTING](CONTRIBUTING.md) for local setup and verification, and
[the release guide](docs/releasing.md) for the separately authorized native and
Swift release sequence.

## Licensing

AnyDocSwift is distributed under the [MIT License](LICENSE). The native bridge
incorporates third-party Rust crates whose exact licenses and attribution
notices are recorded in
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt). Native release archives
embed both files; distributors must retain them when copying or embedding the
artifact.
