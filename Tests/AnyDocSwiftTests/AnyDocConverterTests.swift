import Dispatch
import Foundation
import XCTest

@testable import AnyDocSwift

final class AnyDocConverterTests: XCTestCase, @unchecked Sendable {
  private static let emptyManifest =
    "{\"schemaVersion\":1,\"blocks\":[],\"notes\":[],\"assets\":[]}"
  private static let allVariantsManifest =
    """
    {
      "schemaVersion":1,
      "blocks":[
        {"kind":"heading","value":{"level":7,"anchor":"heading","content":[
          {"kind":"text","value":{"text":"styled","style":{"bold":true,"italic":true,"strike":true,"code":true}}},
          {"kind":"link","value":{"content":[],"target":{"kind":"external","value":"https://example.com"}}},
          {"kind":"link","value":{"content":[],"target":{"kind":"relative","value":"chapter.xml"}}},
          {"kind":"link","value":{"content":[],"target":{"kind":"anchor","value":"inside"}}},
          {"kind":"image","value":{"alt":"remote","source":{"kind":"external","value":"https://example.com/image.png"}}},
          {"kind":"image","value":{"alt":"embedded","source":{"kind":"asset","value":0}}},
          {"kind":"image","value":{"alt":"missing","source":{"kind":"unavailable"}}},
          {"kind":"anchor","value":"inside"},
          {"kind":"noteRef","value":"foot"},
          {"kind":"lineBreak"},
          {"kind":"math","value":"x+y"},
          {"kind":"checkbox","value":true}
        ]}},
        {"kind":"paragraph","value":[]},
        {"kind":"list","value":{"marker":"bullet","start":1,"items":[{"blocks":[{"kind":"rule"}],"markerLabel":"-"}]}},
        {"kind":"list","value":{"marker":"decimal","start":2,"items":[]}},
        {"kind":"list","value":{"marker":"lowerAlpha","start":3,"items":[]}},
        {"kind":"list","value":{"marker":"upperAlpha","start":4,"items":[]}},
        {"kind":"list","value":{"marker":"lowerRoman","start":5,"items":[]}},
        {"kind":"list","value":{"marker":"upperRoman","start":6,"items":[]}},
        {"kind":"table","value":{"grid":[[
          {"kind":"origin","value":{"blocks":[],"columnSpan":2,"rowSpan":1}},
          {"kind":"covered","value":{"originRow":0,"originColumn":0}}
        ]],"headerRows":1,"kind":"data"}},
        {"kind":"table","value":{"grid":[],"headerRows":0,"kind":"layout"}},
        {"kind":"blockQuote","value":[{"kind":"rule"}]},
        {"kind":"codeBlock","value":{"language":"swift","text":"let x = 1"}},
        {"kind":"rule"},
        {"kind":"math","value":"x^2"}
      ],
      "notes":[
        {"id":"foot","kind":"footnote","blocks":[]},
        {"id":"end","kind":"endnote","blocks":[]}
      ],
      "assets":[
        {"id":0,"mediaType":"image/png","originPart":"word/media/image.png","byteLength":1}
      ]
    }
    """

  func testPublicConverterUsesAutomaticOrAuthoritativeFormatSelection() async throws {
    let converter = AnyDocConverter()
    let rtfData = try fixtureData("rtf/handmade-blockstyle.rtf")

    let automaticRTF = try await converter.markdown(from: rtfData)
    XCTAssertTrue(automaticRTF.contains("fn main()"))

    let explicitCSV = try await converter.markdown(from: rtfData, format: .csv)
    XCTAssertNotEqual(explicitCSV, automaticRTF)

    let csvData = try fixtureData("csv/handmade-quoted.csv")
    let csv = try await converter.markdown(from: csvData, format: .csv)
    XCTAssertTrue(csv.contains("| padded | comma, inside | 3 |"))

    do {
      _ = try await converter.markdown(from: csvData)
      XCTFail("Expected unsupported CSV without an explicit format")
    } catch {
      guard case .unsupported = error as? AnyDocConversionError else {
        return XCTFail("Expected unsupported, got \(error)")
      }
    }
  }

  func testPublicEngineVersionReportsPinnedBridge() {
    XCTAssertEqual(
      AnyDocConverter.engineVersion,
      "AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 3"
    )
  }

  func testPublicDocumentConversionExposesEveryModelVariant() async throws {
    let bridge = FakeNativeBridge(responseProvider: { _ in
      .document(manifest: Self.allVariantsManifest, assets: [[0xAA]])
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    let document = try await converter.document(from: Data([1]), format: .docx)

    guard case .heading(level: 7, anchor: "heading", let content) = document.blocks[0] else {
      return XCTFail("Expected heading")
    }
    XCTAssertEqual(
      content,
      [
        .text(text: "styled", style: .init(bold: true, italic: true, strike: true, code: true)),
        .link(content: [], target: .external("https://example.com")),
        .link(content: [], target: .relative("chapter.xml")),
        .link(content: [], target: .anchor("inside")),
        .image(alt: "remote", source: .external("https://example.com/image.png")),
        .image(alt: "embedded", source: .asset(id: 0)),
        .image(alt: "missing", source: .unavailable),
        .anchor(id: "inside"),
        .noteReference(id: "foot"),
        .lineBreak,
        .math("x+y"),
        .checkbox(isChecked: true),
      ]
    )
    XCTAssertEqual(document.blocks[1], .paragraph([]))

    let lists = document.blocks[2...7].map { block -> AnyDocDocument.List in
      guard case .list(let list) = block else {
        XCTFail("Expected list")
        return .init(marker: .bullet, start: 0, items: [])
      }
      return list
    }
    XCTAssertEqual(
      lists.map(\.marker),
      [.bullet, .decimal, .lowerAlpha, .upperAlpha, .lowerRoman, .upperRoman]
    )
    XCTAssertEqual(lists.map(\.start), [1, 2, 3, 4, 5, 6])
    XCTAssertEqual(lists[0].items[0].markerLabel, "-")
    XCTAssertEqual(lists[0].items[0].blocks, [.rule])

    guard case .table(let dataTable) = document.blocks[8],
      case .table(let layoutTable) = document.blocks[9]
    else {
      return XCTFail("Expected tables")
    }
    XCTAssertEqual(dataTable.kind, .data)
    XCTAssertEqual(dataTable.headerRows, 1)
    XCTAssertEqual(dataTable.grid[0][1], .covered(originRow: 0, originColumn: 0))
    guard case .origin(let cell) = dataTable.grid[0][0] else {
      return XCTFail("Expected table origin")
    }
    XCTAssertEqual(cell.columnSpan, 2)
    XCTAssertEqual(cell.rowSpan, 1)
    XCTAssertEqual(layoutTable.kind, .layout)

    XCTAssertEqual(document.blocks[10], .blockQuote([.rule]))
    XCTAssertEqual(document.blocks[11], .codeBlock(language: "swift", text: "let x = 1"))
    XCTAssertEqual(document.blocks[12], .rule)
    XCTAssertEqual(document.blocks[13], .math("x^2"))
    XCTAssertEqual(document.notes.map(\.kind), [.footnote, .endnote])
    XCTAssertEqual(
      document.assets,
      [
        .init(
          id: 0,
          mediaType: "image/png",
          originPart: "word/media/image.png",
          bytes: Data([0xAA])
        )
      ]
    )
    XCTAssertEqual(bridge.invocations.map(\.operation), [.document])
    XCTAssertEqual(bridge.freeCount, 1)
  }

  func testEveryCanonicalFormatIsForwardedUnchanged() async throws {
    let formats: [AnyDocFormat] = [
      .doc, .docx, .odt, .pdf, .ppt, .pptx, .rtf, .epub, .xlsx, .ods, .odp, .csv,
    ]
    let bridge = FakeNativeBridge(responseProvider: { invocation in
      .success(invocation.format ?? "automatic")
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    for format in formats {
      let result = try await converter.markdown(from: Data([1]), format: format)
      XCTAssertEqual(result, format.rawValue)
    }
    XCTAssertEqual(bridge.invocations.map(\.format), formats.map(\.rawValue))
    XCTAssertTrue(bridge.invocations.allSatisfy { $0.operation == .markdown })
  }

  func testInputLimitIsSharedAndRejectedBeforeNativeWork() async {
    let bridge = FakeNativeBridge()
    let converter = AnyDocConverter(
      limits: .init(maximumInputBytes: 1, maximumOutputBytes: 10),
      adapter: bridge.makeAdapter(),
      enqueue: immediateEnqueue
    )

    for operation in [
      { try await converter.markdown(from: Data([1, 2])) as Any },
      { try await converter.document(from: Data([1, 2])) as Any },
    ] {
      do {
        _ = try await operation()
        XCTFail("Expected inputTooLarge")
      } catch {
        XCTAssertEqual(
          error as? AnyDocConversionError,
          .inputTooLarge(actualBytes: 2, maximumBytes: 1)
        )
      }
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

  func testPDFHasNoStructuredDocumentRepresentation() async throws {
    let converter = AnyDocConverter()
    do {
      _ = try await converter.document(from: fixtureData("pdf/text.pdf"), format: .pdf)
      XCTFail("Expected unsupported PDF document conversion")
    } catch {
      guard case .unsupported = error as? AnyDocConversionError else {
        return XCTFail("Expected unsupported, got \(error)")
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

    await fulfillment(of: [startGate.waiting], timeout: 5)
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

  func testDocumentCancellationWhileQueuedSkipsNativeWork() async {
    let bridge = FakeNativeBridge()
    let scheduler = ManualScheduler()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: scheduler.enqueue
    )
    let task = Task {
      try await converter.document(from: Data([1]))
    }

    await fulfillment(of: [scheduler.enqueued], timeout: 5)
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

  func testDocumentCancellationDuringNativeCallWaitsForCleanupAndWins() async {
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
      try await converter.document(from: Data([1]))
    }

    await fulfillment(of: [gate.entered], timeout: 5)
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

  func testMixedMarkdownAndDocumentCallsRemainFIFOWithoutOverlap() async throws {
    let firstGate = BlockingGate(description: "first native conversion started")
    let probe = ActivityProbe()
    let bridge = FakeNativeBridge(responseProvider: { invocation in
      let value = invocation.operation == .markdown ? "markdown" : "document"
      probe.enter(value)
      if invocation.operation == .markdown {
        firstGate.block()
      }
      probe.leave()
      switch invocation.operation {
      case .markdown: return .success("first")
      case .document: return .document(manifest: Self.emptyManifest, assets: [])
      }
    })
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(),
      enqueue: serialEnqueue(label: "mixed-fifo")
    )

    let first = Task {
      try await converter.markdown(from: Data([1]))
    }
    await fulfillment(of: [firstGate.entered], timeout: 5)
    let second = Task {
      try await converter.document(from: Data([2]))
    }
    firstGate.release()

    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue, "first")
    XCTAssertEqual(secondValue, AnyDocDocument(blocks: [], notes: [], assets: []))
    let snapshot = probe.snapshot()
    XCTAssertEqual(snapshot.order, ["markdown", "document"])
    XCTAssertEqual(snapshot.maximumActiveCount, 1)
  }

  func testDifferentConvertersMayRunNativeCallsConcurrently() async throws {
    let gate = BlockingGate(
      description: "both native conversions started",
      expectedFulfillmentCount: 2
    )
    let probe = ActivityProbe()
    let bridge = FakeNativeBridge(responseProvider: { invocation in
      let value = invocation.format ?? "automatic"
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
      try await firstConverter.markdown(from: Data([1]), format: .doc)
    }
    let second = Task {
      try await secondConverter.markdown(from: Data([2]), format: .docx)
    }

    await fulfillment(of: [gate.entered], timeout: 5)
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

    await fulfillment(of: [gate.entered], timeout: 5)
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
