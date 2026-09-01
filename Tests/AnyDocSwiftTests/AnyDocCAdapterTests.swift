import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocCAdapterTests: XCTestCase {
  private let limits = AnyDocConverter.Limits(
    maximumInputBytes: 128,
    maximumOutputBytes: 64
  )

  func testLiveAdapterReportsPinnedVersionAndConvertsRealFixtures() throws {
    XCTAssertEqual(
      try AnyDocCAdapter.live.engineVersion(),
      "AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 2"
    )

    let rtf = try AnyDocCAdapter.live.markdown(
      from: fixtureData("rtf/handmade-blockstyle.rtf"),
      fileExtension: nil,
      limits: .standard
    )
    XCTAssertTrue(rtf.contains("fn main()"))

    let csv = try AnyDocCAdapter.live.markdown(
      from: fixtureData("csv/handmade-quoted.csv"),
      fileExtension: "csv",
      limits: .standard
    )
    XCTAssertTrue(csv.contains("| padded | comma, inside | 3 |"))

    let ocrCases: [(String, AnyDocConversionError)] = [
      ("pdf/handmade-mixed.pdf", .needsOCR(pages: [2], pageCount: 2)),
      ("pdf/handmade-scanned.pdf", .needsOCR(pages: [1, 2], pageCount: 2)),
    ]
    for (fixture, expectedError) in ocrCases {
      XCTAssertThrowsError(
        try AnyDocCAdapter.live.markdown(
          from: fixtureData(fixture),
          fileExtension: nil,
          limits: .standard
        )
      ) { error in
        XCTAssertEqual(error as? AnyDocConversionError, expectedError)
      }
    }
  }

  func testAdapterPassesBytesHintAndLimitsToNativeBridge() throws {
    let bridge = FakeNativeBridge()
    let adapter = bridge.makeAdapter()
    let data = Data([0, 1, 2, 3])

    _ = try adapter.markdown(from: data, fileExtension: "rtf", limits: limits)

    XCTAssertEqual(
      bridge.invocations,
      [
        FakeNativeBridge.Invocation(
          data: data,
          fileExtension: "rtf",
          maximumInputBytes: 128,
          maximumOutputBytes: 64
        )
      ]
    )
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testKnownAndUnknownErrorCodesMapWithoutParsingMessages() throws {
    let mappings: [(String, AnyDocConversionError)] = [
      ("wrapper.invalidInput", .invalidInput("synthetic failure")),
      ("wrapper.inputLimit", .inputTooLarge(actualBytes: 3, maximumBytes: 128)),
      ("wrapper.outputLimit", .outputTooLarge(maximumBytes: 64)),
      ("unsupported", .unsupported("synthetic failure")),
      ("malformed", .malformed("synthetic failure")),
      ("encrypted", .encrypted("synthetic failure")),
      ("resourceLimit", .resourceLimit("synthetic failure")),
      ("missingPart", .missingPart("synthetic failure")),
      ("io", .io("synthetic failure")),
      ("bridge.panic", .bridgeFailure("synthetic failure")),
      (
        "future.upstreamCode",
        .unrecognizedUpstream(code: "future.upstreamCode", message: "synthetic failure")
      ),
    ]

    for (code, expectedError) in mappings {
      let bridge = FakeNativeBridge(responseProvider: { _ in .failure(code: code) })
      let adapter = bridge.makeAdapter()

      XCTAssertThrowsError(
        try adapter.markdown(from: Data([1, 2, 3]), fileExtension: nil, limits: limits)
      ) { error in
        XCTAssertEqual(error as? AnyDocConversionError, expectedError)
      }
      XCTAssertEqual(bridge.freeCount, 1)
    }
  }

  func testNeedsOCRMapsStructuredMetadataWithoutParsingTheMessage() {
    let bridge = FakeNativeBridge(responseProvider: { _ in
      .needsOCR(
        pages: [2, 4],
        pageCount: 5,
        message: "This display text intentionally contains no page numbers."
      )
    })
    let adapter = bridge.makeAdapter()

    XCTAssertThrowsError(
      try adapter.markdown(from: Data([1]), fileExtension: nil, limits: limits)
    ) { error in
      XCTAssertEqual(
        error as? AnyDocConversionError,
        .needsOCR(pages: [2, 4], pageCount: 5)
      )
    }
    XCTAssertEqual(bridge.pageCopyCount, 1)
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testOutputLimitIsCheckedBeforeCopyingNativeMarkdown() {
    let bridge = FakeNativeBridge(responseProvider: { _ in .success("12345") })
    let adapter = bridge.makeAdapter()
    let limits = AnyDocConverter.Limits(maximumInputBytes: 10, maximumOutputBytes: 4)

    XCTAssertThrowsError(
      try adapter.markdown(from: Data([1]), fileExtension: nil, limits: limits)
    ) { error in
      XCTAssertEqual(
        error as? AnyDocConversionError,
        .outputTooLarge(maximumBytes: 4)
      )
    }
    XCTAssertEqual(bridge.copyCount, 0)
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testMalformedNativeResultsBecomeBridgeFailuresAndAreFreed() {
    let responses: [FakeNativeBridge.Response] = [
      .init(status: 7, markdown: nil, errorCode: nil, errorMessage: nil),
      .init(status: 1, markdown: [0xff], errorCode: nil, errorMessage: nil),
      .init(
        status: 1,
        markdown: Array("ok".utf8),
        errorCode: Array("unexpected".utf8),
        errorMessage: nil
      ),
      .init(status: 0, markdown: nil, errorCode: nil, errorMessage: Array("message".utf8)),
      .init(
        status: 0,
        markdown: nil,
        errorCode: [0xff],
        errorMessage: Array("message".utf8)
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: Array("unsupported".utf8),
        errorMessage: [0xff]
      ),
    ]

    for response in responses {
      let bridge = FakeNativeBridge(responseProvider: { _ in response })
      let adapter = bridge.makeAdapter()

      XCTAssertThrowsError(
        try adapter.markdown(from: Data([1]), fileExtension: nil, limits: limits)
      ) { error in
        guard case .bridgeFailure = error as? AnyDocConversionError else {
          return XCTFail("Expected bridgeFailure, got \(error)")
        }
      }
      XCTAssertEqual(bridge.freeCount, 1)
    }
  }

  func testMalformedOCRMetadataBecomesBridgeFailureAndIsFreed() {
    let needsOCRCode = Array("needsOcr".utf8)
    let unsupportedCode = Array("unsupported".utf8)
    let message = Array("synthetic failure".utf8)
    let responses: [FakeNativeBridge.Response] = [
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: nil,
        ocrPageCount: 2
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [],
        ocrPageCount: 0
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [1],
        ocrPageCount: 0
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [0],
        ocrPageCount: 2
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [3],
        ocrPageCount: 2
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [2, 1],
        ocrPageCount: 2
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: needsOCRCode,
        errorMessage: message,
        ocrPages: [1, 1],
        ocrPageCount: 2
      ),
      .init(
        status: 1,
        markdown: Array("ok".utf8),
        errorCode: nil,
        errorMessage: nil,
        ocrPages: [1],
        ocrPageCount: 1
      ),
      .init(
        status: 0,
        markdown: nil,
        errorCode: unsupportedCode,
        errorMessage: message,
        ocrPages: [1],
        ocrPageCount: 1
      ),
    ]

    for response in responses {
      let bridge = FakeNativeBridge(responseProvider: { _ in response })

      XCTAssertThrowsError(
        try bridge.makeAdapter().markdown(from: Data([1]), fileExtension: nil, limits: limits)
      ) { error in
        guard case .bridgeFailure = error as? AnyDocConversionError else {
          return XCTFail("Expected bridgeFailure, got \(error)")
        }
      }
      XCTAssertEqual(bridge.freeCount, 1)
    }
  }

  func testOCRLengthIsValidatedBeforeCopyingNativePages() {
    let response = FakeNativeBridge.Response(
      status: 0,
      markdown: nil,
      errorCode: Array("needsOcr".utf8),
      errorMessage: Array("synthetic failure".utf8),
      ocrPages: [1],
      ocrPageCount: 1,
      reportedOCRPagesLength: 2
    )
    let bridge = FakeNativeBridge(responseProvider: { _ in response })

    XCTAssertThrowsError(
      try bridge.makeAdapter().markdown(from: Data([1]), fileExtension: nil, limits: limits)
    ) { error in
      guard case .bridgeFailure = error as? AnyDocConversionError else {
        return XCTFail("Expected bridgeFailure, got \(error)")
      }
    }
    XCTAssertEqual(bridge.pageCopyCount, 0)
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testMissingHandleAndABIMismatchBecomeBridgeFailuresWithoutFreeing() {
    let missing = FakeNativeBridge(responseProvider: { _ in nil })
    XCTAssertThrowsError(
      try missing.makeAdapter().markdown(from: Data(), fileExtension: nil, limits: limits)
    ) { error in
      guard case .bridgeFailure = error as? AnyDocConversionError else {
        return XCTFail("Expected bridgeFailure, got \(error)")
      }
    }
    XCTAssertEqual(missing.freeCount, 0)

    let mismatch = FakeNativeBridge(abiVersion: 1)
    XCTAssertThrowsError(
      try mismatch.makeAdapter().markdown(from: Data(), fileExtension: nil, limits: limits)
    ) { error in
      guard case .bridgeFailure = error as? AnyDocConversionError else {
        return XCTFail("Expected bridgeFailure, got \(error)")
      }
    }
    XCTAssertTrue(mismatch.invocations.isEmpty)
    XCTAssertEqual(mismatch.freeCount, 0)
  }

  func testEngineVersionUsesSafeFallbackForEveryBridgeFailure() {
    let mismatched = FakeNativeBridge(abiVersion: 1).makeAdapter()
    let missing = FakeNativeBridge(versionBytes: nil).makeAdapter()
    let invalidUTF8 = FakeNativeBridge(versionBytes: [0xff]).makeAdapter()

    for adapter in [mismatched, missing, invalidUTF8] {
      XCTAssertEqual(
        AnyDocConverter.engineVersion(using: adapter),
        AnyDocConverter.unavailableEngineVersion
      )
    }
  }
}
