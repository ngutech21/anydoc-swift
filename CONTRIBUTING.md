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
and macOS 13 or later. The complete iOS gate also requires an installed iOS
Simulator runtime that supports the iPhone 16e device type. Install:

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
- Artifact smoke tests prove that packaged C and Swift bridge consumers link
  for macOS, physical-device iOS, and iOS Simulator with Cargo absent from
  `PATH`; the macOS consumers also execute.
- Xcode package smokes build generic macOS, iOS-device, and iOS-simulator
  destinations. They prove that `ProcessXCFramework` selects the matching
  slice, preserves signatures and license resources, and places the bridge in
  its named framework product rather than a shared `include/module.modulemap`
  output. A public `AnyDocSwift` consumer is final-linked for a physical iOS
  device.
- The complete public Swift test target runs on a temporary arm64 iPhone 16e
  simulator using the newest available installed iOS runtime. The test recipe
  creates, boots, and deletes only that temporary device; no usable runtime is
  a hard failure.
- Real RTF and CSV fixtures exercise the pinned AnyDoc engine. Their provenance
  and hashes are recorded in [`Tests/Fixtures/README.md`](Tests/Fixtures/README.md).

Tests themselves do not access the network. A clean Cargo build may need
network access once to resolve the locked crates.io dependency graph.

## Native artifacts

`just artifact` performs the native packaging and verification path:

1. Build separate Rust `staticlib` intermediates for
   `aarch64-apple-darwin`, `aarch64-apple-ios`, and
   `aarch64-apple-ios-sim` with the pinned toolchain and deployment targets.
2. Verify that the committed third-party notices match the union of the three
   target-filtered locked Cargo graphs.
3. Use each target's independently captured Cargo linker requirements to link
   a macOS 13 framework, a flat iOS 15 device framework, and a flat iOS 15
   simulator framework. Every variant is non-mergeable and exports exactly
   the eight committed ABI symbols.
4. Copy the project license and third-party notices into each platform-correct
   framework layout, then ad-hoc sign each framework variant.
5. Package the three frameworks as one unsigned XCFramework container, ZIP it,
   and compute its SwiftPM checksum.
6. Reopen and validate all slices, including identifiers, platforms,
   architectures, Mach-O metadata, install names, dependencies, bundle
   structure, signatures, resources, exported ABI, and direct consumers.
7. Build generic package destinations, final-link the public device consumer,
   and run real conversions on a temporary arm64 iOS Simulator.
8. Compare the final iOS imports with the committed snapshot of Apple's
   required-reason API list. Any match is a hard failure until its concrete
   call path has an accurate approved reason or is removed upstream.

The currently known `_stat` and `_fstat` paths are recorded in the
[iOS required-reason audit](docs/ios-required-reason-audit.md).

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
prove that it still matches the union of the locked macOS, iOS-device, and
iOS-simulator release graphs.
