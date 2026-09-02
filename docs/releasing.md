# Releasing AnyDocSwift

Publishing, tagging, and uploading are maintainer-only actions and require
separate authorization. Never rewrite a published asset or tag.

## Release model

AnyDocSwift 0.2 and later use two immutable releases:

- `binary-X.Y.Z` publishes three native archives:
  `AnyDocSwiftBridge.xcframework.zip`,
  `AnyDocSwiftBridge-x86_64-unknown-linux-gnu.artifactbundle.zip`, and
  `AnyDocSwiftBridge-aarch64-unknown-linux-gnu.artifactbundle.zip`.
- `X.Y.Z` publishes the Swift package manifest that selects and checksum-pins
  the appropriate archive for the native host.

The native release must be published and independently verified before the
Swift package can point to it. Both workflows accept `MAJOR.MINOR.PATCH`
without a leading `v`, must run from `master`, and refuse an existing tag or
release.

## Required release-safe sequence

### 1. Merge artifact tooling without a Linux release claim

Land the Swift 6.2 manifest, Linux artifact tooling, local-artifact tests, and
native Linux CI first. At this stage:

- macOS ordinary consumers continue to use the checksum-pinned
  `binary-0.1.5` dynamic XCFramework;
- Linux CI sets `ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1` and consumes the verified
  local artifact bundle; and
- Linux manifest evaluation without that explicit local switch fails with a
  message explaining that the binary release is not yet pinned.

Do not add placeholder URLs or checksums and do not describe Linux as released
support during this phase.

### 2. Publish and independently verify `binary-X.Y.Z`

With explicit maintainer authorization, run the
[Release Binary](../.github/workflows/release-binary.yml) workflow. For each
Linux job, the runner architecture must match the artifact triple; native
cross-compilation is not supported.

The workflow:

1. validates the request and refuses an existing release or tag;
2. builds and verifies macOS arm64, Linux x86_64, and Linux aarch64 in parallel;
3. uses Xcode 26.2 for macOS and the digest-pinned Swift 6.2.4 Amazon Linux 2
   image with Rust 1.94.1 for Linux;
4. creates one draft release containing the three archives and their individual
   SHA-256 checksums;
5. redownloads every draft asset on its native architecture, compares its bytes
   and checksum with the build output, and reruns artifact, audit, smoke,
   package, fixture, and Rust-runtime coexistence verification; and
6. publishes only after all three native reverification jobs succeed, then
   confirms that the release is immutable.

Record the three checksums from the release notes. Do not update
`Package.swift` before this workflow succeeds.

### 3. Atomically pin all released artifacts

In one change, update `Package.swift` so manifest evaluation selects:

- the macOS XCFramework URL and checksum on macOS arm64;
- the x86_64 artifact-bundle URL and checksum on GNU/Linux x86_64; and
- the aarch64 artifact-bundle URL and checksum on GNU/Linux aarch64.

Remove the temporary Linux local-only failure while preserving
`ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1` for repository verification. Keep unsupported
hosts explicit. Update the example package to the new Swift package version
only after that version is ready to tag.

### 4. Verify ordinary remote consumers without Cargo

Run the complete local gate:

```sh
just final-check
```

Then test ordinary consumers on macOS arm64 and both native Linux
architectures. Do not set `ANYDOC_SWIFT_USE_LOCAL_BRIDGE`, inject headers, or
leave Cargo/Rust on `PATH`:

```sh
swift package reset
swift build
swift build -c release
swift test
```

These checks must download the published artifact selected by `Package.swift`.
Record each platform, architecture, URL, checksum, and verifier result.

### 5. Update documentation and publish `X.Y.Z`

Only after remote-consumer verification succeeds, update the README,
architecture guide, contributor instructions, example, and current-state
documentation to describe released Linux support.

Run the [Release Swift Package](../.github/workflows/release-swift.yml) workflow.
It rechecks the full macOS gate and ordinary Cargo-free consumers on macOS,
Linux x86_64, and Linux aarch64 before publishing the Swift tag and immutable
GitHub release.

## Immutability

Treat the upstream revision, Rust toolchain, `Cargo.lock`, license policy,
generated notices, platform metadata, native archives, and checksums as one
release unit. Any native code, dependency, bundled resource, symbol map, linker
requirement, or metadata change requires a new `binary-X.Y.Z` release and new
checksums. Never alter an existing native archive in place.
