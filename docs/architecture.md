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
  | length-delimited buffers through the C ABI
  v
AnyDocSwiftBridge (private platform-native artifact)
  |
  | canonical parser selection or anydoc detection
  v
anydoc (pinned upstream engine)
  |
  +--> Markdown bytes
  |
  +--> versioned JSON manifest + separately retained asset buffers
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
| [`Native/include/`](../Native/include/) | Defines the portable C ABI. |
| [`Native/framework/`](../Native/framework/) | Defines the macOS framework metadata and exact export list. |
| [`Native/linux/`](../Native/linux/) | Defines Linux artifact metadata, native linker requirements, and exact export list. |
| [`Rust/anydoc-swift-bridge/`](../Rust/anydoc-swift-bridge/) | Calls anydoc, serializes the versioned document transport, and owns native results. |
| [`Tests/AnyDocSwiftTests/`](../Tests/AnyDocSwiftTests/) | Tests public behavior, transport validation, concurrency, cancellation, ABI shape, and ownership. |
| [`Tests/Fixtures/`](../Tests/Fixtures/) | Holds provenance-recorded upstream fixtures for real conversions. |
| [`Tests/ArtifactSmoke/`](../Tests/ArtifactSmoke/) | Contains Cargo-free C and Swift consumers of packaged artifacts. |
| [`Tests/LinuxRustComposition/`](../Tests/LinuxRustComposition/) | Verifies that a Swift consumer can link the bridge beside another Rust static library. |
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
parser. Passing `nil` delegates detection to anydoc.

`AnyDocFormat(fileExtension:)` owns filename-extension alias lookup in Swift.
It mirrors `Format::from_extension` from the pinned anydoc dependency; recheck
this mapping and its public tests when upgrading the engine. Bare extensions
use ASCII case-insensitive matching, without trimming whitespace, stripping
dots, or extracting filename suffixes. Unknown and non-ASCII input returns
`nil`; `potx` and `potm` are not recognized by the pinned lookup. `.xlsx`
represents the whole upstream Excel
parser family, including `xls`, `xlsm`, and `xlsb`.

This pure lookup performs no file access, content detection, or native calls.
Passing its result to either converter method makes a recognized extension
authoritative; an unrecognized extension delegates detection to anydoc. Callers
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

`AnyDocConverter.engineVersion` exposes the embedded engine and bridge identity.
It validates the ABI and copies the native UTF-8 string. An incompatible bridge
or malformed version buffer produces a fixed fallback string rather than
throwing from this property.

## Private Swift-to-C adapter

[`AnyDocCAdapter`](../Sources/AnyDocSwift/AnyDocCAdapter.swift) concentrates all
unsafe buffer borrowing and native-result ownership. It:

- requires the native ABI to match the adapter's expected ABI version;
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

## C ABI

[`anydoc_swift_bridge.h`](../Native/include/anydoc_swift_bridge.h) declares:

- ABI and embedded-engine version accessors;
- Markdown and document conversion entry points;
- a result-kind discriminator for failure, Markdown, and document payloads;
- Markdown, manifest, indexed asset, error code/message, and OCR metadata
  accessors; and
- one common result free function.

Wrong-payload and out-of-range accessors return no value and reset their
outputs. The indexed asset accessor separately reports success, so a valid
zero-byte asset is not confused with absence. Result payload buffers are
borrowed from the opaque result and remain valid only until the common free
function. The engine-version accessor instead returns static storage that
must never be freed. Callers remain responsible for supplying valid readable
input buffers, writable output pointers, and live result handles.

The full native conversion is enclosed by Rust's `catch_unwind`; a panic becomes
the fixed `bridge.panic` failure instead of unwinding through C. Release builds
therefore retain Rust unwinding.

## Rust integration and document transport

[`engine.rs`](../Rust/anydoc-swift-bridge/src/engine.rs) is safe Rust. It owns
input and Markdown-output limit enforcement, canonical format mapping, calls to
`to_markdown_bytes` and `to_document`, and structured upstream error mapping.
An explicit format is passed directly to anydoc and is authoritative; absence
invokes anydoc's detection.

[`transport.rs`](../Rust/anydoc-swift-bridge/src/transport.rs) owns the versioned
manifest schema and native document-result limit. It destructures the upstream
document, moves each asset byte buffer into the result without cloning it,
serializes temporary structural DTOs with direct `serde`/`serde_json`
dependencies, drops those temporary values, and retains the manifest and assets
separately in the opaque result.

The pinned anydoc grid builder uses empty `Cell::default()` origins with
zero spans for gaps before later-column row spans and for stray covered markers.
The transport represents those single empty positions as 1-by-1 origins.
Cells containing blocks or having only one zero span retain their source
values for Swift's defensive validation.

The manifest has top-level `schemaVersion`, `blocks`, `notes`, and `assets` fields.
Associated-value enums use an adjacent `kind` plus optional `value` envelope
with upstream camel-case tags. Asset metadata contains `id`, `mediaType`,
`originPart`, and `byteLength`; asset bytes never enter JSON. Integer conversion
or serialization failures return the fixed, non-content-bearing
`bridge.transport` error.

[`AnyDocDocumentDecoder`](../Sources/AnyDocSwift/AnyDocDocumentDecoder.swift)
decodes private wire types and validates them before returning the public graph:

- schema version and every enum tag;
- checked `UInt64`-to-`Int` conversions and positive heading levels within
  the upstream `UInt8` range;
- contiguous asset IDs equal to their indexes, exact byte lengths, and every
  image asset reference;
- `headerRows` against the grid height; and
- positive spans within the upstream `UInt32` range, complete rectangles,
  every covered-slot backlink, and every origin's complete set of covered slots.

Malformed transport is a bridge invariant failure, not an upstream document
error.

## Runtime paths

Both operations check cancellation and input size, enqueue one typed closure,
invoke anydoc synchronously, copy/validate the selected result, release the
native owner, then check cancellation again.

Markdown conversion enforces `maximumOutputBytes` and validates UTF-8. Document
conversion enforces `maximumDocumentBytes` over manifest plus asset buffers in
both Rust and Swift. The duplicated document bound is intentional defensive
validation across an unsafe binary boundary.

Native parsing cannot be interrupted. Cancellation can prevent queued work from
starting; once parsing is active, conversion and cleanup finish before
`CancellationError` is delivered. Cancellation observed after native work takes
precedence over both a successful result and a conversion error.

## Application-visible limits and errors

Standard limits are:

- 64 MiB input;
- 16 MiB UTF-8 Markdown; and
- 128 MiB document manifest plus assets.

These are input and result-size limits, not a peak-memory budget. Rust checks
Markdown size after conversion and document size after manifest serialization.
Swift checks Markdown and manifest bounds before copying either buffer, then
checks cumulative document size before copying assets. The release memory
probe separately measures peak RSS.

`AnyDocConversionError.documentTooLarge(maximumBytes:)` represents either
side's structured-result limit. Failures while anydoc retains/extracts an asset
remain `.resourceLimit`. Invalid manifest bytes, unknown schema/tags, invalid
numbers, and inconsistent native payloads become `.bridgeFailure`.

PDF is available only through Markdown conversion because the pinned anydoc
engine has no PDF document-model parser. OCR-required PDFs preserve sorted unique
one-based page numbers and total page count; no partial Markdown is returned.

## Binary distribution and release boundary

[`Package.swift`](../Package.swift) selects a checksum-pinned native artifact
for macOS arm64 or GNU/Linux x86_64 and aarch64. On macOS, artifact selection
depends only on the host OS: SwiftPM can evaluate the manifest in an x86_64
process under Rosetta while building an arm64 target. The macOS binary remains
arm64-only. Ordinary consumers download these packaged artifacts without Cargo.
Repository verification continues to select a newly built local artifact with
`ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1`.

macOS arm64 uses a dynamic XCFramework to isolate its Rust runtime. GNU/Linux
x86_64 and aarch64 use target-specific static-library artifact bundles.
Linux packaging merges the raw archive, prefixes every externally visible
defined non-ABI symbol, and leaves only the declared C exports unprefixed.
Cargo-reported native library requirements are committed and verified rather
than inferred from the developer machine.

Native artifacts are built and verified before a Swift package release pins
them. Qualification includes Cargo-free consumers, Rust-runtime coexistence,
public-interface checks, and a separate peak-memory probe. Publishing the
native artifacts and the Swift package are distinct authorized operations;
existing archives are never rewritten. Exact pins live in the manifests and
lockfile, and the publishing sequence lives in [the release guide](releasing.md).

## Ownership boundaries and invariants

- Public types, filename-extension alias lookup, FIFO scheduling, limits, and
  cancellation belong to Swift.
- Unsafe borrowing, native-result validation, and exactly-once freeing belong
  to the private Swift adapter and handwritten C ABI.
- Byte detection, parser selection from an optional canonical format, and
  parsing belong to anydoc through the Rust engine seam.
- Versioned structural serialization belongs only to the Rust transport DTOs;
  validation and construction of the public graph belong only to Swift.
- Binary selection and bridge visibility belong to `Package.swift`.

The non-negotiable invariants are: native work never blocks the main actor;
mixed operations stay FIFO; C and Rust declarations remain private; no borrowed
buffer outlives its result owner; a panic never crosses C; diagnostics contain
no document content; and consuming builds never invoke Cargo or link an
unpackaged Rust library.
