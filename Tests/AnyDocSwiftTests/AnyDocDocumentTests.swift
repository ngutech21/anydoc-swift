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
}
