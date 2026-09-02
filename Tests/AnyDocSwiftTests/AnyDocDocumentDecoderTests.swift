import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocDocumentDecoderTests: XCTestCase {
  func testManifestDecodesEveryPublicVariant() throws {
    let document = try AnyDocDocumentDecoder.decode(
      manifest: data(
        """
        {
          "schemaVersion": 1,
          "blocks": [
            {"kind":"heading","value":{"level":2,"anchor":"h","content":[
              {"kind":"text","value":{"text":"Title","style":{"bold":true,"italic":false,"strike":true,"code":false}}},
              {"kind":"link","value":{"content":[],"target":{"kind":"external","value":"https://example.com"}}},
              {"kind":"link","value":{"content":[],"target":{"kind":"relative","value":"chapter.xml"}}},
              {"kind":"link","value":{"content":[],"target":{"kind":"anchor","value":"h"}}},
              {"kind":"image","value":{"alt":"remote","source":{"kind":"external","value":"https://example.com/a.png"}}},
              {"kind":"image","value":{"alt":"asset","source":{"kind":"asset","value":0}}},
              {"kind":"image","value":{"alt":"missing","source":{"kind":"unavailable"}}},
              {"kind":"anchor","value":"inside"},
              {"kind":"noteRef","value":"n"},
              {"kind":"lineBreak"},
              {"kind":"math","value":"x+y"},
              {"kind":"checkbox","value":true}
            ]}},
            {"kind":"paragraph","value":[]},
            {"kind":"list","value":{"marker":"upperRoman","start":4,"items":[{"blocks":[{"kind":"rule"}],"markerLabel":"IV)"}]}},
            {"kind":"table","value":{"grid":[[
              {"kind":"origin","value":{"blocks":[],"columnSpan":2,"rowSpan":1}},
              {"kind":"covered","value":{"originRow":0,"originColumn":0}}
            ]],"headerRows":1,"kind":"data"}},
            {"kind":"blockQuote","value":[{"kind":"rule"}]},
            {"kind":"codeBlock","value":{"language":"swift","text":"let x = 1"}},
            {"kind":"rule"},
            {"kind":"math","value":"x^2"}
          ],
          "notes": [
            {"id":"n","kind":"footnote","blocks":[]},
            {"id":"e","kind":"endnote","blocks":[]}
          ],
          "assets": [
            {"id":0,"mediaType":"image/png","originPart":"word/media/image.png","byteLength":2}
          ]
        }
        """
      ),
      assetBytes: [Data([1, 2])]
    )

    XCTAssertEqual(document.blocks.count, 8)
    XCTAssertEqual(document.notes.map(\.kind), [.footnote, .endnote])
    XCTAssertEqual(
      document.assets,
      [
        .init(
          id: 0,
          mediaType: "image/png",
          originPart: "word/media/image.png",
          bytes: Data([1, 2])
        )
      ]
    )
    guard case .heading(level: 2, anchor: "h", let content) = document.blocks[0] else {
      return XCTFail("Expected heading")
    }
    XCTAssertEqual(content.count, 12)
  }

  func testMalformedJSONSchemaTagsAndNumbersAreRejected() {
    let manifests = [
      "not json",
      emptyManifest(schemaVersion: "2"),
      emptyManifest(blocks: "[{\"kind\":\"future\"}]"),
      emptyManifest(
        blocks: "[{\"kind\":\"heading\",\"value\":{\"level\":0,\"anchor\":null,\"content\":[]}}]"),
      emptyManifest(
        blocks:
          "[{\"kind\":\"heading\",\"value\":{\"level\":18446744073709551616,\"anchor\":null,\"content\":[]}}]"
      ),
      emptyManifest(blocks: "[{\"kind\":\"paragraph\",\"value\":[{\"kind\":\"future\"}]}]"),
      emptyManifest(
        blocks:
          "[{\"kind\":\"paragraph\",\"value\":[{\"kind\":\"link\",\"value\":{\"content\":[],\"target\":{\"kind\":\"future\",\"value\":\"x\"}}}]}]"
      ),
      emptyManifest(
        blocks:
          "[{\"kind\":\"paragraph\",\"value\":[{\"kind\":\"image\",\"value\":{\"alt\":\"x\",\"source\":{\"kind\":\"future\"}}}]}]"
      ),
      emptyManifest(
        blocks: "[{\"kind\":\"list\",\"value\":{\"marker\":\"future\",\"start\":1,\"items\":[]}}]"),
      emptyManifest(
        blocks:
          "[{\"kind\":\"table\",\"value\":{\"grid\":[],\"headerRows\":0,\"kind\":\"future\"}}]"),
      emptyManifest(
        blocks:
          "[{\"kind\":\"table\",\"value\":{\"grid\":[[{\"kind\":\"future\"}]],\"headerRows\":0,\"kind\":\"data\"}}]"
      ),
      emptyManifest(notes: "[{\"id\":\"n\",\"kind\":\"future\",\"blocks\":[]}]"),
    ]

    for manifest in manifests {
      assertBridgeFailure(manifest: manifest, assets: [])
    }
  }

  func testInvalidAssetMetadataLengthsAndReferencesAreRejected() {
    assertBridgeFailure(
      manifest: emptyManifest(
        assets: "[{\"id\":1,\"mediaType\":\"x\",\"originPart\":\"a\",\"byteLength\":0}]"
      ),
      assets: [Data()]
    )
    assertBridgeFailure(
      manifest: emptyManifest(
        assets: "[{\"id\":0,\"mediaType\":\"x\",\"originPart\":\"a\",\"byteLength\":2}]"
      ),
      assets: [Data([1])]
    )
    assertBridgeFailure(
      manifest: emptyManifest(
        blocks:
          "[{\"kind\":\"paragraph\",\"value\":[{\"kind\":\"image\",\"value\":{\"alt\":\"x\",\"source\":{\"kind\":\"asset\",\"value\":0}}}]}]"
      ),
      assets: []
    )
    assertBridgeFailure(
      manifest: emptyManifest(
        assets:
          "[{\"id\":9223372036854775808,\"mediaType\":\"x\",\"originPart\":\"a\",\"byteLength\":0}]"
      ),
      assets: [Data()]
    )
  }

  func testInvalidCanonicalTablesAreRejected() {
    let tables = [
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":1,\"rowSpan\":1}}]],\"headerRows\":2,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":0,\"rowSpan\":0}}]],\"headerRows\":0,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":0,\"rowSpan\":1}}]],\"headerRows\":0,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":4294967296,\"rowSpan\":1}}]],\"headerRows\":0,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":2,\"rowSpan\":1}}]],\"headerRows\":0,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":2,\"rowSpan\":1}},{\"kind\":\"covered\",\"value\":{\"originRow\":0,\"originColumn\":1}}]],\"headerRows\":0,\"kind\":\"data\"}",
      "{\"grid\":[[{\"kind\":\"covered\",\"value\":{\"originRow\":0,\"originColumn\":0}}]],\"headerRows\":0,\"kind\":\"data\"}",
    ]

    for table in tables {
      assertBridgeFailure(
        manifest: emptyManifest(blocks: "[{\"kind\":\"table\",\"value\":\(table)}]"),
        assets: []
      )
    }
  }

  private func emptyManifest(
    schemaVersion: String = "1",
    blocks: String = "[]",
    notes: String = "[]",
    assets: String = "[]"
  ) -> String {
    "{\"schemaVersion\":\(schemaVersion),\"blocks\":\(blocks),\"notes\":\(notes),\"assets\":\(assets)}"
  }

  private func assertBridgeFailure(manifest: String, assets: [Data]) {
    XCTAssertThrowsError(
      try AnyDocDocumentDecoder.decode(manifest: data(manifest), assetBytes: assets)
    ) { error in
      guard case .bridgeFailure = error as? AnyDocConversionError else {
        return XCTFail("Expected bridgeFailure, got \(error)")
      }
    }
  }

  private func data(_ string: String) -> Data {
    Data(string.utf8)
  }
}
