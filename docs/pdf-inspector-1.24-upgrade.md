# pdf-inspector 1.24.0 upgrade

This native change shipped in the immutable
[`binary-0.2.1` release](https://github.com/ngutech21/anydoc-swift/releases/tag/binary-0.2.1)
on 2026-09-29 and retains anydoc 0.2.4, Rust 1.94.1, ABI 3, macOS 13, and iOS 17.
The current [`Package.swift`](../Package.swift) pins all three published archives
and their verified checksums. A Swift package release containing these pins
remains pending.
The targeted Cargo update moves pdf-inspector 1.17.0 to 1.24.0 and lopdf
0.42.0 to 0.45.0, with the required crypto/compression dependency changes.

Version 1.24.0 embeds the CMap resources. The iOS producer additionally applies
the [reviewed three-line patch](../Native/patches/README.md) to disable the
optional external CMap directory. It rebuilds the pinned Rust standard library
without backtraces while retaining unwinding and panic containment. See the
[privacy audit](ios-required-reason-audit.md) for source provenance, the
experimental producer configuration, and final-binary qualification.

## Licensing

The checksum-verified pdf-inspector clarification includes both its MIT license
and Adobe's BSD-3-Clause CMap license. Generated notices now cover the active
`include_dir`, `include_dir_macros`, and new compression dependencies. All Apple
frameworks also include the verbatim [Rust runtime notices](../Native/licenses/README.md)
before signing. `just check-licenses` verifies the generated notices and the
committed runtime-notice hashes; artifact, Xcode, and simulator checks compare
the packaged copies.

## Reviewed PDF behavior

The predefined Japan1, GB1, and CNS1 fixtures still produce the exact typed
`needsOCR(pages: [1], pageCount: 1)` failure. They qualify a documented
limitation, not successful CMap decoding. The
[decoder investigation](cmap-portability-investigation.md) preserves the
independent expected text and reproducer for future upstream work.

The `text.pdf` Markdown snapshot was reviewed against both rendered source
pages. Unmodified published 1.24.0 with the stock runtime and the rebuilt-std
bridge produce identical output:

- The standalone “Table” heading becomes inline bold text at the end of the
  preceding list. This is an accepted upstream layout regression.
- `B3 C3` is now a separate line, reflecting the final table row.
- The endnote marker moves from a stray leading `i` to `here<sup>i</sup>`,
  matching the source's marker position.

There is no additional extracted-text loss relative to the previous snapshot.
The exact expected Markdown remains asserted; the test was not relaxed to a
substring or non-empty-output check. PDF layout reconstruction remains
approximate for this initial iOS scope.

## Verification

Local producer: Xcode 27.0 (27A266a), Swift 6.4, Rust 1.94.1, macOS arm64.
Both packaged iOS binaries have zero imports matching the committed
required-reason API list. Their native linker requirements remain
`-framework CoreFoundation -lc -lm -liconv -lSystem -lc -lm`.

| Local artifact | Previous 1.17 bytes | New bytes | SHA-256 |
| --- | ---: | ---: | --- |
| XCFramework ZIP | 9,501,544 | 12,917,836 | `d664f670617dfa475da212a7cacd2397da753b921a8774b54b69cdb71ee9c916` |
| macOS arm64 binary | 6,516,960 | 8,586,336 | `db89cf4521d9196a9597a5fa07df3047fe0c33134cc38aaedeb0e2d626962ed9` |
| iOS arm64 binary | 7,552,896 | 9,190,624 | `21f3f31e8023bec341d98d8f549f93eecbc40eacc21996acebb70e146be0cee1` |
| iOS Simulator arm64 binary | 7,521,056 | 9,156,800 | `015946060f15fd3048fae518079faf480a498975360b1c9ce4ebedaa1ad663bb` |

The archive grows by 3,416,292 bytes (36.0%), including the upgraded native
graph, embedded CMaps, and runtime notices. These checksums identify this local
build; subsequent builds and the published immutable release assets have their own
checksums. The privacy fix reduces the stock 1.24.0 archive from 13,553,509 bytes
to 12,917,836 bytes despite the additional runtime notices.

`just final-check` passed on 2026-09-27, including:

- 24 Rust tests with the normal standard library and 24 with the rebuilt
  unwinding-only standard library;
- 76 macOS Swift tests and 76 arm64 iOS Simulator tests, zero failures or skips;
- Rust/Swift/shell/workflow linting, generated licenses and runtime notice hashes;
- artifact structure, signatures, bundled notices, ABI exports, Cargo-free
  consumers, and Rust-runtime coexistence;
- public Swift interface, generic Xcode builds, final arm64 iOS device linking;
- zero required-reason import matches in both final iOS frameworks.

Existing scanned/mixed-page OCR errors and hosted-OCR tests pass. Hosted OCR
uses the deterministic test transport; no live OCR service was contacted.

The [binary release workflow](https://github.com/ngutech21/anydoc-swift/actions/runs/36562629867)
passed all build, downloaded-artifact verification, and publication jobs for
source commit `31fac1bb587d1b57c93a2682f8bb45318a49ea5d`. Hosted qualification
covered Xcode 26.2 / Swift 6.2, Xcode 27.0 / Swift 6.4, and native Linux
x86_64/aarch64, including the release memory gates.

On 2026-09-29, all three downloaded archive SHA-256 hashes matched the release
metadata and candidate manifest. Local `just verify-published-package` passed
with Xcode 27.0 / Swift 6.4: Debug and Release builds, 76 macOS tests, 76 arm64
iOS Simulator tests, generic Xcode builds, and final arm64 iOS-device linkage.
`just verify-artifact-macos` against the downloaded XCFramework and
`bash Scripts/audit-required-reason-apis.sh` also passed, with zero required-reason
import matches in both published iOS slices. The candidate passed
`just final-check`; Linux execution was verified by hosted CI, not locally.

Physical-device execution and App Store submission have not been performed;
the device gate checks arm64 linkage. Native release qualification does not
establish App Store acceptance.
