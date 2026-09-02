import Foundation

/// An information-preserving, self-contained document parsed by AnyDoc.
///
/// The graph is read-only parser output. Embedded assets retain their exact
/// source bytes, so the value remains usable after the input buffer is gone.
public struct AnyDocDocument: Sendable, Equatable {
  public let blocks: [Block]
  public let notes: [Note]
  public let assets: [Asset]
}

extension AnyDocDocument {
  public indirect enum Block: Sendable, Equatable {
    case heading(level: Int, anchor: String?, content: [Inline])
    case paragraph([Inline])
    case list(List)
    case table(Table)
    case blockQuote([Block])
    case codeBlock(language: String?, text: String)
    case rule
    case math(String)
  }

  public indirect enum Inline: Sendable, Equatable {
    case text(text: String, style: Style)
    case link(content: [Inline], target: LinkTarget)
    case image(alt: String, source: ImageSource)
    case anchor(id: String)
    case noteReference(id: String)
    case lineBreak
    case math(String)
    case checkbox(isChecked: Bool)
  }

  public struct Style: Sendable, Equatable {
    public let bold: Bool
    public let italic: Bool
    public let strike: Bool
    public let code: Bool
  }

  public enum LinkTarget: Sendable, Equatable {
    case external(String)
    case relative(String)
    case anchor(String)
  }

  public enum ImageSource: Sendable, Equatable {
    case external(String)
    case asset(id: Int)
    case unavailable
  }

  public struct List: Sendable, Equatable {
    public let marker: MarkerKind
    public let start: UInt64
    public let items: [ListItem]
  }

  public enum MarkerKind: Sendable, Equatable {
    case bullet
    case decimal
    case lowerAlpha
    case upperAlpha
    case lowerRoman
    case upperRoman
  }

  public struct ListItem: Sendable, Equatable {
    public let blocks: [Block]
    public let markerLabel: String?
  }

  public struct Table: Sendable, Equatable {
    public let grid: [[CellSlot]]
    public let headerRows: Int
    public let kind: TableKind
  }

  public enum TableKind: Sendable, Equatable {
    case data
    case layout
  }

  public enum CellSlot: Sendable, Equatable {
    case origin(Cell)
    case covered(originRow: Int, originColumn: Int)
  }

  public struct Cell: Sendable, Equatable {
    public let blocks: [Block]
    public let columnSpan: Int
    public let rowSpan: Int
  }

  public struct Note: Sendable, Equatable {
    public let id: String
    public let kind: NoteKind
    public let blocks: [Block]
  }

  public enum NoteKind: Sendable, Equatable {
    case footnote
    case endnote
  }

  public struct Asset: Sendable, Equatable {
    public let id: Int
    public let mediaType: String
    public let originPart: String
    public let bytes: Data
  }
}
