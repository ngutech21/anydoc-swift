public import Foundation

/// An information-preserving, self-contained document parsed by anydoc.
///
/// The graph is read-only parser output. Embedded assets retain their exact
/// source bytes, so the value remains usable after the input buffer is gone.
public struct AnyDocDocument: Sendable, Equatable {
  /// Top-level content in document order.
  public let blocks: [Block]
  /// Footnotes and endnotes referenced by the document.
  public let notes: [Note]
  /// Embedded assets, indexed by their document-local IDs.
  public let assets: [Asset]
}

extension AnyDocDocument {
  /// A block of content, including containers with nested blocks or inlines.
  public indirect enum Block: Sendable, Equatable {
    /// A heading with its level, optional anchor, and inline content.
    case heading(level: Int, anchor: String?, content: [Inline])
    /// A paragraph of inline content.
    case paragraph([Inline])
    /// An ordered or unordered list.
    case list(List)
    /// A table represented by a canonical cell grid.
    case table(Table)
    /// A quotation containing nested blocks.
    case blockQuote([Block])
    /// Literal code with an optional language identifier.
    case codeBlock(language: String?, text: String)
    /// A horizontal rule.
    case rule
    /// A display-math expression from the parser.
    case math(String)
  }

  /// Inline content within headings, paragraphs, and links.
  public indirect enum Inline: Sendable, Equatable {
    /// Text with its formatting flags.
    case text(text: String, style: Style)
    /// Link content and its destination.
    case link(content: [Inline], target: LinkTarget)
    /// An image's alternative text and source.
    case image(alt: String, source: ImageSource)
    /// A named anchor inside the document.
    case anchor(id: String)
    /// A reference to a footnote or endnote ID.
    case noteReference(id: String)
    /// An explicit line break.
    case lineBreak
    /// An inline-math expression from the parser.
    case math(String)
    /// A checkbox and its checked state.
    case checkbox(isChecked: Bool)
  }

  /// Formatting flags attached to a text run.
  public struct Style: Sendable, Equatable {
    /// Whether the text is bold.
    public let bold: Bool
    /// Whether the text is italic.
    public let italic: Bool
    /// Whether the text has strikethrough formatting.
    public let strike: Bool
    /// Whether the text is formatted as inline code.
    public let code: Bool
  }

  /// A link destination preserved by the parser.
  public enum LinkTarget: Sendable, Equatable {
    /// An external destination.
    case external(String)
    /// A relative destination.
    case relative(String)
    /// An anchor within the document.
    case anchor(String)
  }

  /// An external, embedded, or unavailable image source.
  public enum ImageSource: Sendable, Equatable {
    /// An external source location; reading the graph does not fetch it.
    case external(String)
    /// An embedded image whose ID indexes ``AnyDocDocument/assets``.
    case asset(id: Int)
    /// An image whose source is unavailable.
    case unavailable
  }

  /// A list with its marker style, starting value, and items.
  public struct List: Sendable, Equatable {
    /// The style used for item markers.
    public let marker: MarkerKind
    /// The list's starting value as supplied by the parser.
    public let start: UInt64
    /// List items in document order.
    public let items: [ListItem]
  }

  /// The marker style of a list.
  public enum MarkerKind: Sendable, Equatable {
    /// Unordered bullet markers.
    case bullet
    /// Decimal-number markers.
    case decimal
    /// Lowercase alphabetical markers.
    case lowerAlpha
    /// Uppercase alphabetical markers.
    case upperAlpha
    /// Lowercase Roman-numeral markers.
    case lowerRoman
    /// Uppercase Roman-numeral markers.
    case upperRoman
  }

  /// One list item, including nested block content.
  public struct ListItem: Sendable, Equatable {
    /// The item's content in document order.
    public let blocks: [Block]
    /// An explicit marker label, when provided by the parser.
    public let markerLabel: String?
  }

  /// A canonical table grid with origin cells and covered span positions.
  public struct Table: Sendable, Equatable {
    /// Rows of slots, with covered-slot coordinates measured from zero.
    public let grid: [[CellSlot]]
    /// The number of leading rows classified as headers.
    public let headerRows: Int
    /// Whether the parser classifies the table as data or layout.
    public let kind: TableKind
  }

  /// The parser's classification of a table's purpose.
  public enum TableKind: Sendable, Equatable {
    /// A table containing tabular data.
    case data
    /// A table used for document layout.
    case layout
  }

  /// A table position containing a cell or covered by another cell's span.
  public enum CellSlot: Sendable, Equatable {
    /// A cell's origin, containing its content and spans.
    case origin(Cell)
    /// A covered position pointing to its origin's zero-based grid coordinates.
    case covered(originRow: Int, originColumn: Int)
  }

  /// Content and positive spans for a table cell at its origin position.
  public struct Cell: Sendable, Equatable {
    /// The cell's content in document order.
    public let blocks: [Block]
    /// The number of grid columns spanned by this cell.
    public let columnSpan: Int
    /// The number of grid rows spanned by this cell.
    public let rowSpan: Int
  }

  /// A footnote or endnote and its block content.
  public struct Note: Sendable, Equatable {
    /// The identifier used by inline note references.
    public let id: String
    /// Whether the note is a footnote or an endnote.
    public let kind: NoteKind
    /// The note's content in document order.
    public let blocks: [Block]
  }

  /// The placement category of a note.
  public enum NoteKind: Sendable, Equatable {
    /// A footnote.
    case footnote
    /// An endnote.
    case endnote
  }

  /// An embedded asset whose bytes are owned by the Swift document value.
  public struct Asset: Sendable, Equatable {
    /// The asset's index in ``AnyDocDocument/assets``.
    public let id: Int
    /// The media type recorded by the parser.
    public let mediaType: String
    /// The source document part from which the asset originated.
    public let originPart: String
    /// The asset's exact source bytes, copied out of native storage.
    public let bytes: Data
  }
}
