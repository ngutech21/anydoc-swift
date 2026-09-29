# Formats and PDFs

Choose a parser and understand the limits of PDF conversion.

## Overview

Both conversion methods accept an optional ``AnyDocFormat``. A non-`nil` value
selects that parser authoritatively, even when the bytes resemble another
format. A `nil` value delegates detection to anydoc.

| Parser | Document family | Recognized filename extensions |
| --- | --- | --- |
| ``AnyDocFormat/doc`` | Binary Word | `doc` |
| ``AnyDocFormat/docx`` | Open XML Word | `docx`, `docm` |
| ``AnyDocFormat/odt`` | OpenDocument text | `odt` |
| ``AnyDocFormat/pdf`` | PDF, Markdown only | `pdf` |
| ``AnyDocFormat/ppt`` | Binary PowerPoint | `ppt`, `pps`, `pot` |
| ``AnyDocFormat/pptx`` | Open XML PowerPoint | `pptx`, `pptm`, `ppsx`, `ppsm` |
| ``AnyDocFormat/rtf`` | Rich Text Format | `rtf` |
| ``AnyDocFormat/epub`` | EPUB | `epub` |
| ``AnyDocFormat/xlsx`` | Excel | `xls`, `xlsx`, `xlsm`, `xlsb` |
| ``AnyDocFormat/ods`` | OpenDocument spreadsheet | `ods` |
| ``AnyDocFormat/odp`` | OpenDocument presentation | `odp` |
| ``AnyDocFormat/csv`` | CSV | `csv` |

### Select a parser from a filename

``AnyDocFormat/init(fileExtension:)`` accepts bare extensions using ASCII
case-insensitive matching. It does not remove leading dots or whitespace,
extract a suffix from a filename, or inspect the data.

```swift
import AnyDocSwift
import Foundation

let url = URL(fileURLWithPath: "/path/to/workbook.xlsm")
let bytes = try Data(contentsOf: url)
let format = AnyDocFormat(fileExtension: url.pathExtension)
let markdown = try await AnyDocConverter().markdown(from: bytes, format: format)
print(markdown)
```

Unknown extensions, including `potx` and `potm`, return `nil`. Passing that
result to a converter enables automatic detection. Unwrap it first if your
application must reject unknown extensions.

The enum's raw values are canonical parser names. For example,
`AnyDocFormat(rawValue: "xlsm")` returns `nil`, while the filename initializer
returns `.xlsx`.

### Convert PDFs

Text-based PDFs can produce Markdown locally, with approximate layout
reconstruction. Headings, lists, and table boundaries may differ from the source.

If any page requires OCR, the default conversion throws
``AnyDocConversionError/needsOCR(pages:pageCount:)`` without partial Markdown.
The page numbers are sorted, unique, and one-based. Some text PDFs using
predefined CMaps also require fallback because the upstream decoder cannot
recover their text; see the
[CMap investigation](https://github.com/ngutech21/anydoc-swift/blob/master/docs/cmap-portability-investigation.md).

There is no local OCR or structured PDF output.
``AnyDocConverter/document(from:format:)`` rejects PDF input. Applications may
explicitly permit the Markdown conversion to use <doc:HostedOCR>.
