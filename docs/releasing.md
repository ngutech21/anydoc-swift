# Releasing AnyDocSwift

Publishing, tagging, and uploading are maintainer-only actions and require
separate authorization. Editing this guide or preparing a release does not
authorize publication.

## Release model

Each release uses two immutable tags:

- `binary-X.Y.Z` publishes three native archives:
  `AnyDocSwiftBridge.xcframework.zip`,
  `AnyDocSwiftBridge-x86_64-unknown-linux-gnu.artifactbundle.zip`, and
  `AnyDocSwiftBridge-aarch64-unknown-linux-gnu.artifactbundle.zip`.
- `X.Y.Z` publishes the Swift package manifest that selects and checksum-pins
  the appropriate platform archive.

Both workflows accept `MAJOR.MINOR.PATCH` without a leading `v`, run from
`master`, and refuse an existing tag or release. The current Swift release
workflow requires all three manifest URLs to reference `binary-X.Y.Z` for the
same requested Swift package version. It does not support publishing a new
Swift version against an older native release.

## Prerequisites

- Follow the [development setup](../CONTRIBUTING.md#development-requirements).
  Toolchain and container pins are defined in
  [rust-toolchain.toml](../rust-toolchain.toml),
  [Native/linux/Dockerfile](../Native/linux/Dockerfile), and the release workflows.
- Enable immutable releases for the repository. The binary workflow verifies
  this before creating its release tag.
- Configure the `binary-release` GitHub environment and make
  `RELEASE_SETTINGS_TOKEN` available to its draft job with repository
  `Administration: read` permission.
- Keep the workflow job permissions intact: draft creation, publication, and
  draft-asset downloads use `contents: write`. The binary workflow otherwise
  defaults to `contents: read`.
- Build and verify on native macOS arm64, GNU/Linux x86_64, and GNU/Linux
  aarch64 hosts. Native cross-compilation is unsupported.

## Release checklist

### 1. Prepare the candidate

Choose an unused `X.Y.Z` and merge the intended implementation and tooling
changes into `master`. Keep the existing manifest artifact pins until the new
native release has passed verification.

For dependency or ABI changes, follow
[Dependency and ABI changes](../CONTRIBUTING.md#dependency-and-abi-changes).
Keep the bridge's embedded engine identity and ABI consistent with
`EMBEDDED_ANYDOC_VERSION` and `BRIDGE_ABI_VERSION` in both release workflows.
Update the complete Swift/C/Rust contract and its tests together; do not release
an intermediate artifact that implements only part of the contract.

Update affected API and behavior documentation with the implementation. Keep
unpublished functionality identified as pending; release numbers belong in the
README and compatibility record, not the architecture guide or `AGENTS.md`.

Run `just final-check` from the repository root and resolve failures before
starting publication.

### 2. Publish and verify the native artifacts

With explicit maintainer authorization, run
[Release Binary](../.github/workflows/release-binary.yml) from `master` with
the chosen version.

The workflow builds and checks all three native artifacts before creating a
tag and draft release. It then downloads each draft asset on its native
architecture, checks its bytes and SHA-256 checksum against the original build,
and repeats artifact verification. Linux also repeats Swift builds, tests, and
Rust-runtime coexistence checks against the downloaded artifact.

Both original and downloaded artifacts undergo the Release memory qualification
defined in [Scripts/memory-probe.sh](../Scripts/memory-probe.sh). The workflow
publishes only after all native verification jobs succeed, then verifies that
the release is public and immutable.

Wait for the complete workflow to succeed. Record the native source commit,
release URL, three archive URLs and checksums, and verification results.
Draft creation, uploads, and downloads use the release ID returned by the API;
do not rediscover a draft by assuming it appears in the public release list.

### 3. Pin the published artifacts

In one change, update [Package.swift](../Package.swift) with all three URLs
from `binary-X.Y.Z` and their verified checksums:

- the macOS XCFramework for macOS arm64;
- the x86_64 artifact bundle for GNU/Linux x86_64; and
- the aarch64 artifact bundle for GNU/Linux aarch64.

Preserve `ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1` for repository verification and the
manifest's ability to run in both arm64 and x86_64 macOS processes. The macOS
binary remains arm64-only. Merge the pin update into `master`. Do not change the
native implementation after publishing its artifacts; further native changes
require a new native release.

### 4. Verify the Swift package candidate

Run `just final-check` again with the updated manifest. Then verify the
candidate checkout on macOS arm64 and both native Linux architectures using
the environments configured in
[Release Swift Package](../.github/workflows/release-swift.yml).

For these consumer checks, unset `ANYDOC_SWIFT_USE_LOCAL_BRIDGE`, keep Cargo
and Rust off `PATH`, and do not inject headers or local library paths:

```sh
swift package reset
swift build
swift build -c release
swift test
```

On macOS, the workflow invokes Swift through `xcrun`; Linux uses its pinned
Swift container. These checks must download the published native artifacts
selected by the candidate manifest. They run before the Swift tag exists.

Record the candidate commit, platform, architecture, archive URL, checksum,
exact commands, and results. Keep the candidate's native contract and test
expectations consistent with the published artifacts.

### 5. Publish the Swift package and finish documentation

With explicit maintainer authorization, run
[Release Swift Package](../.github/workflows/release-swift.yml) from `master`
with the same `X.Y.Z`.

The workflow validates the manifest pins and embedded metadata, rechecks the
complete macOS validation gate, and builds and tests the published binary
dependency without Cargo on all three platforms. It creates the Swift tag and
release only after those jobs succeed, then verifies the tag's commit and that
the release is public, stable, and immutable.

After the workflow succeeds:

- Update the README's installation version and any release-specific guidance.
- Update the example dependency and regenerate its resolved dependency file
  now that the Swift tag exists; verify that the example resolves and runs.
- Add the released package's engine, ABI, and export information to the
  compatibility record below.
- Remove any pending-release wording for the functionality just published.
- Retain links to both workflow runs and their verification evidence.

## Compatibility record

| Swift package | Embedded anydoc | Bridge ABI | Native exports |
| --- | --- | --- | --- |
| `0.1.5` | `0.2.4` | 2 | 9 |
| `0.2.0` | `0.2.4` (`42bf1c5…`) | 3 | 12 |

## Immutability and interrupted releases

Treat the upstream revision, Rust toolchain, `Cargo.lock`, license policy,
generated notices, platform metadata, native archives, and checksums as one
release unit. Any native code, dependency, bundled resource, symbol map, linker
requirement, or metadata change requires a new `binary-X.Y.Z` release and new
checksums.

If a run fails after creating a tag or draft, inspect the existing release and
completed jobs before retrying: a fresh dispatch refuses existing tags and
releases. Never rewrite a published asset or tag, or replace a published
archive in place.
