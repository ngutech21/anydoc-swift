# Fixture provenance

Every committed fixture must record its origin and SHA-256 digest here. Expected
Markdown is pinned in the test that consumes the fixture.

## `rtf/handmade-blockstyle.rtf`

- Source: `firecrawl/anydoc` test fixture
- Revision: `bf3d33e61731580d1ee1c6a85e56093d715a21a6`
- Upstream path: `tests/fixtures/rtf/handmade-blockstyle.rtf`
- URL: <https://github.com/firecrawl/anydoc/blob/bf3d33e61731580d1ee1c6a85e56093d715a21a6/tests/fixtures/rtf/handmade-blockstyle.rtf>
- SHA-256: `e89c59df03996369f284858eddb91865475a909296ac5d26b2a41480980f092e`
- License: MIT, inherited from the upstream repository

## `csv/handmade-quoted.csv`

- Source: `firecrawl/anydoc` test fixture
- Revision: `bf3d33e61731580d1ee1c6a85e56093d715a21a6`
- Upstream path: `tests/fixtures/csv/handmade-quoted.csv`
- URL: <https://github.com/firecrawl/anydoc/blob/bf3d33e61731580d1ee1c6a85e56093d715a21a6/tests/fixtures/csv/handmade-quoted.csv>
- SHA-256: `c50a6a4b653f234e2a7b4d40a0ed0aa1c44c3f21425760c583b838de6c799301`
- License: MIT, inherited from the upstream repository

## `pdf/handmade-mixed.pdf`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/pdf/handmade-mixed.pdf`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/pdf/handmade-mixed.pdf>
- SHA-256: `cd9c10c20b4c324273f98a3f63018eea07592e3e3103092ee1f9499f7a38cede`
- License: MIT, inherited from the upstream repository

## `pdf/handmade-scanned.pdf`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/pdf/handmade-scanned.pdf`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/pdf/handmade-scanned.pdf>
- SHA-256: `f298b75294aa55400691fb88abb7c30e88fbde4ad04a9a43d809c12b214545c4`
- License: MIT, inherited from the upstream repository

## `pdf/text.pdf`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/pdf/text.pdf`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/pdf/text.pdf>
- SHA-256: `7d1fd0932634cffa80bf9fb1bd73a6871f82a2cb29b4d7bcfb689927bc5d84e7`
- License: MIT, inherited from the upstream repository

## Predefined CMap regression PDFs

`pdf/handmade-cmap-japan1.pdf`, `pdf/handmade-cmap-gb1.pdf`, and
`pdf/handmade-cmap-cns1.pdf` are locally authored, deterministic PDF 1.4 files.
Each has one page, one Type0 font using Identity-H, a CIDFontType0 descendant,
and an Adobe CIDSystemInfo collection. They contain neither a ToUnicode map
nor an embedded font program, so text extraction requires the predefined
collection's CID-to-Unicode table. The content stream contains 24 CIDs at
12 points; object offsets and lengths are explicit, with no compression,
timestamps, document identifiers, or external references.

The CID values were checked against Adobe's
[mapping resources](https://github.com/adobe-type-tools/mapping-resources-pdf/tree/2dd5e53fb74a01718b9dfd448a0d1cce6fff2aa5/pdf2unicode)
at revision `2dd5e53fb74a01718b9dfd448a0d1cce6fff2aa5`. The table below records
the intended Unicode text independently of the decoder under test.

| File | Collection | Decimal CIDs per phrase | Phrase and repetition | SHA-256 |
| --- | --- | --- | --- | --- |
| `handmade-cmap-japan1.pdf` | Japan1 | 3284, 3722, 1952 | `日本語` eight times | `ecc17479e542ef102e02cbd669b8e5425fcee8fd25a999ee144f869656c04b1e` |
| `handmade-cmap-gb1.pdf` | GB1 | 4559, 3795, 3795, 1430 | `中文文档` six times | `8f6c282e71da6b9d1256ee9d2b0386dc2050a2e57f9f593e5af2e13c2d93092b` |
| `handmade-cmap-cns1.pdf` | CNS1 | 5183, 5911, 661, 726 | `繁體中文` six times | `b96788a91cb6527e10cfaf220e699884a72e970cea3fd343fe0ecbc7543441cc` |

- License: MIT, under the project license.
- These fixtures exposed an upstream decoding failure before the planned
  resource-isolation control could be established; see
  [the investigation](../../docs/cmap-portability-investigation.md).
- `CMapLimitationTests` exercises the public converter and requires the exact
  typed `needsOCR(pages: [1], pageCount: 1)` error for each fixture. These are
  limitation regressions, not proof of successful CMap conversion or resource
  portability. The first iOS release can retain this documented limitation.

## `docx/text.docx`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/docx/text.docx`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/docx/text.docx>
- SHA-256: `6b674297884f9ed57809763c9f60ea3a849d5cc6fb28c9837c714e322eceddcf`
- License: MIT, inherited from the upstream repository

## `docx/handmade-rich.docx`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/docx/handmade-rich.docx`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/docx/handmade-rich.docx>
- SHA-256: `22afadb7927cc11d7520cd0f471aa1eea658369a1ba85da48123aded0700aafa`
- License: MIT, inherited from the upstream repository

## `docx/handmade-manyrefs.docx`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/docx/handmade-manyrefs.docx`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/docx/handmade-manyrefs.docx>
- SHA-256: `219cfa32f83401f6415191d33d391ddbc35edbbbb3e04678b0d1b74ad6d14cb7`
- License: MIT, inherited from the upstream repository

## `docx/handmade-tables.docx`

- Source: `firecrawl/anydoc` test fixture
- Revision: `42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c`
- Upstream path: `tests/fixtures/docx/handmade-tables.docx`
- URL: <https://github.com/firecrawl/anydoc/blob/42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c/tests/fixtures/docx/handmade-tables.docx>
- SHA-256: `cf847fbf73810f6af47181230cd4ad2704a53e8b2668297dba4904f7366da6ce`
- License: MIT, inherited from the upstream repository

## `epub/handmade-rowspan-gap.epub`

- Source: locally authored EPUB 3 regression fixture for AnyDocSwift
- Content: a table with a two-row span in its third column and only one cell
  in its second row; the pinned anydoc 0.2.4 grid builder inserts an empty
  zero-span filler before the covered position
- Archive: uncompressed ZIP entries, `mimetype` first, with fixed
  `1980-01-01T00:00:00` entry timestamps
- SHA-256: `0c6f2e7939c25f35a58e02b6f612d05a08a478acc16c103d8e41e14d2cd4c489`
- License: MIT, under the project license
