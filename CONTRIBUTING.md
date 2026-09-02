# Contributing to AnyDocSwift

Thank you for improving AnyDocSwift. Start with the [README](README.md) for the
consumer-facing API and read the [architecture guide](docs/architecture.md)
before changing behavior, native ownership, packaging, or release contracts.
Maintainer-only release procedures are documented separately in
[`docs/releasing.md`](docs/releasing.md).

Keep changes narrow and preserve unrelated worktree changes. If the
architecture guide, pinned upstream source, implementation, or tests disagree,
surface the conflict instead of guessing or silently weakening a requirement.

## Development requirements

Development and native artifact verification require either Apple Silicon with
macOS 13 or later, or a native `x86_64`/`aarch64` GNU/Linux host. Install:

- Swift 6.2 or later and, on macOS, the Xcode command-line tools;
- the toolchain pinned by [`rust-toolchain.toml`](rust-toolchain.toml);
- [`just`](https://github.com/casey/just);
- `jq`;
- Python 3 (for deterministic release memory fixtures);
- `actionlint`;
- `shellcheck`; and
- `cargo-about 0.9.1`.

Linux artifact builds additionally require Docker. The supported entry points
build and run the digest-pinned `swift:6.2.4-amazonlinux2` environment so the
result is produced and audited against the glibc 2.26 baseline. Builds are
native-only: run the x86_64 artifact on x86_64 and the aarch64 artifact on
aarch64.

SwiftPM is the root project. Do not create a root Xcode project for package
development.

## Build and test

Run commands from the repository root unless a command says otherwise:

```sh
# Show every supported task.
just --list

# Run Rust formatting, shell linting, builds, tests, and license checks.
just ci-rust

# Build and verify the host artifact, lint and build Swift, and run Swift tests.
just ci-swift

# Run both suites.
just ci

# Run workflow and diff linting followed by every Rust and Swift CI check.
just final-check

# Regenerate or verify notices for the locked native dependency graph.
just update-licenses
just check-licenses

# Build, package, and verify the native release archive for this host.
just artifact

# Run the non-default Release memory qualification used by binary releases.
just memory-probe

# Run platform-specific artifact paths explicitly.
just artifact-macos
just artifact-linux-container
```

Use focused checks while iterating. Run `just final-check` before handing off a
completed change, and report the exact result of every claimed verifier.

## Test coverage

Tests are organized around the seams they protect:

- Rust tests cover every transport variant, schema output, canonical/automatic
  format selection, limits, error codes, result-kind/accessor invariants, empty
  assets, repeated references, panic containment, and the exported ABI.
- Swift adapter/decoder tests cover ABI and UTF-8 validation, error translation,
  both output bounds, unknown schema/tags, invalid numbers/tables/assets,
  malformed payload kinds, defensive copies, and exactly-once cleanup.
- Public actor tests cover both result modes, shared input checks, mixed FIFO
  execution, independent concurrency, main-actor responsiveness, and queued or
  active cancellation.
- Public format tests cover all pinned extension aliases, ASCII case matching,
  rejected inputs, unchanged raw values, and real conversions using lookup
  results in both output modes. Keep this table aligned with the pinned
  upstream `Format::from_extension` when upgrading AnyDoc.
- Artifact smoke tests prove that packaged C and Swift consumers can link and
  run without Cargo on `PATH`; artifact and Xcode-package verification also
  prove that the project license and third-party notices survive packaging.
- macOS artifact verification also links the dynamic framework beside an
  independent unwind-enabled Rust static library and runs both ABIs.
- Linux verification checks the exact ELF architecture, artifact metadata,
  module map, ABI/engine versions, 12 public functions, symbol namespace,
  native-library report, SwiftPM artifact audit, and archive checksum.
- A generated Linux SwiftPM consumer links AnyDocSwift with a second
  unwind-enabled Rust static library and performs a real conversion, proving
  that the two module maps and Rust runtimes do not collide.
- The Xcode package smoke proves that `ProcessXCFramework` places the bridge in
  its named framework product rather than a shared `include/module.modulemap`
  output.
- A generated public symbol graph proves that no C/Rust bridge declaration is
  exported by the Swift module.
- The non-default binary-release qualification builds a public consumer in
  Release mode, warms deterministic asset-heavy and manifest-heavy DOCX inputs,
  then checks three runs of each against a 512 MiB peak-RSS ceiling.
- Real RTF, CSV, PDF, structure-rich DOCX, and EPUB table fixtures exercise the
  pinned AnyDoc engine. Their provenance and hashes are recorded in
  [`Tests/Fixtures/README.md`](Tests/Fixtures/README.md).

Tests themselves do not access the network. A clean Cargo build may need
network access once to resolve the locked crates.io dependency graph.

## Native artifacts

`just artifact` selects the native packaging and verification path for the
current host.

### macOS

`just artifact-macos`:

1. Build the Rust `staticlib` for `aarch64-apple-darwin` with the pinned Rust
   toolchain and macOS 13 deployment target as an internal intermediate.
2. Verify that the committed third-party notices match the target-filtered,
   locked Cargo graph.
3. Use Cargo's reported native link requirements to link that archive into a
   versioned, non-mergeable dynamic framework with a controlled `@rpath`
   install name and exactly 12 exported C symbols.
4. Copy the project license and third-party notices into the framework before
   signing it.
5. Package the framework as an XCFramework ZIP and compute its SwiftPM
   checksum.
6. Reopen and validate the package, including its platform, architecture,
   Mach-O type, install name, dependencies, bundle structure, signature,
   license resources, exported ABI, and C and Swift smoke consumers.
7. Link and run it beside an independent unwind-enabled Rust static library,
   proving that the dynamic framework keeps its Rust runtime isolated.

The ignored output is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`.

### GNU/Linux

`just artifact-linux-container` builds the pinned container environment and
runs the native Linux artifact path inside it. The direct `artifact-linux`,
`build-artifact-linux`, `package-artifact-linux`, `audit-artifact-linux`,
`smoke-artifact-linux`, and `verify-artifact-linux` recipes are intended for
that baseline environment and reject a different glibc version or a target
triple that does not match the host.

For the current native architecture, the path:

1. builds the locked AnyDoc 0.2.4 bridge with Rust 1.94.1 and
   `panic = "unwind"`;
2. captures Cargo's ordered `native-static-libs` report and rejects any drift
   from [`Native/linux/native-static-libs.txt`](Native/linux/native-static-libs.txt);
3. merges the archive into one relocatable ELF object, then uses the pinned
   `llvm-objcopy` to deterministically prefix every externally visible defined
   symbol except the 12 ABI-v3 functions and verifies that no old internal
   reference remains;
4. packages the archive, portable C header, plain module map, license, notices,
   link report, and symbol map as one target-specific `staticLibrary` artifact
   bundle;
5. verifies the exact GNU target, contents, symbols, ABI and engine versions,
   native link closure, and checksum;
6. requires `swift package experimental-audit-binary-artifact` to accept the
   final ZIP (the x86_64 invocation supplies an audit-only Clang library path
   because the pinned image exposes `libm.a` as a GNU linker script rather than
   an object archive); and
7. runs debug/release Swift builds, public-interface extraction, the full test
   suite, and the independent
   two-Rust-library composition consumer with Cargo removed from `PATH`.

The ignored outputs are:

- `.build/artifacts/AnyDocSwiftBridge-x86_64-unknown-linux-gnu.artifactbundle.zip`
- `.build/artifacts/AnyDocSwiftBridge-aarch64-unknown-linux-gnu.artifactbundle.zip`

Local Swift recipes set `ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1` to select the verified
platform artifact through the package's private binary-target seam. On macOS
that path is an XCFramework; on Linux it is an artifact bundle. This switch is
for repository validation, not ordinary package consumers.

## Dependency and ABI changes

Treat the upstream revision, Rust toolchain, `Cargo.lock`, license policy,
generated notices, fixtures, platform artifacts, and checksums as one
intentional upgrade unit.

- Public behavior, scheduling, or cancellation changes require public actor
  tests.
- Error-presentation changes belong in `AnyDocConversionError.swift`; native
  code mapping remains in `AnyDocCAdapter.swift`.
- Pointer, result-ownership, detection, or AnyDoc integration changes require
  focused Rust and Swift-adapter tests.
- An ABI change must update the C header, Rust exports, Swift adapter, ABI
  version, symbol-graph and memory gates, smoke tests, and native binary release
  together. ABI v3 belongs to one 0.2.0 artifact set; do not publish an
  intermediate subset.
- An AnyDoc upgrade must update the exact Cargo dependency, lockfile, embedded
  version and revision, fixture expectations, generated third-party notices,
  and released platform artifacts intentionally.
- Linker settings must come from Cargo's report for the built artifact rather
  than assumptions about a developer machine. Any report change must update
  the verifier and manifest as one reviewed change.

Run `just update-licenses` after an intentional native dependency change and
commit the resulting `THIRD_PARTY_NOTICES.txt`. Run `just check-licenses` to
prove that it still matches the locked native release graph.
