import XCTest

@testable import AnyDocSwift

final class AnyDocConversionErrorTests: XCTestCase {
  func testEveryErrorHasANonEmptyLocalizedDescription() {
    let errors: [AnyDocConversionError] = [
      .inputTooLarge(actualBytes: 2, maximumBytes: 1),
      .outputTooLarge(maximumBytes: 1),
      .invalidInput("invalid"),
      .unsupported("unsupported"),
      .needsOCR("OCR required"),
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
}
