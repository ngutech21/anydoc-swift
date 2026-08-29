# AnyDocSwift Contributor Instructions

## Authority

- These instructions apply to the whole repository.
- [`docs/architecture.md`](docs/architecture.md) explains the current
  architecture, runtime behavior, repository layout, and invariants.
  [`CONTRIBUTING.md`](CONTRIBUTING.md) explains local setup, verification,
  and artifact generation. [`docs/releasing.md`](docs/releasing.md) contains the
  maintainer-only release flow. Read the relevant sections before changing code
  and verify exact contracts against the implementation and tests; do not
  duplicate those guides here.
- If the overview, pinned upstream source, implementation, or tests conflict,
  stop and surface the conflict. Do not guess, silently weaken a requirement,
  or use the latest upstream branch as authority.
- Keep changes narrow and preserve unrelated worktree changes.

## Current state

- The repository has a verified native artifact and the source implementation
  of the Swift public interface. The crates.io-pinned AnyDoc dependency is
  proven through real conversion fixtures; the C ABI, Swift adapter, ownership,
  scheduling, cancellation, and typed-error behavior are implemented and
  tested against the local XCFramework. The verified immutable release asset is
  integrated as a checksum-pinned SwiftPM binary target, so ordinary root Swift
  builds require neither Cargo nor a locally built Rust library.
- SwiftPM is the root project. Do not create a root `.xcodeproj`; an Xcode
  project may later exist only for the example consumer application.
- `Package.swift` pins the `binary-0.1.4` dynamic-framework release archive and
  keeps its bridge dependency private to the Swift implementation target. A
  native change must publish and verify a new immutable archive before updating
  its URL and checksum together.
- Native artifacts built from this revision embed the project license and the
  generated third-party notices before signing. The immutable `binary-0.1.4`
  archive contains those resources and is not rewritten; publish a new native
  archive for any future resource change.
- Empty layout directories use `.gitkeep`. Remove those placeholders when real
  files land, and update this section as implementation milestones change.

## Design rules

- Implement one deep module behind the public interface in
  `Sources/AnyDocSwift`. Do not add public protocols, factories, registries,
  format-specific converters, or native types.
- Keep the Swift-to-C adapter private. C and Rust declarations must not appear
  in the generated Swift interface.
- Put behavior at the seam that owns it. Follow the responsibility split in
  the architecture guide instead of spreading normalization, scheduling, error
  translation, detection, or ownership rules across layers.
- Internal seams are allowed only for real variation or deterministic fault
  injection. Do not introduce pass-through wrappers or public test hooks.
- Keep unsafe pointer work concentrated at the FFI seam and document the
  lifetime, bounds, and ownership assumptions next to it.

## High-risk changes

- Treat the documented concurrency, cancellation, error-code, panic, and
  allocation rules as indivisible invariants. Changes in these areas require
  focused tests at the same time as the implementation.
- Test observable Swift behavior through the public interface. Test below it
  only for ABI behavior that cannot be observed safely from Swift.
- Use deterministic gates, continuations, or canonical events for concurrency
  tests. Do not synchronize with timing sleeps.
- Never parse human-readable upstream messages or logs to recover structured
  behavior, and never include document contents in diagnostics.

## Reproducibility and artifacts

- Treat the upstream revision, Rust toolchain, `Cargo.lock`, license policy,
  generated notices, snapshots, XCFramework, and checksum as one intentional
  upgrade unit. Do not change one incidentally.
- Clean Rust builds resolve the locked dependency graph from crates.io. Tests
  themselves must not access network resources at runtime.
- Derive native libraries and Apple framework linker settings from the release
  artifact. Do not guess or rely on the developer machine's ambient state.
- Consuming builds must never invoke Cargo or link against an unpackaged local
  Rust build.

## Verification

- Run Rust checks from `Rust/anydoc-swift-bridge` using the configured
  toolchain. Run Swift checks from the repository root.
- Keep Swift sources and the manifest clean under
  `swift format lint --strict --recursive Package.swift Sources Tests`.
- Use focused checks while iterating, then run `just final-check` before handing
  off a completed change. It composes workflow linting, diff validation, and
  the Rust and Swift CI recipes. Do not add no-op scripts or placeholder
  artifacts merely to make that list appear green.
- Run `just update-licenses` after an intentional native dependency change and
  `just check-licenses` to prove the committed notices still match the locked
  Apple Silicon release graph.
- Replace the bootstrap import test with behavioral tests as the public
  interface is implemented.
- Never report an unrun check as passing. Record the exact command, result, and
  any acceptance criterion that remains unverified.

## Documentation and completion

- Keep implementation, the architecture overview, README, project license,
  third-party notices, and examples consistent. A user-approved contract
  change updates them together.
- Report actual artifact architecture, checksum, linker settings, verifier
  results, and remaining gaps; do not claim completion early.
