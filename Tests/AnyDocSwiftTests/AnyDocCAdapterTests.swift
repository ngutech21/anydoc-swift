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
      "AnyDoc 0.2.3 (bf3d33e61731580d1ee1c6a85e56093d715a21a6); AnyDocSwift bridge ABI 1"
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

    let mismatch = FakeNativeBridge(abiVersion: 2)
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
    let mismatched = FakeNativeBridge(abiVersion: 2).makeAdapter()
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
