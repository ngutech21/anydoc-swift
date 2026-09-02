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
