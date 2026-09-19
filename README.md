# AnyDocSwift

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/anydoc-swift/ci.yml?branch=master&event=push&label=CI)](https://github.com/ngutech21/anydoc-swift/actions/workflows/ci.yml)
[![Swift package release](https://img.shields.io/github/v/release/ngutech21/anydoc-swift?filter=%21binary-%2A&sort=semver&label=release)](https://github.com/ngutech21/anydoc-swift/releases)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](#requirements)
[![macOS 13+ (Apple Silicon)](https://img.shields.io/badge/macOS-13%2B%20%28Apple%20Silicon%29-blue?logo=apple&logoColor=white)](#requirements)
[![GNU/Linux (x86_64, aarch64)](https://img.shields.io/badge/GNU%2FLinux-x86__64%20%7C%20aarch64-blue?logo=linux&logoColor=white)](#requirements)
[![License](https://img.shields.io/github/license/ngutech21/anydoc-swift)](LICENSE)

AnyDocSwift converts Word, PowerPoint, Excel, OpenDocument, PDF, EPUB, RTF,
and CSV data to GitHub-Flavored Markdown in Swift applications.

Conversion runs locally by default and in-process through the Rust
[Firecrawl anydoc](https://github.com/firecrawl/anydoc) engine. Applications
install the package through SwiftPM and do not need Rust, Cargo, or an external
service.
AnyDocSwift 0.2.2 also supports explicitly opted-in hosted OCR through the
Firecrawl Parse API for PDFs that need it; see [Hosted OCR](#hosted-ocr).

This independent community project is not affiliated with, endorsed by, or maintained by Firecrawl.

## Requirements

- Swift 6.2 or later
- macOS 13 or later on Apple Silicon, or GNU/Linux on `x86_64` or `aarch64`
  with glibc 2.26 or later

## Installation

Add AnyDocSwift to your package dependencies and to the target that uses it.
For example, a command-line app's `Package.swift` can look like this. Replace
`MyApp` with your package and target name:

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MyApp",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(
      url: "https://github.com/ngutech21/anydoc-swift.git",
      exact: "0.2.2"
    )
  ],
  targets: [
    .executableTarget(
      name: "MyApp",
      dependencies: [
        .product(name: "AnyDocSwift", package: "anydoc-swift")
      ]
    )
  ]
)
```

SwiftPM downloads the required native library automatically.

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

// Opt in to hosted OCR when local PDF parsing requires it.
// Obtain user consent to upload the entire PDF to the chosen service first.
let pdf = try Data(contentsOf: URL(fileURLWithPath: "scanned.pdf"))
let fromScannedPdf = try await converter.markdown(
  from: pdf, format: .pdf, ocr: .hosted()
)
```

Hosted OCR uses the Firecrawl Parse API by default. `.hosted()` reads optional
`FIRECRAWL_API_KEY` and `FIRECRAWL_API_URL` environment variables; use
`.hosted(apiKey:apiURL:)` to supply credentials and an endpoint explicitly.
See [Hosted OCR](#hosted-ocr) for configuration and fallback behavior.

For complete command-line examples, see
[`Examples/AnyDocSwiftExample`](Examples/AnyDocSwiftExample) and
[`Examples/HostedOCR`](Examples/HostedOCR/README.md).

## Supported formats

Use these `AnyDocFormat` cases to select a document format explicitly:

| Format | Document family | File extensions |
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

> [!IMPORTANT]
> **PDF supports Markdown output only.** Local OCR and structured PDF output
> are not supported. By default, if any page requires OCR, conversion fails
> without returning partial Markdown. Explicitly opt in to [Hosted OCR](#hosted-ocr)
> to enable fallback through the Firecrawl Parse API. See [PDF behavior](#pdfs)
> for error details.

## Behavior and limitations

### Format selection

Passing `format: nil` delegates detection to anydoc. A supplied format is
authoritative and selects that parser even when the bytes resemble another
format. Signature-less CSV data normally needs the explicit `.csv` format.

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

`AnyDocFormat(fileExtension:)` matches bare extensions case-insensitively using
ASCII characters only. It does not remove leading dots or whitespace or extract
extensions from full filenames. Unrecognized input, including `potx` and
`potm`, returns `nil`, matching pinned anydoc 0.2.4's extension lookup.

`AnyDocFormat` cases identify parsers, rather than every filename alias. The
`.xlsx` case selects the whole upstream Excel parser family, not a file
conversion to XLSX. Raw values remain canonical: `AnyDocFormat(rawValue: "xlsm")`
returns `nil`; use `AnyDocFormat(fileExtension:)` for filename aliases.

### Structured documents

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

The FIFO slot includes hosted requests and their cleanup. HTTP suspends
asynchronously, leaving the native serial worker free. Cancellation before
native work starts skips the call. An active native parser
call cannot be interrupted; conversion and cleanup finish before the awaiting
task receives `CancellationError`. Cancellation prevents an unstarted hosted
request and cancels an active HTTP task. Cancellation observed before returning
takes precedence over success or another failure.

### Errors

Conversion failures use `AnyDocConversionError`, including invalid or oversized
input, oversized Markdown, oversized structured documents, unsupported,
OCR-required, malformed, encrypted, missing, resource-limited, and I/O cases.
Unknown future engine codes remain observable through
`unrecognizedUpstream(code:message:)`. Corrupt bridge transport becomes
`bridgeFailure`; task cancellation uses Swift's `CancellationError`.
Hosted OCR failures use `.hostedOCR(HostedOCRFailure)` with fixed,
privacy-safe descriptions; see the [error reference](docs/errors.md).

### PDFs

Text-based PDFs can be converted to Markdown locally. By default, an image-only,
scanned, or mixed PDF with any page requiring OCR fails with
`AnyDocConversionError.needsOCR(pages:pageCount:)`; no partial Markdown is
returned. Page numbers are sorted, unique, and one-based.
Explicitly select [Hosted OCR](#hosted-ocr) to allow fallback for these PDFs.

anydoc 0.2.4 intentionally has no structured document-model representation for
PDF. `document(from:format:)` therefore rejects `.pdf`; the package does not
synthesize a lossy graph.

### Hosted OCR

Hosted OCR is available in the released AnyDocSwift 0.2.2 package. The
`markdown(from:format:)` overload remains local-only. Explicitly
select `.hosted` to allow fallback after a structured `.needsOCR` failure:

```swift
// Application consent must cover uploading the entire PDF to the chosen service.
let markdown = try await converter.markdown(from: pdf, ocr: .hosted())

// Credentials belong to the application, not the library.
let authenticated = try await converter.markdown(
  from: pdf, format: .pdf, ocr: .hosted(apiKey: apiKey)
)
```

Local success returns immediately. Other local errors never trigger an upload.
When fallback begins, the complete original PDF is transmitted, including pages
that already contain text. Environment variables alone never enable uploads.
Use the original overload or `.reject` to preserve local-only behavior and
the OCR-required page metadata.

Configuration follows the Node.js wrapper at the pinned anydoc revision:

| Setting | Resolution, in order |
| --- | --- |
| API key | Explicit `apiKey`, `FIRECRAWL_API_KEY`, then keyless |
| Base URL | Explicit `apiURL`, `FIRECRAWL_API_URL`, then `https://api.firecrawl.dev` |

Only `nil` falls through. `apiKey: ""` suppresses environment credentials and
omits authorization. `apiURL: ""` is invalid configuration. At most one trailing
slash is removed before appending `/v2/parse`. For example,
`.hosted(apiURL: "https://ocr.example.com")` uses
`https://ocr.example.com/v2/parse`. A custom URL changes the recipient of the
entire document, so applications must include that destination in upload consent.
The endpoint must implement the upstream multipart parse API.

Keyless use follows the service's limits; HTTP 429 distinguishes keyless quota
exhaustion from authenticated rate limiting. Provider upload/credit limits may
vary by endpoint. AnyDocSwift retains its configured input/output limits and
adds no separate 50 MiB upload cap. It makes no application retries or retries
without credentials. A 300-second deadline covers the request, redirects, and
response reading. Redirects follow Node Fetch semantics, with authorization
removed across origins.

Store credentials in application-owned configuration or a suitable credential
store; do not embed secrets in distributed applications. Policies and hosted
errors redact sensitive details. Sandboxed macOS applications using hosted OCR
need the outgoing network entitlement `com.apple.security.network.client`.

See the [hosted OCR example](Examples/HostedOCR/README.md) for buildable
code. The [architecture guide](docs/architecture.md#hosted-ocr) describes the
pinned wrapper contract, Node.js tie-breaker, and deliberate Swift guarantees.

### Other limitations

The package does not provide local OCR, streaming output, progress reporting,
active-parser interruption, file-path or security-scoped URL handling,
persistence, mutation/builders, or custom rendering.

### Native artifacts

AnyDocSwift 0.2.2 embeds **anydoc 0.2.4** with bridge ABI v3. Its manifest pins
the immutable
[`binary-0.2.0`](https://github.com/ngutech21/anydoc-swift/releases/tag/binary-0.2.0)
artifacts for macOS arm64 and GNU/Linux x86_64 and aarch64. SwiftPM verifies
the downloaded artifact against its pinned checksum.

Swift package and native binary tags are separate: use `0.2.2` as the package
version; `binary-0.2.0` identifies its native artifact release.

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
