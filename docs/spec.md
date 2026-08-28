# How AnyDocSwift Works

AnyDocSwift is a macOS Swift package that converts document bytes into
GitHub-Flavored Markdown. It wraps the Rust
[`anydoc`](https://github.com/firecrawl/anydoc) engine without exposing Rust or
C types to applications.

This document is the architectural guide to the repository. For installation
and a minimal example, start with the [README](../README.md).

## At a glance

```text
Application
  |
  | Data + optional file-extension hint
  v
AnyDocConverter (public Swift actor)
  |
  | normalized, size-checked request on a serial queue
  v
AnyDocCAdapter (private Swift adapter)
  |
  | length-delimited buffers through ABI version 1
  v
AnyDocSwiftBridge (dynamic framework with a private Rust runtime)
  |
  | content detection and conversion
  v
AnyDoc 0.2.3
  |
  | UTF-8 Markdown or a stable error code
  v
Application
```

There are two distinct build-time experiences:

- Applications consume a checksum-pinned XCFramework through SwiftPM. They do
  not need Rust, Cargo, or an external process.
- Contributors can rebuild that XCFramework from the pinned Rust source and
  toolchain, then test the Swift layer against the local artifact.

Conversion itself is local and in-process. It does not make network requests.

## Repository map

| Path | Responsibility |
| --- | --- |
| [`Package.swift`](../Package.swift) | Declares the public Swift library, private binary dependency, and supported platform. |
| [`Sources/AnyDocSwift/`](../Sources/AnyDocSwift/) | Contains the public actor and error type plus the private Swift-to-C adapter. |
| [`Native/include/`](../Native/include/) | Defines the versioned C ABI header used by Swift. |
| [`Native/framework/`](../Native/framework/) | Defines the framework module, bundle metadata, and exact exported-symbol list. |
| [`Rust/anydoc-swift-bridge/`](../Rust/anydoc-swift-bridge/) | Implements the C ABI, owns native result memory, and calls the pinned AnyDoc engine. |
| [`THIRD_PARTY_NOTICES.txt`](../THIRD_PARTY_NOTICES.txt) | Records the licenses and attribution notices for the locked native release graph. |
| [`Tests/AnyDocSwiftTests/`](../Tests/AnyDocSwiftTests/) | Tests public behavior, concurrency, cancellation, error mapping, ABI validation, and ownership. |
| [`Tests/Fixtures/`](../Tests/Fixtures/) | Holds provenance-recorded documents used for real conversions. |
| [`Tests/ArtifactSmoke/`](../Tests/ArtifactSmoke/) | Contains small C and Swift consumers used to validate the packaged framework. |
| [`Examples/AnyDocSwiftExample/`](../Examples/AnyDocSwiftExample/) | Demonstrates a complete command-line consumer. |
| [`Justfile`](../Justfile) | Provides the supported build, test, packaging, and verification entry points. |
| [`.github/workflows/`](../.github/workflows/) | Runs CI and the separate native-binary and Swift-package release processes. |
| [`rust-toolchain.toml`](../rust-toolchain.toml) | Pins the Rust compiler, components, and Apple Silicon target used for the bridge. |

SwiftPM is the root project. There is intentionally no root Xcode project.

## Layer responsibilities

### Public Swift API

[`AnyDocConverter`](../Sources/AnyDocSwift/AnyDocConverter.swift) is the only
conversion entry point. It accepts complete document data and an optional
extension hint:

```swift
let converter = AnyDocConverter()
let markdown = try await converter.markdown(
  from: documentData,
  fileExtension: "docx"
)
```

The actor owns the application-facing behavior:

- normalizing the extension hint;
- rejecting oversized input before native work starts;
- scheduling blocking native work away from the main actor;
- preserving FIFO execution for one converter instance; and
- presenting cancellation and typed Swift errors.

[`AnyDocConversionError`](../Sources/AnyDocSwift/AnyDocConversionError.swift)
describes conversion failures without leaking native types. The static
`AnyDocConverter.engineVersion` property reports the embedded AnyDoc revision
and bridge ABI, which is useful in diagnostics.

### Private Swift-to-C adapter

[`AnyDocCAdapter`](../Sources/AnyDocSwift/AnyDocCAdapter.swift) is the ownership
and validation boundary between safe Swift code and the native interface. It:

- verifies that the packaged bridge implements ABI version 1;
- keeps Swift input buffers alive for the synchronous C call;
- copies every returned native buffer before its owner is released;
- validates lengths, result shape, and UTF-8;
- frees each native result exactly once; and
- maps stable native error codes to `AnyDocConversionError` cases.

The bridge dependency is an `internal import`, so applications importing
`AnyDocSwift` do not see C declarations in the generated Swift interface.

### C ABI

[`anydoc_swift_bridge.h`](../Native/include/anydoc_swift_bridge.h) is a small,
handwritten interface based on byte pointers plus explicit lengths. A
conversion returns one opaque, Rust-owned result handle. Accessor functions
borrow Markdown or error buffers from that handle, and one Rust-provided free
function releases the handle and all of its buffers together.

The ABI also reports its version and the embedded engine version. This lets the
Swift adapter reject an incompatible or malformed binary instead of making
unsafe assumptions about it.

### Rust bridge and AnyDoc

[`lib.rs`](../Rust/anydoc-swift-bridge/src/lib.rs) validates pointers, lengths,
UTF-8, and configured limits before invoking AnyDoc. It detects the document
format from the bytes first and uses the extension only as a fallback. The
bridge calls AnyDoc's byte-to-Markdown path and converts its structured error
code and message into owned result data.

The complete native conversion is contained with Rust's `catch_unwind`. A
panic becomes a bridge failure rather than unwinding through C into Swift.
Release builds retain unwinding for this reason.

The native dependency is pinned to `anydoc = "=0.2.3"` and its complete
transitive graph is locked by
[`Cargo.lock`](../Rust/anydoc-swift-bridge/Cargo.lock). The embedded engine
version also records AnyDoc's originating revision so a diagnostic can identify
the exact parser implementation.

## Runtime conversion path

One call to `markdown(from:fileExtension:)` follows this sequence:

1. Swift checks task cancellation, normalizes the hint, and enforces the input
   limit before invoking native code.
2. The actor places the operation on its private serial queue. Work from one
   converter is FIFO; separate converter instances have separate queues.
3. The private adapter validates the packaged ABI and passes the data, hint,
   and limits as length-delimited buffers.
4. Rust validates the same boundary again, detects the format from content,
   falls back to the hint when needed, and asks AnyDoc for Markdown.
5. Rust enforces the output byte limit and returns either Markdown or a stable
   error code and message in one opaque result.
6. Swift validates and copies those bytes, translates any error, and frees the
   Rust result on every exit path.
7. Swift checks cancellation again before returning the Markdown.

This split keeps policy that matters to Swift callers in Swift, parsing in
AnyDoc, and pointer ownership at the FFI seam.

## Behavior applications should account for

### Format detection

Content detection is authoritative. The extension is a hint for formats that
cannot be identified reliably from bytes; CSV specifically requires the `csv`
hint. The hint is trimmed, one leading period is removed, and the result is
lowercased before it reaches the bridge.

Supported hints are:

- Word: `doc`, `docx`, `docm`
- PowerPoint: `ppt`, `pps`, `pot`, `pptx`, `pptm`, `ppsx`, `ppsm`
- Excel: `xls`, `xlsx`, `xlsm`, `xlsb`
- OpenDocument: `odt`, `ods`, `odp`
- Other: `rtf`, `epub`, `csv`, `pdf`

The API returns Markdown only. It does not expose AnyDoc's internal document
model or extract embedded assets.

### Limits and loading

The standard limits are 64 MiB of input and 16 MiB of UTF-8 Markdown. Both are
measured in bytes. Applications can create a converter with different limits:

```swift
let converter = AnyDocConverter(
  limits: .init(
    maximumInputBytes: 20 * 1024 * 1024,
    maximumOutputBytes: 5 * 1024 * 1024
  )
)
```

The input limit applies after the caller has loaded a document into `Data`.
Applications handling untrusted or very large files should also check file
size before loading the complete contents into memory.

### Concurrency and cancellation

Native parsing is synchronous, so the Swift actor moves it to a dedicated
serial queue instead of blocking the main actor. Use one converter when FIFO
ordering is desirable; use multiple converter instances when independent
documents should be eligible to run concurrently.

Cancellation can prevent queued work from starting. It cannot interrupt an
AnyDoc call that is already running. In that case conversion and native cleanup
finish first, then the awaiting task receives `CancellationError`.

### Errors

Expected conversion problems use `AnyDocConversionError`, including invalid or
oversized input, oversized output, unsupported, malformed, encrypted, missing,
resource-limited, and I/O cases. Unknown future AnyDoc codes are preserved in
`unrecognizedUpstream(code:message:)` rather than being inferred from message
text. ABI mismatches, invalid native UTF-8, panics, and inconsistent native
results become `bridgeFailure`.

Task cancellation is deliberately represented by Swift's `CancellationError`,
not by `AnyDocConversionError`.

### PDFs

Text-based PDFs can be converted. Image-only and scanned PDFs need OCR, which
this package does not provide. Mixed PDFs may return useful Markdown while
omitting pages that require OCR, so success does not guarantee that every page
was extracted.

### Current platform and feature boundaries

The released binary targets macOS 13 or later on Apple Silicon. The package
currently works on complete in-memory documents and does not provide:

- OCR;
- streaming output or progress reporting;
- interruption of an active native parser call;
- file-path or security-scoped URL handling;
- persistence or caching; or
- embedded asset extraction.

## Binary packaging

[`Package.swift`](../Package.swift) exposes the `AnyDocSwift` library and keeps
`AnyDocSwiftBridge` private to its implementation target. The bridge is a
remote binary target whose release URL and SHA-256 checksum are pinned together.
SwiftPM downloads and verifies that archive for ordinary `swift build` and
`swift test` commands.

For native development, `just artifact` performs the reproducible path:

1. build the Rust `staticlib` for `aarch64-apple-darwin` with the pinned Rust
   toolchain and macOS 13 deployment target as an internal intermediate;
2. verify that the committed third-party notices match the target-filtered,
   locked Cargo graph;
3. use Cargo's reported native link requirements to link that archive into a
   versioned, non-mergeable dynamic framework with a controlled `@rpath`
   install name and exactly eight exported C symbols;
4. copy the project license and third-party notices into the framework before
   signing it;
5. package the framework as an XCFramework ZIP and compute its SwiftPM
   checksum; and
6. reopen and validate the package, including its platform, architecture,
   Mach-O type, install name, dependencies, bundle structure, signature,
   license resources, exported ABI, and C and Swift smoke consumers.

The ignored output is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`. The local Swift recipes
set `ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1`, which selects the verified local
XCFramework through the same private binary-target seam used by the remote
release; that switch is for repository validation, not for package consumers.
The bridge owns its `CoreFoundation` and `iconv` dependencies, so the consumer
Swift target does not declare native system linker settings.

Native releases and Swift package releases are intentionally separate:

- `binary-X.Y.Z` releases contain an immutable XCFramework archive.
- `X.Y.Z` releases tag a `Package.swift` that points at a published binary URL
  and checksum.

A native change is released first under a new `binary-` tag. The manifest is
then updated to that immutable asset and checksum before the Swift package is
released. The workflows refuse to replace existing tags or releases.

## Development and verification

Install the pinned Rust toolchain, Swift 6.1 or later, Xcode command-line tools,
[`just`](https://github.com/casey/just), `jq`, `actionlint`, and
`cargo-about 0.9.1`. From the repository root:

```sh
# Show every supported task.
just --list

# Run Rust formatting, linting, builds, and tests.
just ci-rust

# Build and verify a local XCFramework, lint and build Swift, and run Swift tests.
just ci-swift

# Run both suites.
just ci

# Run workflow and diff linting followed by every Rust and Swift CI check.
just final-check

# Regenerate or verify the committed notices for the locked native graph.
just update-licenses
just check-licenses

# Only build, package, and verify the native release archive.
just artifact
```

The tests are organized around the seams they protect:

- Rust tests cover raw-buffer validation, detection, limits, error codes,
  result invariants, panic containment, and the exported ABI.
- Swift adapter tests cover ABI and UTF-8 validation, error translation,
  output bounds, malformed native results, and result cleanup.
- Public actor tests cover normalization, limits, FIFO execution, independent
  concurrency, main-actor responsiveness, and cancellation at each stage.
- Artifact smoke tests prove that packaged C and Swift consumers can link and
  run without Cargo on `PATH`; artifact and Xcode-package verification also
  prove that the project license and third-party notices survive packaging.
- The Rust composition smoke links a test-only Rust static library beside the
  dynamic bridge and proves that both unwind runtimes coexist without a symbol
  collision.
- The Xcode package smoke proves that `ProcessXCFramework` places the bridge in
  its named framework product rather than a shared `include/module.modulemap`
  output.
- Real RTF and CSV fixtures exercise the pinned AnyDoc engine. Their provenance
  and hashes are recorded in [`Tests/Fixtures/README.md`](../Tests/Fixtures/README.md).

Tests themselves do not access the network. A clean Cargo build may need
network access once to resolve the locked crates.io dependency graph.

## Making changes safely

The module stays small by keeping each behavior at one owning seam:

- Public behavior, scheduling, or cancellation changes belong in
  `AnyDocConverter.swift` with public actor tests.
- Error presentation changes belong in `AnyDocConversionError.swift`; native
  code mapping stays in `AnyDocCAdapter.swift`.
- Pointer, result-ownership, detection, or AnyDoc integration changes belong in
  the Rust bridge and require focused Rust and adapter tests.
- An ABI change must update the C header, Rust exports, Swift adapter, ABI
  version, smoke tests, and native binary release as one unit.
- An AnyDoc upgrade must update the exact Cargo dependency, lockfile, embedded
  version and revision, fixture expectations, generated third-party notices,
  and released XCFramework intentionally.
- Linker settings must come from the built artifact rather than assumptions
  about a developer machine.

The core invariants are that native work never blocks the main actor, C and Rust
types remain private, buffers never outlive their Rust owner, a panic never
crosses the C ABI, and consuming applications never build or link an unpackaged
Rust library.
