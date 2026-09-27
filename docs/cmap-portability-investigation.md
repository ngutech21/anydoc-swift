# CMap portability upgrade investigation

## Status on 2026-09-27

The first iOS release may retain the documented predefined-CMap conversion
limitation. The upgrade from pdf-inspector 1.17.0 to 1.24.0 therefore proceeds
without a decoder patch. Version 1.24.0 embeds the CMap resource bytes on all
targets, removing the default lookup through a build-machine Cargo directory.
That resource change does not make the three tested predefined CMaps decode
successfully, and it does not by itself resolve the required-reason API audit.
Publication remains a separate step; the published native artifact pins stay
unchanged during this work.

## Regression and observed behavior

The three locally authored fixtures in `Tests/Fixtures/pdf/handmade-cmap-*.pdf`
need the Adobe Japan1, GB1, and CNS1 tables. They contain no embedded ToUnicode
mapping or font program. Their provenance, literal expected text, and hashes
are recorded in `Tests/Fixtures/README.md`.

The public-interface baseline command was:

```sh
env -u PDF_INSPECTOR_BCMAPS_DIR ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
  xcrun swift test --scratch-path .build/swift \
  --filter CMapPortabilityTests
```

The original tests expected the intended Unicode text. Against the packaged
1.17.0 bridge, all three failed with
`needsOCR(pages: [1], pageCount: 1)` even while the Cargo CMap directory is
readable. The original positive control was not established; denying access
could not isolate the resource-portability bug with these fixtures.

A separate diagnostic package compiled unmodified crates.io anydoc 0.2.4
with pdf-inspector 1.24.0 and lopdf 0.45.0 using Rust 1.94.1. For all three
fixtures:

- `FontCMaps::from_doc` produces no map for the CID font.
- Text extraction emits 24 U+FFFD replacement characters.
- `anydoc::to_markdown_bytes` returns `NeedsOcr { pages: [1], page_count: 1 }`.

As an independent fixture check, Apple's PDFKit `PDFDocument.string` extracts
the exact expected Japanese, simplified Chinese, and traditional Chinese text
from all three files on macOS. This distinguishes the upstream failure from
invalid PDF object offsets or incorrect CID values in the fixtures.

To locate the swallowed failure, temporary copies of the 1.17.0 and 1.24.0
sources were instrumented only at the `parse_binary_cmap(&data).ok()?`
boundary. Both versions report:

```text
Adobe-Japan1-UCS2.bcmap: unexpected EOF in bcmap
Adobe-GB1-UCS2.bcmap: unexpected EOF in bcmap
Adobe-CNS1-UCS2.bcmap: unexpected EOF in bcmap
```

During that diagnosis, no shared Cargo source or production Rust code was
patched. The unmodified 1.24.0 failure was observed before adding diagnostic
logging. This is distinct from the missing-resource path fixed by embedding.

The published 1.25.0 crate was also inspected: the relevant decoder section
and all three table files are byte-for-byte unchanged from 1.24.0. This was a
source comparison, not a separate runtime test of 1.25.0.

## Release regression contract

The revised release scope accepts this existing decoder limitation.
`CMapLimitationTests` now requires the exact public
`AnyDocConversionError.needsOCR(pages: [1], pageCount: 1)` result for each
fixture, rather than successful text extraction. It continues to load the
original fixture bytes through `Bundle.module` and calls
`AnyDocConverter.markdown(from:format:)`. No embedded mappings, font programs,
skips, or production fallback have been added to conceal the limitation.

Run the limitation regressions against the rebuilt local framework with:

```sh
env -u PDF_INSPECTOR_BCMAPS_DIR ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
  xcrun swift test --scratch-path .build/swift \
  --filter CMapLimitationTests
```

Passing these tests establishes the typed failure contract only. In particular,
the same failure when filesystem access is blocked cannot prove that CMap
decoding works from embedded resources. Successful CMap conversion portability
remains unverified until the decoder is fixed and an exact-text positive control
passes. Artifact rebuilds, the full simulator suite, license verification, and
the privacy audit remain independent upgrade checks.

## Deferred decoder follow-up

Investigate the binary CMap decoder against the bundled table format and fix it
upstream. Once a suitable dependency version is adopted, restore exact-text
assertions using the independent text and CID values in the fixture provenance,
then verify them with external CMap reads denied. This follow-up is not a
prerequisite for the first iOS release.
