import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocConverterTests: XCTestCase, @unchecked Sendable {
  func testPublicConverterUsesContentFirstDetectionAndCSVFallback() async throws {
    let converter = AnyDocConverter()
    let rtfData = try fixtureData("rtf/handmade-blockstyle.rtf")

    let rtf = try await converter.markdown(from: rtfData, fileExtension: "csv")
    XCTAssertTrue(rtf.contains("fn main()"))

    let csvData = try fixtureData("csv/handmade-quoted.csv")
    let csv = try await converter.markdown(from: csvData, fileExtension: " .CSV ")
    XCTAssertTrue(csv.contains("| padded | comma, inside | 3 |"))

    do {
      _ = try await converter.markdown(from: csvData)
      XCTFail("Expected unsupported CSV without an extension hint")
    } catch {
      guard case .unsupported = error as? AnyDocConversionError else {
        return XCTFail("Expected unsupported, got \(error)")
      }
    }
  }

  func testPublicEngineVersionReportsPinnedBridge() {
    XCTAssertEqual(
      AnyDocConverter.engineVersion,
      "AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 2"
    )
  }

  func testStandardLimitsMatchThePublicContract() {
    XCTAssertEqual(
      AnyDocConverter.Limits.standard,
      AnyDocConverter.Limits(
        maximumInputBytes: 64 * 1024 * 1024,
        maximumOutputBytes: 16 * 1024 * 1024
      )
    )
  }

  func testExtensionNormalizationAndEmptyHint() async throws {
    let bridge = FakeNativeBridge()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    _ = try await converter.markdown(from: Data([1]), fileExtension: " \n.DoCX\t ")
    _ = try await converter.markdown(from: Data([2]), fileExtension: " . ")
    _ = try await converter.markdown(from: Data([3]), fileExtension: "..PDF")

    XCTAssertEqual(
      bridge.invocations.map(\.fileExtension),
      ["docx", nil, ".pdf"]
    )
  }

  func testEverySupportedExtensionIsForwardedAfterNormalization() async throws {
    let supportedExtensions = [
      "doc", "docx", "docm",
      "ppt", "pps", "pot", "pptx", "pptm", "ppsx", "ppsm",
      "xls", "xlsx", "xlsm", "xlsb",
      "odt", "ods", "odp",
      "rtf", "epub", "csv", "pdf",
    ]
    let bridge = FakeNativeBridge()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    for fileExtension in supportedExtensions {
      _ = try await converter.markdown(
        from: Data([1]),
        fileExtension: " .\(fileExtension.uppercased()) "
      )
    }

    XCTAssertEqual(
      bridge.invocations.compactMap(\.fileExtension),
      supportedExtensions
    )
  }

  func testOverlongExtensionAndInputAreRejectedBeforeNativeWork() async {
    let bridge = FakeNativeBridge()
    let converter = AnyDocConverter(
      limits: .init(maximumInputBytes: 1, maximumOutputBytes: 10),
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    do {
      _ = try await converter.markdown(
        from: Data(),
        fileExtension: String(repeating: "é", count: 33)
      )
      XCTFail("Expected invalidInput")
    } catch {
      guard case .invalidInput = error as? AnyDocConversionError else {
        return XCTFail("Expected invalidInput, got \(error)")
      }
    }

    do {
      _ = try await converter.markdown(from: Data([1, 2]))
      XCTFail("Expected inputTooLarge")
    } catch {
      XCTAssertEqual(
        error as? AnyDocConversionError,
        .inputTooLarge(actualBytes: 2, maximumBytes: 1)
      )
    }

    XCTAssertTrue(bridge.invocations.isEmpty)
  }

  func testPublicConverterSurfacesOCRRequiredFailure() async {
    let bridge = FakeNativeBridge(responseProvider: { _ in
      .needsOCR(
        pages: [2],
        pageCount: 2,
        message: "This display text intentionally contains no page numbers."
      )
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    do {
      _ = try await converter.markdown(from: Data([1]))
      XCTFail("Expected needsOCR")
    } catch {
      XCTAssertEqual(
        error as? AnyDocConversionError,
        .needsOCR(pages: [2], pageCount: 2)
      )
    }
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testPublicConverterReportsOCRRequiredForRealPDFFixtures() async throws {
    let converter = AnyDocConverter()

    let cases: [(String, AnyDocConversionError)] = [
      ("pdf/handmade-mixed.pdf", .needsOCR(pages: [2], pageCount: 2)),
      ("pdf/handmade-scanned.pdf", .needsOCR(pages: [1, 2], pageCount: 2)),
    ]
    for (fixture, expectedError) in cases {
      do {
        _ = try await converter.markdown(from: fixtureData(fixture))
        XCTFail("Expected needsOCR for \(fixture)")
      } catch {
        XCTAssertEqual(error as? AnyDocConversionError, expectedError)
      }
    }
  }

  func testCancellationBeforeDispatchSkipsNativeWork() async {
    let bridge = FakeNativeBridge()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )
    let startGate = AsyncStartGate()
    let task = Task {
      await startGate.wait()
      return try await converter.markdown(from: Data([1]))
    }

    await fulfillment(of: [startGate.waiting])
    task.cancel()
    startGate.release()

    do {
      _ = try await task.value
      XCTFail("Expected CancellationError")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertTrue(bridge.invocations.isEmpty)
  }

  func testCancellationWhileQueuedSkipsNativeWork() async {
    let bridge = FakeNativeBridge()
    let scheduler = ManualScheduler()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: scheduler.enqueue
    )
    let task = Task {
      try await converter.markdown(from: Data([1]))
    }

    await fulfillment(of: [scheduler.enqueued])
    task.cancel()
    scheduler.runNext()

    do {
      _ = try await task.value
      XCTFail("Expected CancellationError")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertTrue(bridge.invocations.isEmpty)
    XCTAssertEqual(bridge.freeCount, 0)
  }

  func testCancellationDuringNativeCallWaitsForCleanupAndWinsOverResult() async {
    let gate = BlockingGate(description: "native conversion started")
    let bridge = FakeNativeBridge(responseProvider: { _ in
      gate.block()
      return .failure(code: "unsupported")
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "active-cancellation")
    )
    let task = Task {
      try await converter.markdown(from: Data([1]))
    }

    await fulfillment(of: [gate.entered])
    task.cancel()
    XCTAssertEqual(bridge.freeCount, 0)
    gate.release()

    do {
      _ = try await task.value
      XCTFail("Expected CancellationError")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testOneConverterRunsFIFOWithoutOverlappingNativeCalls() async throws {
    let firstGate = BlockingGate(description: "first native conversion started")
    let probe = ActivityProbe()
    let bridge = FakeNativeBridge(responseProvider: { invocation in
      let value = invocation.fileExtension ?? "none"
      probe.enter(value)
      if value == "first" {
        firstGate.block()
      }
      probe.leave()
      return .success(value)
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "fifo")
    )

    let first = Task {
      try await converter.markdown(from: Data([1]), fileExtension: "first")
    }
    await fulfillment(of: [firstGate.entered])
    let second = Task {
      try await converter.markdown(from: Data([2]), fileExtension: "second")
    }
    firstGate.release()

    let values = try await [first.value, second.value]
    let snapshot = probe.snapshot()
    XCTAssertEqual(values, ["first", "second"])
    XCTAssertEqual(snapshot.order, ["first", "second"])
    XCTAssertEqual(snapshot.maximumActiveCount, 1)
  }

  func testDifferentConvertersMayRunNativeCallsConcurrently() async throws {
    let gate = BlockingGate(
      description: "both native conversions started",
      expectedFulfillmentCount: 2
    )
    let probe = ActivityProbe()
    let bridge = FakeNativeBridge(responseProvider: { invocation in
      let value = invocation.fileExtension ?? "none"
      probe.enter(value)
      gate.block()
      probe.leave()
      return .success(value)
    })
    let firstConverter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "concurrent-one")
    )
    let secondConverter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "concurrent-two")
    )

    let first = Task {
      try await firstConverter.markdown(from: Data([1]), fileExtension: "one")
    }
    let second = Task {
      try await secondConverter.markdown(from: Data([2]), fileExtension: "two")
    }

    await fulfillment(of: [gate.entered])
    gate.release(count: 2)
    _ = try await [first.value, second.value]

    XCTAssertEqual(probe.snapshot().maximumActiveCount, 2)
  }

  func testNativeConversionDoesNotBlockMainActor() async throws {
    let gate = BlockingGate(description: "native conversion started")
    let bridge = FakeNativeBridge(responseProvider: { _ in
      gate.block()
      return .success("done")
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "main-actor")
    )
    let task = Task { @MainActor in
      try await converter.markdown(from: Data([1]))
    }

    await fulfillment(of: [gate.entered])
    let mainActorRemainedResponsive = await MainActor.run { true }
    XCTAssertTrue(mainActorRemainedResponsive)
    gate.release()
    let result = try await task.value
    XCTAssertEqual(result, "done")
  }

  private func serialEnqueue(label: String) -> AnyDocConverter.Enqueue {
    let queue = DispatchQueue(label: "io.ngutech21.AnyDocSwiftTests.\(label)")
    return { operation in
      queue.async(execute: operation)
    }
  }
}
