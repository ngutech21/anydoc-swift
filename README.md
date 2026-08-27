# AnyDocSwift

AnyDocSwift is a macOS Swift package for converting supported document bytes
to GitHub-Flavored Markdown through the pinned Rust `anydoc` engine.

The implementation contract and acceptance criteria live in
[`docs/spec.md`](docs/spec.md). The Rust bridge and Swift public interface are
implemented and tested against a locally verified XCFramework. Publishing that
archive and wiring its immutable URL and checksum into SwiftPM remain separate
release steps, so the package is not yet consumable from an ordinary checkout.

## Requirements

- macOS 13 or later on Apple Silicon
- Swift 6.1 or later
- Rust 1.88.0 when rebuilding the native bridge

## Development

Once the immutable binary target is published and wired, conversion uses one
actor with a small public interface:

```swift
import AnyDocSwift

let converter = AnyDocConverter()
let markdown = try await converter.markdown(
  from: documentData,
  fileExtension: "docx"
)
```

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

Until the binary target is published, plain `swift build` and `swift test` are
expected to fail because `AnyDocSwiftBridge` is deliberately absent from
`Package.swift`. Development validation supplies the verified local framework's
headers and static library explicitly without committing a local binary target.

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
