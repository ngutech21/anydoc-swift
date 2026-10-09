import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocDocumentDecoderTests: XCTestCase {
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
