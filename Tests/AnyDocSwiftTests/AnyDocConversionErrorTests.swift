import XCTest

@testable import AnyDocSwift

final class AnyDocConversionErrorTests: XCTestCase {
  func testEveryErrorHasANonEmptyLocalizedDescription() {
    let errors: [AnyDocConversionError] = [
      .inputTooLarge(actualBytes: 2, maximumBytes: 1),
      .outputTooLarge(maximumBytes: 1),
      .invalidInput("invalid"),
      .unsupported("unsupported"),
      .needsOCR(pages: [2], pageCount: 3),
      .malformed("malformed"),
      .encrypted("encrypted"),
      .resourceLimit("resource"),
      .missingPart("missing"),
      .io("I/O"),
      .unrecognizedUpstream(code: "future.code", message: "future"),
      .bridgeFailure("bridge"),
    ]

    for error in errors {
      XCTAssertFalse(error.localizedDescription.isEmpty)
    }
  }

  func testNeedsOCRDescriptionsUseStructuredPageMetadata() {
    XCTAssertEqual(
      AnyDocConversionError.needsOCR(pages: [2], pageCount: 3).localizedDescription,
      "Document page 2 of 3 requires optical character recognition."
    )
    XCTAssertEqual(
      AnyDocConversionError.needsOCR(pages: [1, 3], pageCount: 4).localizedDescription,
      "Document pages 1, 3 of 4 require optical character recognition."
    )
    XCTAssertEqual(
      AnyDocConversionError.needsOCR(pages: [1, 2], pageCount: 2).localizedDescription,
      "All 2 document pages require optical character recognition."
    )
  }
}
