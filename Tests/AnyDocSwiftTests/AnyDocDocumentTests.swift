import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocDocumentTests: XCTestCase {
  func testCanonicalFormatsHaveStableRawValues() {
    XCTAssertEqual(
      [
        AnyDocFormat.doc, .docx, .odt, .pdf, .ppt, .pptx, .rtf, .epub, .xlsx, .ods, .odp, .csv,
      ].map(\.rawValue),
      ["doc", "docx", "odt", "pdf", "ppt", "pptx", "rtf", "epub", "xlsx", "ods", "odp", "csv"]
    )
  }

  func testStandardLimitsIncludeTheDocumentWireLimitAndPreserveTheOldInitializer() {
    XCTAssertEqual(AnyDocConverter.Limits.standard.maximumDocumentBytes, 128 * 1024 * 1024)
    XCTAssertEqual(
      AnyDocConverter.Limits(maximumInputBytes: 1, maximumOutputBytes: 2),
      AnyDocConverter.Limits(
        maximumInputBytes: 1,
        maximumOutputBytes: 2,
        maximumDocumentBytes: 128 * 1024 * 1024
      )
    )
  }

  func testCompleteDocumentGraphHasValueSemantics() {
    let style = AnyDocDocument.Style(bold: true, italic: true, strike: true, code: true)
    let blocks: [AnyDocDocument.Block] = [
      .heading(
        level: 2,
        anchor: "heading",
        content: [
          .text(text: "Title", style: style),
          .link(content: [], target: .external("https://example.com")),
          .image(alt: "logo", source: .asset(id: 0)),
          .anchor(id: "anchor"),
          .noteReference(id: "note"),
          .lineBreak,
          .math("x+y"),
          .checkbox(isChecked: true),
        ]
      ),
      .paragraph([]),
      .list(
        .init(
          marker: .decimal,
          start: 3,
          items: [.init(blocks: [.rule], markerLabel: "3)")]
        )
      ),
      .table(
        .init(
          grid: [
            [
              .origin(.init(blocks: [], columnSpan: 2, rowSpan: 1)),
              .covered(originRow: 0, originColumn: 0),
            ]
          ],
          headerRows: 1,
          kind: .data
        )
      ),
      .blockQuote([.rule]),
      .codeBlock(language: "swift", text: "let x = 1"),
      .rule,
      .math("x^2"),
    ]
    let document = AnyDocDocument(
      blocks: blocks,
      notes: [.init(id: "note", kind: .footnote, blocks: [.paragraph([])])],
      assets: [
        .init(
          id: 0,
          mediaType: "image/png",
          originPart: "word/media/image.png",
          bytes: Data([1, 2, 3])
        )
      ]
    )

    XCTAssertEqual(document, document)
    requireSendable(document)
  }

  private func requireSendable<T: Sendable>(_ value: T) {
    _ = value
  }
}
