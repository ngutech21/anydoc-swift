# AnyDocSwift Architecture

AnyDocSwift is one deep Swift module over the pinned Rust
[`anydoc`](https://github.com/firecrawl/anydoc) engine. It converts complete
in-memory document bytes either to GitHub-Flavored Markdown or to an immutable,
self-contained Swift document graph without exposing Rust or C types.

For installation and usage, start with the [README](../README.md). For local
setup and verification, see [CONTRIBUTING](../CONTRIBUTING.md). Maintainer-only
publishing is documented in [Releasing AnyDocSwift](releasing.md).

## At a glance

```text
Application
  |
  | Data + optional AnyDocFormat + output limits
  v
AnyDocConverter (public Swift actor, one mixed FIFO queue)
  |
  | checked request on a serial worker queue
  v
AnyDocCAdapter (private ownership and validation boundary)
  |
  | length-delimited buffers through bridge ABI v3
  v
AnyDocSwiftBridge (private platform-native artifact)
  |
  | canonical parser selection or AnyDoc detection
  v
AnyDoc 0.2.4 / revision 42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c
  |
  +--> Markdown bytes
  |
  +--> schema-v1 manifest + separately retained asset buffers
  |
  +--> stable error code + optional structured OCR metadata
```

Applications consume a checksum-pinned native artifact through SwiftPM and do
not need Cargo or an external process. Contributors rebuild the native artifact
from the locked Rust graph and run the Swift package against that verified
local artifact. Conversion itself is local and makes no network requests.

## Repository map

| Path | Responsibility |
| --- | --- |
| [`Package.swift`](../Package.swift) | Declares the public Swift library, private bridge dependency, and host selection. |
| [`Sources/AnyDocSwift/`](../Sources/AnyDocSwift/) | Owns the public actor, format/error/document types, private decoder, and private C adapter. |
| [`Native/include/`](../Native/include/) | Defines the portable ABI-v3 C header. |
| [`Native/framework/`](../Native/framework/) | Defines the macOS framework metadata and exact export list. |
| [`Native/linux/`](../Native/linux/) | Defines Linux artifact metadata, native linker requirements, and exact export list. |
| [`Rust/anydoc-swift-bridge/`](../Rust/anydoc-swift-bridge/) | Calls AnyDoc, serializes transport schema v1, and owns native results. |
| [`Tests/AnyDocSwiftTests/`](../Tests/AnyDocSwiftTests/) | Tests public behavior, transport validation, concurrency, cancellation, ABI shape, and ownership. |
| [`Tests/Fixtures/`](../Tests/Fixtures/) | Holds provenance-recorded upstream fixtures for real conversions. |
| [`Tests/ArtifactSmoke/`](../Tests/ArtifactSmoke/) | Contains Cargo-free C and Swift consumers of packaged artifacts. |
| [`Tests/MemoryProbe/`](../Tests/MemoryProbe/) | Generates deterministic asset/manifest-heavy documents for the release-only RSS gate. |
| [`Scripts/check-public-interface.sh`](../Scripts/check-public-interface.sh) | Proves the generated public symbol graph contains no bridge declarations. |
| [`Scripts/memory-probe.sh`](../Scripts/memory-probe.sh) | Runs the non-default Release memory qualification. |
| [`Scripts/linux-artifact.sh`](../Scripts/linux-artifact.sh) | Builds, namespaces, packages, audits, and tests one native Linux artifact. |
| [`Justfile`](../Justfile) | Provides supported build, test, packaging, and verification entry points. |

SwiftPM is the root project. There is intentionally no root Xcode project.

## Public Swift contract

[`AnyDocConverter`](../Sources/AnyDocSwift/AnyDocConverter.swift) is the only
conversion entry point:

```swift
let converter = AnyDocConverter()
let markdown = try await converter.markdown(from: data, format: .docx)
let document = try await converter.document(from: data, format: .docx)
```

[`AnyDocFormat`](../Sources/AnyDocSwift/AnyDocFormat.swift) is a closed set of
canonical parser identities. A supplied value authoritatively selects its
parser. Passing `nil` delegates detection to AnyDoc.

`AnyDocFormat(fileExtension:)` owns filename-extension alias lookup in Swift.
It mirrors `Format::from_extension` from AnyDoc 0.2.4's `src/lib.rs` at revision
`42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`; recheck this mapping and its public
tests when upgrading the engine. Bare extensions use ASCII case-insensitive
matching, without trimming whitespace, stripping dots, or extracting filename
suffixes. Unknown and non-ASCII input returns `nil`; `potx` and `potm` are not
recognized by the pinned lookup. `.xlsx` represents the whole upstream Excel
parser family, including `xls`, `xlsm`, and `xlsb`.

This pure lookup performs no file access, content detection, or native calls.
Passing its result to either converter method makes a recognized extension
authoritative; an unrecognized extension delegates detection to AnyDoc. Callers
that need to reject unknown extensions can unwrap first. Existing canonical raw
values and `init(rawValue:)` remain unchanged. The example uses this public
initializer instead of maintaining its own alias table.

[`AnyDocDocument`](../Sources/AnyDocSwift/AnyDocDocument.swift) is immutable
parser output, not a builder or persistence schema. Its get-only graph preserves
every upstream block, inline, link/image target, list, canonical table slot,
note, and asset value, with empty table fillers canonicalized to 1-by-1 origins.
Struct initializers are internal; public values are `Sendable` and `Equatable`,
but deliberately not `Codable`.

The actor owns application-facing policy:

- enforcing the input limit before native work begins;
- moving synchronous native calls off the caller's executor;
- putting Markdown and document requests through one FIFO queue per converter;
- allowing separate converters to execute independently; and
- presenting queued/active cancellation with Swift's `CancellationError`.

One private generic operation implements that scheduling path for both public
methods, preventing the two result modes from developing different ordering or
cancellation behavior.

## Private Swift-to-C adapter

[`AnyDocCAdapter`](../Sources/AnyDocSwift/AnyDocCAdapter.swift) concentrates all
unsafe buffer borrowing and native-result ownership. It:

- requires bridge ABI v3;
- keeps input and canonical-format UTF-8 buffers alive for the synchronous C
  call;
- dispatches on the explicit result-kind discriminator;
- rejects fields belonging to a different payload kind;
- validates every length before copying through an unsafe pointer;
- maps stable upstream/wrapper codes without parsing display messages; and
- frees each opaque result exactly once on every success and failure path.

For a document result, Swift copies and decodes the manifest in a helper whose
temporary JSON `Data` dies before any asset is copied. It checks the manifest
length and all declared asset lengths cumulatively against
`maximumDocumentBytes`, then copies each indexed asset and verifies the exact
accessor length. A valid empty asset is distinguished from an accessor mismatch
by the accessor's explicit success status.

The bridge import is `internal`, and the release gate extracts the public Swift
symbol graph and rejects `AnyDocSwiftBridge` or `anydoc_swift_*` leakage.

## C ABI v3

[`anydoc_swift_bridge.h`](../Native/include/anydoc_swift_bridge.h) exports
exactly 12 functions:

- ABI and embedded-engine version accessors;
- Markdown and document conversion entry points;
- a result-kind discriminator for failure, Markdown, and document payloads;
- Markdown, manifest, indexed asset, error code/message, and OCR metadata
  accessors; and
- one common result free function.

Wrong-payload and out-of-range accessors return no value and reset their
outputs. The indexed asset accessor separately reports success, so a valid
zero-byte asset is not confused with absence. Every returned buffer is borrowed
from the opaque result and remains valid only until the common free function.

The full native conversion is enclosed by Rust's `catch_unwind`; a panic becomes
the fixed `bridge.panic` failure instead of unwinding through C. Release builds
therefore retain Rust unwinding.

## Rust integration and document transport

[`engine.rs`](../Rust/anydoc-swift-bridge/src/engine.rs) is safe Rust. It owns
input/output limit enforcement, canonical format mapping, calls to
`to_markdown_bytes` and `to_document`, and structured upstream error mapping.
An explicit format is passed directly to AnyDoc and is authoritative; absence
invokes AnyDoc's detection.

[`transport.rs`](../Rust/anydoc-swift-bridge/src/transport.rs) owns manifest
schema version 1. It destructures the upstream document, moves each asset byte
buffer into the result without cloning it, serializes temporary structural DTOs
with direct `serde`/`serde_json` dependencies, drops those temporary values, and
retains the manifest and assets separately in the opaque result.

The pinned AnyDoc 0.2.4 grid builder uses empty `Cell::default()` origins with
zero spans for gaps before later-column row spans and for stray covered markers.
The transport represents those single empty positions as 1-by-1 origins.
Cells containing blocks or having only one zero span retain their source
values for Swift's defensive validation.

Schema v1 has top-level `schemaVersion`, `blocks`, `notes`, and `assets` fields.
Associated-value enums use an adjacent `kind` plus optional `value` envelope
with upstream camel-case tags. Asset metadata contains `id`, `mediaType`,
`originPart`, and `byteLength`; asset bytes never enter JSON. Integer conversion
or serialization failures return the fixed, non-content-bearing
`bridge.transport` error.

Before the public graph is constructed, Swift validates:

- schema version and every enum tag;
- checked `UInt64`-to-`Int` conversions and positive heading levels;
- contiguous asset IDs equal to their indexes, exact byte lengths, and every
  image asset reference;
- `headerRows` against the grid height; and
- positive spans, complete rectangles, every covered-slot backlink, and every
  origin's complete set of covered slots.

Malformed transport is a bridge invariant failure, not an upstream document
error.

## Runtime paths

Both operations check cancellation and input size, enqueue one typed closure,
invoke AnyDoc synchronously, copy/validate the selected result, release the
native owner, then check cancellation again.

Markdown conversion enforces `maximumOutputBytes` and validates UTF-8. Document
conversion enforces `maximumDocumentBytes` over manifest plus asset buffers in
both Rust and Swift. The duplicated document bound is intentional defensive
validation across an unsafe binary boundary.

Native parsing cannot be interrupted. Cancellation can prevent queued work from
starting; once parsing is active, conversion and cleanup finish before
`CancellationError` is delivered.

## Application-visible limits and errors

Standard limits are:

- 64 MiB input;
- 16 MiB UTF-8 Markdown; and
- 128 MiB document manifest plus assets.

`AnyDocConversionError.documentTooLarge(maximumBytes:)` represents either
side's structured-result limit. Failures while AnyDoc retains/extracts an asset
remain `.resourceLimit`. Invalid manifest bytes, unknown schema/tags, invalid
numbers, and inconsistent native payloads become `.bridgeFailure`.

PDF is available only through Markdown conversion because pinned AnyDoc 0.2.4
has no PDF document-model parser. OCR-required PDFs preserve sorted unique
one-based page numbers and total page count; no partial Markdown is returned.

## Binary distribution and release boundary

The source implementation is the unreleased 0.2.0/ABI-v3 unit. Its manifest
pins all three artifacts from the published immutable `binary-0.2.0` release,
selecting the URL and checksum for the native host. Repository verification
continues to select a newly built local artifact with
`ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1`. The published 0.1.5 Swift package still pins
the macOS ABI-v2 XCFramework; the 0.2.0 Swift package release remains pending
remote-consumer verification on all three platforms.

macOS arm64 uses a dynamic XCFramework to isolate its Rust runtime. GNU/Linux
x86_64 and aarch64 use target-specific SE-0482 static-library artifact bundles.
Linux packaging merges the raw archive, prefixes every externally visible
defined non-ABI symbol, and leaves only the 12 ABI-v3 functions unprefixed.
Cargo-reported native library requirements are committed and verified rather
than inferred from the developer machine.

The binary release workflow builds all three artifacts natively, opens one
draft, redownloads each asset byte-for-byte on its native architecture, and
repeats verification before publication. Its title and notes record the
embedded AnyDoc version and ABI. The release-only memory gate builds a public
consumer in Release mode, warms each deterministic profile once, then requires
three asset-heavy and three manifest-heavy runs to remain at or below 512 MiB
peak RSS.

Only after the immutable binary release passes are all three artifact URLs and
checksums pinned atomically and ordinary Cargo-free consumers tested. The Swift
package release is a separate authorized operation. See
[the release guide](releasing.md).

## Ownership boundaries and invariants

- Public types, filename-extension alias lookup, FIFO scheduling, limits, and
  cancellation belong to Swift.
- Unsafe borrowing, native-result validation, and exactly-once freeing belong
  to the private Swift adapter and handwritten C ABI.
- Byte detection, parser selection from an optional canonical format, and
  parsing belong to AnyDoc through the Rust engine seam.
- Versioned structural serialization belongs only to the Rust transport DTOs;
  validation and construction of the public graph belong only to Swift.
- Binary selection and bridge visibility belong to `Package.swift`.

The non-negotiable invariants are: native work never blocks the main actor;
mixed operations stay FIFO; C and Rust declarations remain private; no borrowed
buffer outlives its result owner; a panic never crosses C; diagnostics contain
no document content; and consuming builds never invoke Cargo or link an
unpackaged Rust library.
