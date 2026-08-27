# Implementation Specification: AnyDocSwift

## 1. Objective

Create a standalone Swift package named `AnyDocSwift` that converts supported document bytes into GitHub-Flavored Markdown.

The package must:

- Run locally and in-process.
- Wrap the Rust `anydoc` crate through a small, handwritten C ABI.
- Ship the Rust implementation as a macOS XCFramework.
- Expose one idiomatic asynchronous Swift conversion interface.
- Return Markdown on success or a typed Swift error on failure.
- Require neither Rust nor Cargo in consuming applications.
- Never block the main actor during conversion.

The initial release targets macOS 13 or later on Apple Silicon.

## 2. Authoritative upstream version

Pin AnyDoc to:

- crates.io dependency: `anydoc = "=0.2.3"`
- crates.io archive checksum:
  `cba429594e94170aa99d2e4e0f596719ecc5c5df00269c671bc60c9e08172678`
- Originating commit:
  [`bf3d33e61731580d1ee1c6a85e56093d715a21a6`](https://github.com/firecrawl/anydoc/commit/bf3d33e61731580d1ee1c6a85e56093d715a21a6)
- Minimum Rust toolchain: `1.88.0`

Use the immutable crates.io archive as the build source. Its
`.cargo_vcs_info.json` records the originating commit above, which remains the
implementation authority. Commit `Cargo.lock` and do not silently upgrade
AnyDoc or its transitive dependencies.

## 3. Scope

### Supported input

The wrapper accepts:

- Document contents as `Foundation.Data`.
- An optional file-extension hint such as `"docx"` or `"csv"`.

Supported extensions:

- Word: `doc`, `docx`, `docm`
- PowerPoint: `ppt`, `pps`, `pot`, `pptx`, `pptm`, `ppsx`, `ppsm`
- Excel: `xls`, `xlsx`, `xlsm`, `xlsb`
- OpenDocument: `odt`, `ods`, `odp`
- Other: `rtf`, `epub`, `csv`, `pdf`

Detection must inspect document contents first. The extension is only a fallback. CSV requires an extension hint because it has no reliable binary signature.

### Output

Successful conversion returns one UTF-8 Markdown `String`.

The wrapper does not expose AnyDoc’s internal document model, embedded assets, parser types, or Rust types.

Embedded images and objects may appear only as Markdown alt text. Asset extraction is outside this specification.

### PDF behavior

Document the following behavior prominently:

- Text-based PDFs can be converted.
- Image-only and scanned PDFs are unsupported.
- Mixed PDFs may return successful Markdown while omitting pages that require OCR.
- A successful PDF conversion means meaningful Markdown was produced; it does not guarantee that every page was extracted.
- The wrapper must not parse log messages to infer PDF completeness.

### Explicit non-goals

The first release does not provide:

- OCR.
- Streaming output.
- Native cancellation of an active parser call.
- Progress reporting.
- File-path or security-scoped URL handling.
- Persistence or caching.
- Embedded asset extraction.
- iOS, Mac Catalyst, visionOS, or Intel macOS support.

## 4. Module design

Implement one deep Swift module with a small public interface:

```text
Swift application
    -> AnyDocSwift public interface
        -> private Swift-to-C adapter
            -> C ABI
                -> Rust bridge
                    -> pinned AnyDoc implementation
```

Format detection, parser selection, Rust memory ownership, background scheduling, output limits, error translation, panic containment, and version reporting belong behind the interface.

Do not add a public protocol, factory, parser registry, or format-specific converter. Tests may use a package-internal seam for fault injection, but that seam must not become public.

## 5. Public Swift interface

Expose only the following conceptual interface. Naming changes require a concrete technical reason.

```swift
import Foundation

public actor AnyDocConverter {
    public struct Limits: Sendable, Equatable {
        public static let standard = Limits(
            maximumInputBytes: 64 * 1024 * 1024,
            maximumOutputBytes: 16 * 1024 * 1024
        )

        public let maximumInputBytes: UInt64
        public let maximumOutputBytes: UInt64

        public init(
            maximumInputBytes: UInt64,
            maximumOutputBytes: UInt64
        )
    }

    public init(limits: Limits = .standard)

    public func markdown(
        from data: Data,
        fileExtension: String? = nil
    ) async throws -> String

    public static var engineVersion: String { get }
}
```

Define this typed error:

```swift
public enum AnyDocConversionError:
    Error,
    Sendable,
    Equatable,
    LocalizedError
{
    case inputTooLarge(
        actualBytes: UInt64,
        maximumBytes: UInt64
    )
    case outputTooLarge(maximumBytes: UInt64)
    case invalidInput(String)
    case unsupported(String)
    case malformed(String)
    case encrypted(String)
    case resourceLimit(String)
    case missingPart(String)
    case io(String)
    case unrecognizedUpstream(
        code: String,
        message: String
    )
    case bridgeFailure(String)
}
```

Requirements:

- Map known upstream error codes without parsing human-readable messages.
- Preserve unknown future upstream codes using `unrecognizedUpstream`.
- Represent task cancellation with `CancellationError`, not `AnyDocConversionError`.
- Provide useful, non-sensitive `LocalizedError` descriptions.
- Do not expose C or Rust declarations through the generated Swift interface.

## 6. Swift behavior

### Extension normalization

Before entering the native bridge:

1. Trim surrounding whitespace.
2. Remove one leading period.
3. Lowercase using locale-independent rules.
4. Treat an empty result as no extension.
5. Reject extension hints longer than 64 UTF-8 bytes as `invalidInput`.

An unrecognized but valid extension remains a hint; content detection must still be attempted first.

### Limits

- Reject data exceeding `maximumInputBytes` before invoking native code.
- Pass both configured limits into the Rust bridge for defense in depth.
- Enforce the Markdown limit inside Rust before returning data across the ABI.
- Check the returned length again in Swift.
- Measure both limits in bytes, not characters.

The input limit does not replace a caller-side file-size check before loading a file into `Data`.

### Execution and concurrency

- Execute the synchronous native call on a dedicated serial queue.
- Never perform parsing on `MainActor`.
- Preserve FIFO execution within one `AnyDocConverter` instance.
- Different converter instances may operate concurrently.
- Check cancellation before enqueueing, when queued work begins, and after
  native conversion.
- If a task is cancelled while waiting on the serial queue, skip its native
  call and throw `CancellationError`.
- Once native conversion begins, cancellation cannot interrupt it. The native operation finishes, its allocation is released, and the Swift task then throws `CancellationError`.

These semantics must be documented as part of the interface.

## 7. C ABI

Create a Rust `staticlib` with an opaque result handle. Use length-delimited UTF-8 buffers instead of NUL-terminated input strings.

The public header should be equivalent to:

```c
#ifndef ANYDOC_SWIFT_BRIDGE_H
#define ANYDOC_SWIFT_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct anydoc_swift_result anydoc_swift_result_t;

uint32_t anydoc_swift_abi_version(void);

const uint8_t *anydoc_swift_engine_version(
    size_t *out_length
);

anydoc_swift_result_t *anydoc_swift_convert_markdown(
    const uint8_t *bytes,
    size_t bytes_length,
    const uint8_t *extension_utf8,
    size_t extension_length,
    uint64_t maximum_input_bytes,
    uint64_t maximum_output_bytes
);

int32_t anydoc_swift_result_is_success(
    const anydoc_swift_result_t *result
);

const uint8_t *anydoc_swift_result_markdown(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

const uint8_t *anydoc_swift_result_error_code(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

const uint8_t *anydoc_swift_result_error_message(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

void anydoc_swift_result_free(
    anydoc_swift_result_t *result
);

#ifdef __cplusplus
}
#endif

#endif
```

### ABI invariants

- ABI version starts at `1`.
- `bytes` may be null only when `bytes_length == 0`.
- `extension_utf8` may be null only when `extension_length == 0`.
- Returned buffers remain valid until `anydoc_swift_result_free`.
- Swift must copy every returned buffer before freeing the result.
- A result must be freed exactly once with the Rust-provided free function.
- `anydoc_swift_result_free(NULL)` is a no-op.
- Accessors receiving null return null and set the output length to zero.
- A success result contains Markdown and no error.
- A failure result contains an error code and message and no Markdown.
- No Rust `String`, `Vec`, enum, or allocator-owned pointer may be freed directly by Swift.

## 8. Rust bridge requirements

The Rust implementation must:

- Use `crate-type = ["staticlib"]`.
- Pin AnyDoc to the exact specified crates.io release and verify its recorded
  originating revision.
- Use `#[unsafe(no_mangle)] extern "C"` exports appropriate for Rust 2024.
- Validate every pointer and length before constructing a slice.
- Decode the extension as UTF-8 without unchecked conversion.
- Detect format from bytes first and extension second.
- Call only the upstream byte-to-Markdown conversion path.
- Translate `ConvertError::code()` and `Display` into owned result data.
- Preserve these upstream codes:
  - `unsupported`
  - `malformed`
  - `encrypted`
  - `resourceLimit`
  - `missingPart`
  - `io`
- Use wrapper-owned codes for:
  - `wrapper.invalidInput`
  - `wrapper.inputLimit`
  - `wrapper.outputLimit`
  - `bridge.panic`
- Wrap the complete conversion operation in `catch_unwind`.
- Compile releases with unwinding enabled so a Rust panic never crosses the C ABI.
- Never include document contents in diagnostics or panic messages.
- Remain stateless and avoid mutable global parser state.

`engineVersion` should return a static value containing the AnyDoc version, exact revision, and bridge ABI version.
The Swift adapter must validate ABI version `1` and strict UTF-8 before exposing
that value. Because the public property is nonthrowing, an ABI mismatch, null or
empty version buffer, or invalid UTF-8 returns the fixed string
`AnyDoc engine version unavailable`. Conversion calls report the same integrity
failures as `bridgeFailure`.

## 9. Package structure

Use a structure equivalent to:

```text
Package.swift
Sources/
  AnyDocSwift/
    AnyDocConverter.swift
    AnyDocConversionError.swift
    AnyDocCAdapter.swift
Rust/
  anydoc-swift-bridge/
    Cargo.toml
    Cargo.lock
    src/
      lib.rs
rust-toolchain.toml
Native/
  include/
    anydoc_swift_bridge.h
    module.modulemap
Tests/
  AnyDocSwiftTests/
  Fixtures/
  ArtifactSmoke/
    main.c
    main.swift
Examples/
  ConsumerApp/
Justfile
LICENSE
THIRD_PARTY_NOTICES.md
README.md
```

`Package.swift` must:

- Use Swift tools version 6.1 or later.
- Declare macOS 13 as the minimum platform.
- Expose the `AnyDocSwift` library product.
- Include the XCFramework as a checksum-pinned remote binary target after its
  immutable release asset has been published and verified.
- Keep the C module internal to the Swift implementation.

## 10. XCFramework build

The Justfile artifact recipes must compose the standard Cargo, Xcode, and
SwiftPM commands to:

1. Verify the expected Rust toolchain.
2. Build with `cargo build --release --locked --target aarch64-apple-darwin`.
3. Set `MACOSX_DEPLOYMENT_TARGET=13.0`.
4. Produce the static library.
5. Stage the header and module map.
6. Create `AnyDocSwiftBridge.xcframework` with `xcodebuild -create-xcframework`.
7. Verify that the artifact contains only the expected macOS arm64 slice.
8. Package the XCFramework as a ZIP under the ignored `.build/artifacts`
   directory.
9. Record the ZIP's SwiftPM-compatible SHA-256 checksum.
10. Run a C-link smoke test against the packaged artifact.
11. Run a Swift consumer build that has no dependency on Cargo.

The recipe interface is:

```text
just build-artifact
just verify-artifact [archive]
just artifact
```

`just artifact` performs both steps. The default archive is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`.

Release archives are published outside Git under immutable `binary-<version>`
GitHub release tags. Never replace an existing release archive in place; a
native change requires a new bridge version, release URL, and checksum.

Inspect the Rust build’s required native libraries and Apple frameworks. Declare any required linker settings explicitly in `Package.swift`; do not guess or rely on developer-machine environment state.

Consuming applications must not invoke Cargo during resolution, build, or execution.

## 11. Tests

Tests must use committed fixtures with recorded provenance and hashes and must
not access network resources at runtime. Resolving the locked Cargo dependency
graph on a clean machine may access crates.io.

### Rust tests

Cover:

- Null-pointer and length validation.
- Empty input.
- Invalid UTF-8 extension.
- Input and output limits.
- Content-first detection.
- Extension fallback.
- Upstream error-code preservation.
- Unknown error-code preservation.
- Panic containment through an internal test seam.
- Success and failure result invariants.
- Null-safe accessors and free function.
- Embedded version and ABI information.

### Swift tests

Cover:

- Successful Markdown conversion.
- Extension normalization.
- Mislabeled files detected by content.
- CSV success with an extension.
- CSV failure without an extension.
- Every supported extension mapping.
- Input and output limits.
- Every typed error mapping.
- Unknown upstream errors.
- Invalid native UTF-8 reported as `bridgeFailure`.
- Native results freed on every success, failure, and cancellation path.
- FIFO serialization.
- Main-actor responsiveness using deterministic gates rather than timing sleeps.
- Cancellation before dispatch, while queued, and during an active native call.
- Engine-version fallback for ABI mismatch, missing data, and invalid native
  UTF-8.

### Fixture coverage

Include representative fixtures for:

- Legacy and OOXML Word documents.
- Legacy and OOXML presentations.
- Legacy, OOXML, and binary spreadsheets.
- OpenDocument text, spreadsheet, and presentation files.
- RTF.
- EPUB.
- CSV.
- Text PDF.
- Image-only PDF.
- Mixed text/OCR PDF.
- Encrypted input.
- Malformed archives.
- Upstream resource-limit cases.

Snapshot expected Markdown for the pinned AnyDoc revision. An upstream upgrade must intentionally review and update these snapshots.

## 12. Verification commands

The finished implementation must pass:

```text
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
swift build
swift build -c release
swift test
just artifact
```

The repository exposes those checks through the same Justfile entrypoints used
by continuous integration:

```text
just build-rust
just test-rust
just build-swift
just test-swift
just ci-rust
just ci-swift
just ci
```

`just ci-rust` performs Rust formatting, linting, building, and testing.
`just ci-swift` performs strict Swift format linting, builds and verifies the
local XCFramework, builds the Swift package in debug and release configurations,
and runs its tests against that verified artifact. It must not modify
`Package.swift` to inject a local binary target. `just ci` performs both suites.

Also build and run the example consumer application on Apple Silicon without using a locally built Rust library.

Run a repeated-conversion leak check against the release artifact and verify that result handles and returned buffers are not leaked.

## 13. Documentation and licensing

The README must include:

- Swift Package integration instructions.
- A minimal conversion example.
- Supported formats.
- Input and output limit semantics.
- Error behavior.
- Concurrency and cancellation semantics.
- PDF completeness limitations.
- The embedded AnyDoc version and revision.
- Instructions for rebuilding the XCFramework.

Retain AnyDoc’s MIT license notice. Generate and review a third-party license report from the locked Rust dependency graph and commit it as `THIRD_PARTY_NOTICES.md`.

## 14. Acceptance criteria

The work is complete only when:

- A macOS Swift application can import `AnyDocSwift` and convert document `Data` to Markdown.
- The consuming application needs no Rust toolchain or external runtime.
- No C or Rust type appears in the public Swift interface.
- Detection is content-first with extension fallback.
- CSV behavior is covered explicitly.
- Known conversion failures produce distinct Swift errors.
- Unknown upstream error codes remain observable.
- Malformed or encrypted fixtures cannot unwind across the ABI.
- Input and output limits are enforced.
- Conversion does not block the main actor.
- Every native allocation is released by Rust.
- PDF and embedded-asset limitations are documented accurately.
- No speculative public abstractions or unfinished compatibility paths remain.
- The exact AnyDoc revision, Cargo lockfile, XCFramework, checksum, notices, and verification results are present.

## 15. Implementation reporting

When implementation is finished, report:

- Files added or changed.
- The final public Swift interface.
- The exact upstream revision.
- XCFramework architecture and checksum.
- Required native linker settings.
- Every verification command and its actual result.
- Any acceptance criterion that remains unverified.

Do not report completion while required checks are failing or skipped without a concrete explanation.
