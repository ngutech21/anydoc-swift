import Foundation

/// Decodes and validates manifest schema version 1 without exposing Codable on
/// the public model graph.
enum AnyDocDocumentDecoder {
  struct Prepared {
    fileprivate let manifest: Manifest
    let manifestByteCount: UInt64

    var assetByteLengths: [UInt64] {
      manifest.assets.map(\.byteLength)
    }

    func materialize(assetBytes: [Data]) throws -> AnyDocDocument {
      try manifest.materialize(assetBytes: assetBytes)
    }
  }

  static func prepare(manifest data: Data) throws -> Prepared {
    do {
      let manifest = try JSONDecoder().decode(Manifest.self, from: data)
      guard manifest.schemaVersion == 1 else {
        throw invalidManifest()
      }
      guard let byteCount = UInt64(exactly: data.count) else {
        throw invalidManifest()
      }
      return Prepared(manifest: manifest, manifestByteCount: byteCount)
    } catch let error as AnyDocConversionError {
      throw error
    } catch {
      throw invalidManifest()
    }
  }

  static func decode(manifest data: Data, assetBytes: [Data]) throws -> AnyDocDocument {
    try prepare(manifest: data).materialize(assetBytes: assetBytes)
  }

  fileprivate static func invalidManifest() -> AnyDocConversionError {
    .bridgeFailure("Native bridge returned an invalid structured-document manifest.")
  }
}

private struct Manifest: Decodable {
  let schemaVersion: UInt64
  let blocks: [WireBlock]
  let notes: [WireNote]
  let assets: [WireAsset]

  func materialize(assetBytes: [Data]) throws -> AnyDocDocument {
    guard assets.count == assetBytes.count else {
      throw AnyDocDocumentDecoder.invalidManifest()
    }

    var publicAssets: [AnyDocDocument.Asset] = []
    publicAssets.reserveCapacity(assets.count)
    for (index, pair) in zip(assets, assetBytes).enumerated() {
      let (metadata, bytes) = pair
      let id = try checkedInt(metadata.id)
      guard id == index, metadata.byteLength == UInt64(bytes.count) else {
        throw AnyDocDocumentDecoder.invalidManifest()
      }
      publicAssets.append(
        .init(
          id: id,
          mediaType: metadata.mediaType,
          originPart: metadata.originPart,
          bytes: bytes
        )
      )
    }

    let assetCount = publicAssets.count
    return try AnyDocDocument(
      blocks: blocks.map { try $0.materialize(assetCount: assetCount) },
      notes: notes.map { try $0.materialize(assetCount: assetCount) },
      assets: publicAssets
    )
  }
}

private struct WireAsset: Decodable {
  let id: UInt64
  let mediaType: String
  let originPart: String
  let byteLength: UInt64
}

private struct WireNote: Decodable {
  let id: String
  let kind: WireNoteKind
  let blocks: [WireBlock]

  func materialize(assetCount: Int) throws -> AnyDocDocument.Note {
    .init(
      id: id,
      kind: kind == .footnote ? .footnote : .endnote,
      blocks: try blocks.map { try $0.materialize(assetCount: assetCount) }
    )
  }
}

private enum WireNoteKind: String, Decodable {
  case footnote
  case endnote
}

private enum WireBlock: Decodable {
  case heading(HeadingValue)
  case paragraph([WireInline])
  case list(WireList)
  case table(WireTable)
  case blockQuote([WireBlock])
  case codeBlock(CodeBlockValue)
  case rule
  case math(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "heading":
      self = .heading(try container.decode(HeadingValue.self, forKey: .value))
    case "paragraph":
      self = .paragraph(try container.decode([WireInline].self, forKey: .value))
    case "list":
      self = .list(try container.decode(WireList.self, forKey: .value))
    case "table":
      self = .table(try container.decode(WireTable.self, forKey: .value))
    case "blockQuote":
      self = .blockQuote(try container.decode([WireBlock].self, forKey: .value))
    case "codeBlock":
      self = .codeBlock(try container.decode(CodeBlockValue.self, forKey: .value))
    case "rule":
      self = .rule
    case "math":
      self = .math(try container.decode(String.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown block kind"
      )
    }
  }

  func materialize(assetCount: Int) throws -> AnyDocDocument.Block {
    switch self {
    case .heading(let value):
      let level = try checkedInt(value.level)
      guard (1...Int(UInt8.max)).contains(level) else {
        throw AnyDocDocumentDecoder.invalidManifest()
      }
      return .heading(
        level: level,
        anchor: value.anchor,
        content: try value.content.map { try $0.materialize(assetCount: assetCount) }
      )
    case .paragraph(let content):
      return .paragraph(try content.map { try $0.materialize(assetCount: assetCount) })
    case .list(let value):
      return .list(try value.materialize(assetCount: assetCount))
    case .table(let value):
      return .table(try value.materialize(assetCount: assetCount))
    case .blockQuote(let blocks):
      return .blockQuote(try blocks.map { try $0.materialize(assetCount: assetCount) })
    case .codeBlock(let value):
      return .codeBlock(language: value.language, text: value.text)
    case .rule:
      return .rule
    case .math(let value):
      return .math(value)
    }
  }
}

private struct HeadingValue: Decodable {
  let level: UInt64
  let anchor: String?
  let content: [WireInline]
}

private struct CodeBlockValue: Decodable {
  let language: String?
  let text: String
}

private enum WireInline: Decodable {
  case text(TextValue)
  case link(LinkValue)
  case image(ImageValue)
  case anchor(String)
  case noteReference(String)
  case lineBreak
  case math(String)
  case checkbox(Bool)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "text":
      self = .text(try container.decode(TextValue.self, forKey: .value))
    case "link":
      self = .link(try container.decode(LinkValue.self, forKey: .value))
    case "image":
      self = .image(try container.decode(ImageValue.self, forKey: .value))
    case "anchor":
      self = .anchor(try container.decode(String.self, forKey: .value))
    case "noteRef":
      self = .noteReference(try container.decode(String.self, forKey: .value))
    case "lineBreak":
      self = .lineBreak
    case "math":
      self = .math(try container.decode(String.self, forKey: .value))
    case "checkbox":
      self = .checkbox(try container.decode(Bool.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown inline kind"
      )
    }
  }

  func materialize(assetCount: Int) throws -> AnyDocDocument.Inline {
    switch self {
    case .text(let value):
      return .text(
        text: value.text,
        style: .init(
          bold: value.style.bold,
          italic: value.style.italic,
          strike: value.style.strike,
          code: value.style.code
        )
      )
    case .link(let value):
      return .link(
        content: try value.content.map { try $0.materialize(assetCount: assetCount) },
        target: value.target.materialize()
      )
    case .image(let value):
      return .image(
        alt: value.alt,
        source: try value.source.materialize(assetCount: assetCount)
      )
    case .anchor(let id):
      return .anchor(id: id)
    case .noteReference(let id):
      return .noteReference(id: id)
    case .lineBreak:
      return .lineBreak
    case .math(let value):
      return .math(value)
    case .checkbox(let isChecked):
      return .checkbox(isChecked: isChecked)
    }
  }
}

private struct TextValue: Decodable {
  let text: String
  let style: WireStyle
}

private struct WireStyle: Decodable {
  let bold: Bool
  let italic: Bool
  let strike: Bool
  let code: Bool
}

private struct LinkValue: Decodable {
  let content: [WireInline]
  let target: WireLinkTarget
}

private enum WireLinkTarget: Decodable {
  case external(String)
  case relative(String)
  case anchor(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let value = try container.decode(String.self, forKey: .value)
    switch try container.decode(String.self, forKey: .kind) {
    case "external": self = .external(value)
    case "relative": self = .relative(value)
    case "anchor": self = .anchor(value)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown link-target kind"
      )
    }
  }

  func materialize() -> AnyDocDocument.LinkTarget {
    switch self {
    case .external(let value): .external(value)
    case .relative(let value): .relative(value)
    case .anchor(let value): .anchor(value)
    }
  }
}

private struct ImageValue: Decodable {
  let alt: String
  let source: WireImageSource
}

private enum WireImageSource: Decodable {
  case external(String)
  case asset(UInt64)
  case unavailable

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "external":
      self = .external(try container.decode(String.self, forKey: .value))
    case "asset":
      self = .asset(try container.decode(UInt64.self, forKey: .value))
    case "unavailable":
      self = .unavailable
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown image-source kind"
      )
    }
  }

  func materialize(assetCount: Int) throws -> AnyDocDocument.ImageSource {
    switch self {
    case .external(let value):
      return .external(value)
    case .asset(let rawID):
      let id = try checkedInt(rawID)
      guard id < assetCount else {
        throw AnyDocDocumentDecoder.invalidManifest()
      }
      return .asset(id: id)
    case .unavailable:
      return .unavailable
    }
  }
}

private struct WireList: Decodable {
  let marker: WireMarkerKind
  let start: UInt64
  let items: [WireListItem]

  func materialize(assetCount: Int) throws -> AnyDocDocument.List {
    .init(
      marker: marker.materialize(),
      start: start,
      items: try items.map { try $0.materialize(assetCount: assetCount) }
    )
  }
}

private enum WireMarkerKind: String, Decodable {
  case bullet
  case decimal
  case lowerAlpha
  case upperAlpha
  case lowerRoman
  case upperRoman

  func materialize() -> AnyDocDocument.MarkerKind {
    switch self {
    case .bullet: .bullet
    case .decimal: .decimal
    case .lowerAlpha: .lowerAlpha
    case .upperAlpha: .upperAlpha
    case .lowerRoman: .lowerRoman
    case .upperRoman: .upperRoman
    }
  }
}

private struct WireListItem: Decodable {
  let blocks: [WireBlock]
  let markerLabel: String?

  func materialize(assetCount: Int) throws -> AnyDocDocument.ListItem {
    .init(
      blocks: try blocks.map { try $0.materialize(assetCount: assetCount) },
      markerLabel: markerLabel
    )
  }
}

private struct WireTable: Decodable {
  let grid: [[WireCellSlot]]
  let headerRows: UInt64
  let kind: WireTableKind

  func materialize(assetCount: Int) throws -> AnyDocDocument.Table {
    let publicGrid = try grid.map { row in
      try row.map { try $0.materialize(assetCount: assetCount) }
    }
    let publicHeaderRows = try checkedInt(headerRows)
    guard publicHeaderRows <= publicGrid.count else {
      throw AnyDocDocumentDecoder.invalidManifest()
    }
    try validateCanonicalGrid(publicGrid)
    return .init(
      grid: publicGrid,
      headerRows: publicHeaderRows,
      kind: kind == .data ? .data : .layout
    )
  }
}

private enum WireTableKind: String, Decodable {
  case data
  case layout
}

private enum WireCellSlot: Decodable {
  case origin(WireCell)
  case covered(WireCoveredCell)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "origin":
      self = .origin(try container.decode(WireCell.self, forKey: .value))
    case "covered":
      self = .covered(try container.decode(WireCoveredCell.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown table-slot kind"
      )
    }
  }

  func materialize(assetCount: Int) throws -> AnyDocDocument.CellSlot {
    switch self {
    case .origin(let cell):
      let columnSpan = try checkedSpan(cell.columnSpan)
      let rowSpan = try checkedSpan(cell.rowSpan)
      return .origin(
        .init(
          blocks: try cell.blocks.map { try $0.materialize(assetCount: assetCount) },
          columnSpan: columnSpan,
          rowSpan: rowSpan
        )
      )
    case .covered(let covered):
      return .covered(
        originRow: try checkedInt(covered.originRow),
        originColumn: try checkedInt(covered.originColumn)
      )
    }
  }
}

private struct WireCell: Decodable {
  let blocks: [WireBlock]
  let columnSpan: UInt64
  let rowSpan: UInt64
}

private struct WireCoveredCell: Decodable {
  let originRow: UInt64
  let originColumn: UInt64
}

private func checkedInt(_ value: UInt64) throws -> Int {
  guard let value = Int(exactly: value) else {
    throw AnyDocDocumentDecoder.invalidManifest()
  }
  return value
}

private func checkedSpan(_ value: UInt64) throws -> Int {
  guard value > 0, value <= UInt64(UInt32.max) else {
    throw AnyDocDocumentDecoder.invalidManifest()
  }
  return try checkedInt(value)
}

private func validateCanonicalGrid(_ grid: [[AnyDocDocument.CellSlot]]) throws {
  for (rowIndex, row) in grid.enumerated() {
    for (columnIndex, slot) in row.enumerated() {
      switch slot {
      case .origin(let cell):
        try validateOrigin(
          row: rowIndex,
          column: columnIndex,
          cell: cell,
          grid: grid
        )
      case .covered(let originRow, let originColumn):
        try validateCovered(
          row: rowIndex,
          column: columnIndex,
          originRow: originRow,
          originColumn: originColumn,
          grid: grid
        )
      }
    }
  }
}

private func validateOrigin(
  row: Int,
  column: Int,
  cell: AnyDocDocument.Cell,
  grid: [[AnyDocDocument.CellSlot]]
) throws {
  let (lastRow, rowOverflow) = row.addingReportingOverflow(cell.rowSpan - 1)
  let (lastColumn, columnOverflow) = column.addingReportingOverflow(cell.columnSpan - 1)
  guard !rowOverflow, !columnOverflow, lastRow < grid.count else {
    throw AnyDocDocumentDecoder.invalidManifest()
  }

  for coveredRow in row...lastRow {
    guard lastColumn < grid[coveredRow].count else {
      throw AnyDocDocumentDecoder.invalidManifest()
    }
    for coveredColumn in column...lastColumn where (coveredRow, coveredColumn) != (row, column) {
      guard
        case .covered(originRow: row, originColumn: column) =
          grid[coveredRow][coveredColumn]
      else {
        throw AnyDocDocumentDecoder.invalidManifest()
      }
    }
  }
}

private func validateCovered(
  row: Int,
  column: Int,
  originRow: Int,
  originColumn: Int,
  grid: [[AnyDocDocument.CellSlot]]
) throws {
  guard
    originRow < grid.count,
    originColumn < grid[originRow].count,
    case .origin(let origin) = grid[originRow][originColumn]
  else {
    throw AnyDocDocumentDecoder.invalidManifest()
  }

  let (lastRow, rowOverflow) = originRow.addingReportingOverflow(origin.rowSpan - 1)
  let (lastColumn, columnOverflow) = originColumn.addingReportingOverflow(origin.columnSpan - 1)
  guard
    !rowOverflow,
    !columnOverflow,
    row >= originRow,
    row <= lastRow,
    column >= originColumn,
    column <= lastColumn,
    (row, column) != (originRow, originColumn)
  else {
    throw AnyDocDocumentDecoder.invalidManifest()
  }
}
