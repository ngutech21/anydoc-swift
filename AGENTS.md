# AnyDocSwift Contributor Instructions

## Authority

- These instructions apply to the whole repository.
- [`docs/spec.md`](docs/spec.md) is the source of truth for product scope,
  public behavior, ABI, layout, tests, documentation, and acceptance. Read the
  relevant section before changing code; do not duplicate those requirements
  here.
- If the specification, pinned upstream source, or implementation conflict,
  stop and surface the conflict. Do not guess, silently weaken a requirement,
  or use the latest upstream branch as authority.
- Keep changes narrow and preserve unrelated worktree changes.

## Current state

- The repository is at the bootstrap stage. The Swift package and Rust
  `staticlib` crate compile, but the converter, C ABI, AnyDoc dependency,
  fixtures, scripts, and XCFramework are not implemented yet.
- SwiftPM is the root project. Do not create a root `.xcodeproj`; an Xcode
  project may later exist only for the example consumer application.
- `Package.swift` intentionally has no binary target while the artifact is
  absent. Add the local binary target and its private Swift-target dependency
  only when a real XCFramework has been built and verified.
- Empty layout directories use `.gitkeep`. Remove those placeholders when
  real files land, and update this section as implementation milestones change.

## Design rules

- Implement one deep module behind the exact public interface in section 5 of
  the specification. Do not add public protocols, factories, registries,
  format-specific converters, or native types.
- Keep the Swift-to-C adapter private. C and Rust declarations must not appear
  in the generated Swift interface.
- Put behavior at the seam that owns it. Follow the responsibility split in
  sections 4, 6, and 8 instead of spreading normalization, scheduling, error
  translation, detection, or ownership rules across layers.
- Internal seams are allowed only for real variation or deterministic fault
  injection. Do not introduce pass-through wrappers or public test hooks.
- Keep unsafe pointer work concentrated at the FFI seam and document the
  lifetime, bounds, and ownership assumptions next to it.

## High-risk changes

- Treat the concurrency, cancellation, error-code, panic, and allocation rules
  in sections 6–8 as indivisible invariants. Changes in these areas require
  focused tests at the same time as the implementation.
- Test observable Swift behavior through the public interface. Test below it
  only for ABI behavior that cannot be observed safely from Swift.
- Use deterministic gates, continuations, or canonical events for concurrency
  tests. Do not synchronize with timing sleeps.
- Never parse human-readable upstream messages or logs to recover structured
  behavior, and never include document contents in diagnostics.

## Reproducibility and artifacts

- Treat the upstream revision, Rust toolchain, `Cargo.lock`, snapshots,
  licenses, XCFramework, and checksum as one intentional upgrade unit. Do not
  change one incidentally.
- A warm Cargo cache is not proof of offline operation. Verification intended
  to be offline must also work with the repository's declared dependency
  sources available from a clean environment.
- Derive native libraries and Apple framework linker settings from the release
  artifact. Do not guess or rely on the developer machine's ambient state.
- Consuming builds must never invoke Cargo or link against an unpackaged local
  Rust build.

## Verification

- Run Rust checks from `Rust/anydoc-swift-bridge` using the configured
  toolchain. Run Swift checks from the repository root.
- Keep Swift sources and the manifest clean under
  `swift format lint --strict --recursive Package.swift Sources Tests`.
- Use focused checks while iterating, then run every command in section 12 of
  the specification once the corresponding implementation exists. Do not add
  no-op scripts or placeholder artifacts merely to make that list appear green.
- Replace the bootstrap import test with behavioral tests as the public
  interface is implemented.
- Never report an unrun check as passing. Record the exact command, result, and
  any acceptance criterion that remains unverified.

## Documentation and completion

- Keep implementation, the specification, README, notices, and examples
  consistent. A user-approved contract change updates them together.
- Completion is defined only by sections 14 and 15 of the specification.
  Report actual artifact architecture, checksum, linker settings, verifier
  results, and remaining gaps; do not claim completion early.
