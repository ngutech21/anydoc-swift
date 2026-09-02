import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocStructuredFixtureTests: XCTestCase, @unchecked Sendable {
  func testPinnedFixtureProvenanceHashes() throws {
    let expected = [
      "docx/text.docx": "6b674297884f9ed57809763c9f60ea3a849d5cc6fb28c9837c714e322eceddcf",
      "docx/handmade-rich.docx":
        "22afadb7927cc11d7520cd0f471aa1eea658369a1ba85da48123aded0700aafa",
      "docx/handmade-manyrefs.docx":
        "219cfa32f83401f6415191d33d391ddbc35edbbbb3e04678b0d1b74ad6d14cb7",
      "docx/handmade-tables.docx":
        "cf847fbf73810f6af47181230cd4ad2704a53e8b2668297dba4904f7366da6ce",
      "epub/handmade-rowspan-gap.epub":
        "0c6f2e7939c25f35a58e02b6f612d05a08a478acc16c103d8e41e14d2cd4c489",
    ]
    XCTAssertEqual(
      sha256Hex(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    for (fixture, hash) in expected {
      XCTAssertEqual(sha256Hex(try fixtureData(fixture)), hash, fixture)
    }
  }

  func testTextFixturePreservesNotesLinksAnchorsSpansAndAssetBytes() async throws {
    let document = try await AnyDocConverter().document(
      from: fixtureData("docx/text.docx"),
      format: .docx
    )

    XCTAssertEqual(document.notes.map(\.id), ["fn2", "en2"])
    XCTAssertEqual(document.notes.map(\.kind), [.footnote, .endnote])
    let inlines = allInlines(in: document)
    let targets = inlines.compactMap { inline -> AnyDocDocument.LinkTarget? in
      guard case .link(_, let target) = inline else { return nil }
      return target
    }
    XCTAssertTrue(targets.contains(.external("https://example.com/page")))
    XCTAssertTrue(targets.contains(.relative("../../fixture-src/sibling.odt")))
    XCTAssertTrue(targets.contains(.anchor("plainmark")))
    XCTAssertTrue(inlines.contains(.anchor(id: "plainmark")))
    XCTAssertTrue(inlines.contains(.noteReference(id: "fn2")))
    XCTAssertTrue(inlines.contains(.noteReference(id: "en2")))

    let table = try XCTUnwrap(allTables(in: document).first)
    XCTAssertEqual(table.headerRows, 0)
    XCTAssertEqual(table.grid.map(\.count), [3, 3, 3])
    XCTAssertEqual(table.grid[0][1], .covered(originRow: 0, originColumn: 0))
    XCTAssertEqual(table.grid[2][0], .covered(originRow: 1, originColumn: 0))

    let asset = try XCTUnwrap(document.assets.first)
    XCTAssertEqual(asset.id, 0)
    XCTAssertEqual(asset.mediaType, "image/png")
    XCTAssertEqual(asset.originPart, "word/media/image1.png")
    XCTAssertEqual(
      sha256Hex(asset.bytes),
      "c414cd0e204de974f73753c7e28d7638e7b3691bb8b1a2bab6b25bb7fed7ce77"
    )
  }

  func testRichFixtureRetainsTwoDistinctReferencedAssets() async throws {
    let document = try await AnyDocConverter().document(
      from: fixtureData("docx/handmade-rich.docx"),
      format: .docx
    )

    XCTAssertEqual(document.assets.map(\.id), [0, 1])
    XCTAssertEqual(
      document.assets.map(\.mediaType), ["image/png", "application/vnd.ms-ole-object"])
    XCTAssertEqual(
      document.assets.map(\.originPart),
      ["word/media/dot.png", "word/embeddings/oleObject1.bin"]
    )
    XCTAssertEqual(
      document.assets.map { sha256Hex($0.bytes) },
      [
        "c414cd0e204de974f73753c7e28d7638e7b3691bb8b1a2bab6b25bb7fed7ce77",
        "be7a8c28ab094836cc1ff77dcf771c6e20bfe8fee378d258c15c80082d333e41",
      ]
    )
    XCTAssertEqual(assetReferences(in: document), [0, 1])
    XCTAssertEqual(try XCTUnwrap(allTables(in: document).first).headerRows, 1)
  }

  func testSeventyReferencesResolveToOneStableAsset() async throws {
    let document = try await AnyDocConverter().document(
      from: fixtureData("docx/handmade-manyrefs.docx"),
      format: .docx
    )

    XCTAssertEqual(document.assets.count, 1)
    XCTAssertEqual(assetReferences(in: document), Array(repeating: 0, count: 70))
    XCTAssertEqual(document.assets[0].originPart, "word/media/logo.png")
    XCTAssertEqual(
      sha256Hex(document.assets[0].bytes),
      "98554edcaad1be5539cf8f7e51516308417fffca6150f014f0565625f98da768"
    )
  }

  func testTableFixturePreservesHeaderRowsOriginsAndCoveredSlots() async throws {
    let document = try await AnyDocConverter().document(
      from: fixtureData("docx/handmade-tables.docx"),
      format: .docx
    )
    let table = try XCTUnwrap(allTables(in: document).first)

    XCTAssertEqual(table.headerRows, 1)
    XCTAssertEqual(table.kind, .data)
    XCTAssertEqual(table.grid.map(\.count), [3, 3, 3])
    guard case .origin(let vertical) = table.grid[0][2] else {
      return XCTFail("Expected vertical-span origin")
    }
    XCTAssertEqual(vertical.columnSpan, 1)
    XCTAssertEqual(vertical.rowSpan, 2)
    XCTAssertEqual(table.grid[1][2], .covered(originRow: 0, originColumn: 2))
    guard case .origin(let horizontal) = table.grid[2][0] else {
      return XCTFail("Expected horizontal-span origin")
    }
    XCTAssertEqual(horizontal.columnSpan, 2)
    XCTAssertEqual(horizontal.rowSpan, 1)
    XCTAssertEqual(table.grid[2][1], .covered(originRow: 2, originColumn: 0))
  }

  func testEPUBTablePreservesFillerBeforeALaterColumnRowSpan() async throws {
    let data = try fixtureData("epub/handmade-rowspan-gap.epub")
    let converter = AnyDocConverter()
    let markdown = try await converter.markdown(from: data, format: .epub)
    XCTAssertTrue(markdown.contains("Short"))

    let document = try await converter.document(from: data, format: .epub)
    let table = try XCTUnwrap(allTables(in: document).first)

    XCTAssertEqual(table.grid.map(\.count), [3, 3])
    XCTAssertEqual(
      table.grid[1][1],
      .origin(.init(blocks: [], columnSpan: 1, rowSpan: 1))
    )
    guard case .origin(let spanningCell) = table.grid[0][2] else {
      return XCTFail("Expected row-span origin")
    }
    XCTAssertEqual(spanningCell.columnSpan, 1)
    XCTAssertEqual(spanningCell.rowSpan, 2)
    XCTAssertEqual(table.grid[1][2], .covered(originRow: 0, originColumn: 2))
    XCTAssertEqual(
      allInlines(in: document).compactMap { inline -> String? in
        guard case .text(let text, _) = inline else { return nil }
        return text
      },
      ["Rowspan gap", "A", "B", "Tall", "Short"]
    )
  }

  private func allTables(in document: AnyDocDocument) -> [AnyDocDocument.Table] {
    allBlocks(in: document).compactMap { block in
      guard case .table(let table) = block else { return nil }
      return table
    }
  }

  private func assetReferences(in document: AnyDocDocument) -> [Int] {
    allInlines(in: document).compactMap { inline in
      guard case .image(_, .asset(let id)) = inline else { return nil }
      return id
    }
  }

  private func allInlines(in document: AnyDocDocument) -> [AnyDocDocument.Inline] {
    allBlocks(in: document).flatMap { block in
      switch block {
      case .heading(_, _, let content), .paragraph(let content):
        return flatten(inlines: content)
      default:
        return []
      }
    }
  }

  private func flatten(inlines: [AnyDocDocument.Inline]) -> [AnyDocDocument.Inline] {
    inlines.flatMap { inline in
      if case .link(let content, _) = inline {
        return [inline] + flatten(inlines: content)
      }
      return [inline]
    }
  }

  private func allBlocks(in document: AnyDocDocument) -> [AnyDocDocument.Block] {
    flatten(blocks: document.blocks) + document.notes.flatMap { flatten(blocks: $0.blocks) }
  }

  private func flatten(blocks: [AnyDocDocument.Block]) -> [AnyDocDocument.Block] {
    blocks.flatMap { block in
      switch block {
      case .list(let list):
        return [block] + list.items.flatMap { flatten(blocks: $0.blocks) }
      case .table(let table):
        return [block]
          + table.grid.flatMap { row -> [AnyDocDocument.Block] in
            row.flatMap { slot -> [AnyDocDocument.Block] in
              guard case .origin(let cell) = slot else { return [] }
              return flatten(blocks: cell.blocks)
            }
          }
      case .blockQuote(let nested):
        return [block] + flatten(blocks: nested)
      default:
        return [block]
      }
    }
  }
}
