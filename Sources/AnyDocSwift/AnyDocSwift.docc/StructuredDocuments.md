# Reading structured documents

Inspect document blocks, tables, notes, and embedded assets.

## Overview

Use ``AnyDocConverter/document(from:format:)`` when your application needs the
parsed structure instead of Markdown. The resulting ``AnyDocDocument`` is
immutable parser output. It owns copied asset bytes and remains usable after
the input buffer is gone. PDF has no structured representation.

```swift
import AnyDocSwift
import Foundation

let bytes = Data("name,value\nexample,42\n".utf8)
let document = try await AnyDocConverter().document(from: bytes, format: .csv)

for block in document.blocks {
  if case .table(let table) = block {
    for row in table.grid {
      for slot in row {
        if case .origin(let cell) = slot {
          print("Cell spans \(cell.rowSpan) rows and \(cell.columnSpan) columns")
        }
      }
    }
  }
}
```

### Traverse content

``AnyDocDocument/Block`` covers headings, paragraphs, lists, tables, block
quotes, code blocks, rules, and display math. Containers can hold more blocks,
so a complete traversal must visit nested content too.

``AnyDocDocument/Inline`` covers styled text, links, images, anchors, note
references, line breaks, inline math, and checkboxes. Footnotes and endnotes
are available in ``AnyDocDocument/notes``.

### Read table spans

``AnyDocDocument/Table/grid`` is a canonical grid. An origin slot contains a
cell with positive row and column spans. A covered slot points back to its
origin using zero-based row and column indexes. Visit origins to render cell
content once; use covered slots to account for merged cells.

``AnyDocDocument/Table/headerRows`` identifies the number of leading header
rows, and ``AnyDocDocument/Table/kind`` distinguishes data and layout tables.

### Use embedded assets

An inline image can reference an external source, an embedded asset ID, or an
unavailable source. Embedded IDs index ``AnyDocDocument/assets``. Each
``AnyDocDocument/Asset`` contains its media type, source part, and exact bytes.
External sources are not fetched by the structured-document API.

The public graph is `Sendable` and `Equatable`. It is not a persistence schema,
has no public struct initializers, and does not conform to `Codable`. Keep any
storage format or custom rendering in your application. The structured-result
size limit is described in <doc:LimitsAndErrors>.
