import AnyDocSwift
import XCTest

final class CMapLimitationTests: XCTestCase, @unchecked Sendable {
  func testUnsupportedJapan1MappingReportsNeedsOCR() async throws {
    let data = try fixtureData("pdf/handmade-cmap-japan1.pdf")
    do {
      _ = try await AnyDocConverter().markdown(from: data, format: .pdf)
      XCTFail("Expected needsOCR for the unsupported Japan1 mapping")
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, .needsOCR(pages: [1], pageCount: 1))
    }
  }

  func testUnsupportedGB1MappingReportsNeedsOCR() async throws {
    let data = try fixtureData("pdf/handmade-cmap-gb1.pdf")
    do {
      _ = try await AnyDocConverter().markdown(from: data, format: .pdf)
      XCTFail("Expected needsOCR for the unsupported GB1 mapping")
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, .needsOCR(pages: [1], pageCount: 1))
    }
  }

  func testUnsupportedCNS1MappingReportsNeedsOCR() async throws {
    let data = try fixtureData("pdf/handmade-cmap-cns1.pdf")
    do {
      _ = try await AnyDocConverter().markdown(from: data, format: .pdf)
      XCTFail("Expected needsOCR for the unsupported CNS1 mapping")
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, .needsOCR(pages: [1], pageCount: 1))
    }
  }
}
