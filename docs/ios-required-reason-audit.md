# iOS required-reason API audit

Audit date: 2026-09-27; published-artifact verification: 2026-09-29. Both iOS
frameworks in the immutable
[`binary-0.2.1` release](https://github.com/ngutech21/anydoc-swift/releases/tag/binary-0.2.1)
pass the unchanged import audit with zero matched required-reason APIs. No privacy
declaration or import exception is needed for these native binaries. The current
[`Package.swift`](../Package.swift) pins this release's URLs and verified checksums;
publication of a Swift package containing those pins remains pending. Release
verification and the remaining Apple validation limits are recorded in the
[upgrade report](pdf-inspector-1.24-upgrade.md).

The committed comparison list is
[`Native/privacy/required-reason-imports.txt`](../Native/privacy/required-reason-imports.txt).
It was checked against Apple's current
[required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
The import audit remains a hard failure for any matched symbol. No privacy
manifest or import allowlist has been added.

## Why the stock dependencies fail

The current registry lockfile contains:

```text
anydoc-swift-bridge 0.1.0
  -> anydoc 0.2.4
    -> pdf-inspector 1.24.0
```

Version 1.17.0 looked for native CMaps under its build-time Cargo directory and
imported `stat` and `fstat`. Version 1.24.0 embeds those resources on every target,
removing that build-directory dependency. The stock 1.24.0 framework still
imports `fstat`; embedding resources alone does not resolve the privacy audit.

Two source paths explain the remaining file metadata access:

```text
anydoc::formats::pdf::to_markdown
  -> pdf_inspector::process_pdf_mem
    -> tounicode::read_builtin_cmap_file
      -> read_bcmap_override
        -> std::fs::read -> fstat

Rust backtrace symbolization
  -> dyld image enumeration and Mach-O/dSYM lookup
    -> std::backtrace_rs::symbolize::gimli::mmap
      -> File::metadata -> fstat
```

The optional PDF override reads an arbitrary `PDF_INSPECTOR_BCMAPS_DIR` path.
Rust 1.94.1's symbolizer enumerates loaded images, including system libraries,
and opens their files or neighboring debug resources. Its source contains no
constraint limiting those accesses to application containers. The earlier
1.17.0 audit also identified a `stat` call in Rust's filesystem helpers.

## Why a declaration is insufficient

Apple requires approved reasons to accurately cover each use, including uses
inside an SDK's own dynamic library. An SDK cannot rely on its host application's
manifest. See [Apple's declaration requirements](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

The current file-metadata reasons do not cover all the stock paths:

| Reason | Scope and mismatch |
| --- | --- |
| `DDA9.1` | Displaying file timestamps; AnyDocSwift does not do this. |
| `C617.1` | App, app-group, or CloudKit container files; system images and arbitrary overrides are not restricted to those containers. |
| `3B52.1` | Files or directories explicitly authorized by the user; automatic symbolization is not such an access. |
| `0A2A.1` | SDK wrappers for metadata APIs, with no SDK use of the resulting information; internal conversion and symbolization do not fit. |

This assessment follows the [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
not merely whether timestamps happen to be used. `fstat` also returns file size,
and remains a covered API. The resolution removes the uncovered paths.

## Producer changes

The narrow [CMap patch](../Native/patches/pdf-inspector-1.24.0-ios-cmaps.patch)
disables the optional filesystem override on iOS, including the simulator.
Embedded resources remain available. Its import, function, and caller are
excluded together; other targets retain upstream behavior. This does not fix
the separate [CMap decoder limitation](cmap-portability-investigation.md).

The [preparation script](../Scripts/prepare-ios-pdf-inspector.py) verifies the
published crate archive and exact source hashes, stages the patch under `.build`,
and emits Cargo's supported `paths` configuration. The registry lockfile is
unchanged by staging; metadata identifies the actual source path. There is no
upstream fork, shared-cache mutation, or compiler wrapper. Patch provenance is
documented in [Native/patches](../Native/patches/README.md).

The [iOS producer](../Scripts/build-ios-bridge.sh) rebuilds Rust 1.94.1's standard
library with `-Zbuild-std=std,panic_unwind` and
`-Zbuild-std-features=panic-unwind`. Omitting the `backtrace` feature removes the
symbolizer; `panic = "unwind"` and the bridge's `catch_unwind` boundary remain.
Caught panics still return the fixed `bridge.panic` error. Native Rust backtraces
are unavailable in these iOS binaries.

This is an explicit producer maintenance tradeoff:
[Cargo's `build-std`](https://doc.rust-lang.org/cargo/reference/unstable.html#build-std)
is experimental, and enabling it on the pinned stable compiler uses
[`RUSTC_BOOTSTRAP=1`](https://doc.rust-lang.org/unstable-book/compiler-environment-variables/RUSTC_BOOTSTRAP.html).
Rust's normal stability guarantee does not cover these features. Both the exact
compiler version and its independent standard-library lockfile checksum are
checked; any toolchain change requires requalification. SwiftPM consumers use
the packaged framework and do not run Cargo or inherit these producer settings.

The standard-library build has additional locked dependencies outside the
bridge's ordinary Cargo graph. Their license texts and notices must be included
in the generated framework notices; see [Native/licenses](../Native/licenses/README.md).

## Verification and remaining gates

`just test-ios-rust-runtime` passed all 24 bridge tests on macOS with the rebuilt
standard library, zero failures or skips, and the required private panic test
present. This establishes that removing backtraces preserves panic containment;
it is a macOS test of the iOS producer's standard-library features. The packaged
device and simulator frameworks also pass the final import audit. Their normal
linking and runtime qualification is recorded separately in the upgrade report.

```sh
just test-ios-rust-runtime
just build-artifact-macos
just verify-artifact
just audit-required-reason-apis
just final-check
```

The audit writes per-slice results and their union under
`.build/artifact/verified/required-reason-imports.txt`. Both final iOS frameworks
must have zero matches. Packaging, signing, notices, device linking, simulator
execution, conversion behavior, and panic containment also require their normal
checks; an empty import report alone does not prove these contracts.
