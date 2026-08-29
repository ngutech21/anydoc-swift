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

Development and native artifact verification currently require Apple Silicon
and macOS 13 or later. Install:

- Swift 6.1 or later and the Xcode command-line tools;
- the toolchain pinned by [`rust-toolchain.toml`](rust-toolchain.toml);
- [`just`](https://github.com/casey/just);
- `jq`;
- `actionlint`; and
- `cargo-about 0.9.1`.

SwiftPM is the root project. Do not create a root Xcode project for package
development.

## Build and test

Run commands from the repository root unless a command says otherwise:

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

# Regenerate or verify notices for the locked native dependency graph.
just update-licenses
just check-licenses

# Build, package, and verify the native release archive.
just artifact
```

Use focused checks while iterating. Run `just final-check` before handing off a
completed change, and report the exact result of every claimed verifier.

## Test coverage

Tests are organized around the seams they protect:

- Rust tests cover raw-buffer validation, detection, limits, error codes,
  result invariants, panic containment, and the exported ABI.
- Swift adapter tests cover ABI and UTF-8 validation, error translation,
  output bounds, malformed native results, and result cleanup.
- Public actor tests cover normalization, limits, FIFO execution, independent
  concurrency, main-actor responsiveness, and cancellation at each stage.
- Artifact smoke tests prove that packaged C and Swift consumers can link and
  run without Cargo on `PATH`; artifact and Xcode-package verification also
  prove that the project license and third-party notices survive packaging.
- The Xcode package smoke proves that `ProcessXCFramework` places the bridge in
  its named framework product rather than a shared `include/module.modulemap`
  output.
- Real RTF and CSV fixtures exercise the pinned AnyDoc engine. Their provenance
  and hashes are recorded in [`Tests/Fixtures/README.md`](Tests/Fixtures/README.md).

Tests themselves do not access the network. A clean Cargo build may need
network access once to resolve the locked crates.io dependency graph.

## Native artifacts

`just artifact` performs the native packaging and verification path:

1. Build the Rust `staticlib` for `aarch64-apple-darwin` with the pinned Rust
   toolchain and macOS 13 deployment target as an internal intermediate.
2. Verify that the committed third-party notices match the target-filtered,
   locked Cargo graph.
3. Use Cargo's reported native link requirements to link that archive into a
   versioned, non-mergeable dynamic framework with a controlled `@rpath`
   install name and exactly eight exported C symbols.
4. Copy the project license and third-party notices into the framework before
   signing it.
5. Package the framework as an XCFramework ZIP and compute its SwiftPM
   checksum.
6. Reopen and validate the package, including its platform, architecture,
   Mach-O type, install name, dependencies, bundle structure, signature,
   license resources, exported ABI, and C and Swift smoke consumers.

The ignored output is
`.build/artifacts/AnyDocSwiftBridge.xcframework.zip`. Local Swift recipes set
`ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1` to select the verified local XCFramework
through the package's private binary-target seam. This switch is for repository
validation, not package consumers.

## Dependency and ABI changes

Treat the upstream revision, Rust toolchain, `Cargo.lock`, license policy,
generated notices, fixtures, XCFramework, and checksum as one intentional
upgrade unit.

- Public behavior, scheduling, or cancellation changes require public actor
  tests.
- Error-presentation changes belong in `AnyDocConversionError.swift`; native
  code mapping remains in `AnyDocCAdapter.swift`.
- Pointer, result-ownership, detection, or AnyDoc integration changes require
  focused Rust and Swift-adapter tests.
- An ABI change must update the C header, Rust exports, Swift adapter, ABI
  version, smoke tests, and native binary release together.
- An AnyDoc upgrade must update the exact Cargo dependency, lockfile, embedded
  version and revision, fixture expectations, generated third-party notices,
  and released XCFramework intentionally.
- Linker settings must come from the built artifact rather than assumptions
  about a developer machine.

Run `just update-licenses` after an intentional native dependency change and
commit the resulting `THIRD_PARTY_NOTICES.txt`. Run `just check-licenses` to
prove that it still matches the locked Apple Silicon release graph.
