import Dispatch
import Foundation
import XCTest
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import AnyDocSwift

final class HostedOCRConcurrencyTests: XCTestCase, @unchecked Sendable {
  func testCancellationBeforeDispatchAndWhileNativeWorkIsQueuedSkipsBothStages() async {
    let transport = HostedTransportProbe()
    let bridge = ocrBridge()
    let converter = hostedConverter(bridge: bridge, transport: transport)
    let start = AsyncStartGate()
    let beforeDispatch = Task {
      await start.wait()
      return try await converter.markdown(from: Data([1]), ocr: .hosted())
    }
    await fulfillment(of: [start.waiting], timeout: 5)
    beforeDispatch.cancel()
    start.release()
    await expectCancellation(beforeDispatch)

    let scheduler = ManualScheduler()
    let queuedConverter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: scheduler.enqueue,
      hostedOCR: .init(transport: transport.send, environment: { [:] })
    )
    let queued = Task { try await queuedConverter.markdown(from: Data([1]), ocr: .hosted()) }
    await fulfillment(of: [scheduler.enqueued], timeout: 5)
    queued.cancel()
    scheduler.runNext()
    await expectCancellation(queued)
    XCTAssertTrue(bridge.invocations.isEmpty)
    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertEqual(bridge.freeCount, 0)
  }

  func testCancellationDuringNativeParsingCleansUpBeforePreventingFallback() async {
    let native = BlockingGate(description: "native parsing active")
    let bridge = FakeNativeBridge { _ in
      native.block()
      return .needsOCR(pages: [1], pageCount: 1)
    }
    let transport = HostedTransportProbe()
    let queue = DispatchQueue(label: "hosted-native-cancellation")
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: { queue.async(execute: $0) },
      hostedOCR: .init(transport: transport.send, environment: { [:] })
    )
    let task = Task { try await converter.markdown(from: Data([1]), ocr: .hosted()) }
    await fulfillment(of: [native.entered], timeout: 5)
    task.cancel()
    XCTAssertEqual(bridge.freeCount, 0)
    native.release()
    await expectCancellation(task)
    XCTAssertEqual(bridge.freeCount, 1)
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testCancellationDuringConfigurationPreventsRequestDispatch() async {
    let bridge = ocrBridge()
    let transport = HostedTransportProbe()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: immediateEnqueue,
      hostedOCR: .init(
        transport: transport.send,
        environment: {
          withUnsafeCurrentTask { $0?.cancel() }
          return [:]
        }
      )
    )
    let task = Task { try await converter.markdown(from: Data([1]), ocr: .hosted()) }
    await expectCancellation(task)
    XCTAssertEqual(bridge.freeCount, 1)
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testActiveHTTPCancellationWinsOverConcurrentResponseAndCleansUp() async {
    for status in [200, 401] {
      let activeHTTP = HostedEvent()
      let bridge = ocrBridge()
      let transport = HostedTransportProbe { request, _ in
        // Deliberately return a response even when cancellation wakes transport.
        try? await activeHTTP.wait()
        return hostedReply(request, status: status)
      }
      let converter = hostedConverter(bridge: bridge, transport: transport)
      let task = Task { try await converter.markdown(from: Data([1]), ocr: .hosted()) }
      await fulfillment(of: [activeHTTP.waiting], timeout: 5)
      task.cancel()
      await expectCancellation(task)
      await fulfillment(of: [activeHTTP.cancelled], timeout: 5)
      XCTAssertEqual(bridge.freeCount, 1)
      XCTAssertEqual(transport.requests.count, 1)
    }
  }

  func testFIFOReservationSurvivesHTTPAndFailureAndQueuedCancellation() async throws {
    let http = HostedEvent()
    let admission = AdmissionEvents(count: 4)
    let bridge = FakeNativeBridge { invocation in
      if invocation.data == Data([1]) { return .needsOCR(pages: [1], pageCount: 1) }
      if invocation.operation == .document {
        return .document(
          manifest: #"{"schemaVersion":1,"blocks":[],"notes":[],"assets":[]}"#, assets: [])
      }
      return .success("local")
    }
    let transport = HostedTransportProbe { request, _ in
      try await http.wait()
      return hostedReply(request, status: 503)
    }
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: immediateEnqueue,
      hostedOCR: .init(transport: transport.send, environment: { [:] }), onQueued: admission.record
    )
    let first = Task { try await converter.markdown(from: Data([1]), ocr: .hosted()) }
    await fulfillment(of: [http.waiting], timeout: 5)
    let cancelled = Task { try await converter.markdown(from: Data([2]), ocr: .hosted()) }
    await fulfillment(of: [admission.events[1]], timeout: 5)
    let third = Task { try await converter.document(from: Data([3])) }
    await fulfillment(of: [admission.events[2]], timeout: 5)
    let fourth = Task { try await converter.markdown(from: Data([4])) }
    await fulfillment(of: [admission.events[3]], timeout: 5)
    XCTAssertEqual(bridge.invocations.map(\.data), [Data([1])])
    XCTAssertEqual(bridge.freeCount, 1)
    cancelled.cancel()
    // A queued cancellation completes even while the first HTTP request waits.
    await expectCancellation(cancelled)
    http.release()
    do {
      _ = try await first.value
      XCTFail("Expected server error")
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, .hostedOCR(.server(statusCode: 503)))
    }
    _ = try await third.value
    let last = try await fourth.value
    XCTAssertEqual(last, "local")
    XCTAssertEqual(bridge.invocations.map(\.data), [Data([1]), Data([3]), Data([4])])
    XCTAssertEqual(bridge.freeCount, 3)
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testIndependentConvertersCanHaveConcurrentHostedRequests() async throws {
    let firstEvent = HostedEvent()
    let secondEvent = HostedEvent()
    let firstTransport = HostedTransportProbe { request, _ in
      try await firstEvent.wait()
      return hostedReply(request)
    }
    let secondTransport = HostedTransportProbe { request, _ in
      try await secondEvent.wait()
      return hostedReply(request)
    }
    let first = Task {
      try await hostedConverter(transport: firstTransport).markdown(from: Data([1]), ocr: .hosted())
    }
    let second = Task {
      try await hostedConverter(transport: secondTransport).markdown(
        from: Data([2]), ocr: .hosted())
    }
    await fulfillment(of: [firstEvent.waiting, secondEvent.waiting], timeout: 5)
    firstEvent.release()
    secondEvent.release()
    _ = try await [first.value, second.value]
  }

  func testOneControlledDeadlineCoversRedirectsAndCancelsActiveTransport() async {
    let deadline = HostedEvent()
    let response = HostedEvent()
    let transport = HostedTransportProbe { request, index in
      if index == 0 { return hostedReply(request, status: 307, headers: ["Location": "/redirect"]) }
      try await response.wait()
      return hostedReply(request)
    }
    let converter = AnyDocConverter(
      adapter: ocrBridge().makeAdapter(), enqueue: immediateEnqueue,
      hostedOCR: .init(
        transport: transport.send, environment: { [:] }, waitForDeadline: deadline.wait)
    )
    let task = Task { try await converter.markdown(from: Data([1]), ocr: .hosted()) }
    await fulfillment(of: [deadline.waiting, response.waiting], timeout: 5)
    deadline.release()
    do {
      _ = try await task.value
      XCTFail("Expected deadline failure")
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, .hostedOCR(.transport))
    }
    await fulfillment(of: [response.cancelled], timeout: 5)
    XCTAssertEqual(transport.requests.count, 2)
  }

  func testCancellationReachesProductionURLSessionTaskOffline() async {
    let host = UUID().uuidString.lowercased() + ".test"
    let events = OfflineURLProtocol.Events()
    OfflineURLProtocol.registry.set(events, host: host)
    defer { OfflineURLProtocol.registry.remove(host: host) }
    let bridge = ocrBridge()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: immediateEnqueue,
      hostedOCR: .init(
        transport: { request in
          let configuration = URLSessionConfiguration.ephemeral
          configuration.protocolClasses = [OfflineURLProtocol.self]
          return try await HostedOCRAdapter.send(request, configuration: configuration)
        }, environment: { [:] }
      )
    )
    let task = Task {
      try await converter.markdown(from: Data([1]), ocr: .hosted(apiURL: "https://\(host)"))
    }
    await fulfillment(of: [events.started], timeout: 5)
    task.cancel()
    await expectCancellation(task)
    await fulfillment(of: [events.stopped], timeout: 5)
    XCTAssertEqual(bridge.freeCount, 1)
  }

  private func expectCancellation(_ task: Task<String, any Error>) async {
    do {
      _ = try await task.value
      XCTFail("Expected CancellationError")
    } catch {
      XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
    }
  }
}

private final class AdmissionEvents: @unchecked Sendable {
  let events: [XCTestExpectation]
  private let lock = NSLock()
  private var count = 0

  init(count: Int) {
    events = (0..<count).map { XCTestExpectation(description: "admitted operation \($0)") }
  }

  func record() {
    let index = lock.withLock {
      defer { count += 1 }
      return count
    }
    events[index].fulfill()
  }
}

private final class OfflineURLProtocol: URLProtocol {
  struct Events: Sendable {
    let started = XCTestExpectation(description: "URLSession started protocol")
    let stopped = XCTestExpectation(description: "URLSession stopped protocol")
  }

  final class Registry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Events] = [:]
    func set(_ events: Events, host: String) { lock.withLock { values[host] = events } }
    func remove(host: String) { _ = lock.withLock { values.removeValue(forKey: host) } }
    func get(host: String) -> Events? { lock.withLock { values[host] } }
  }

  static let registry = Registry()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let events = Self.registry.get(host: request.url?.host ?? "") else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    events.started.fulfill()
  }
  override func stopLoading() {
    Self.registry.get(host: request.url?.host ?? "")?.stopped.fulfill()
  }
}

#if !canImport(FoundationNetworking)
  // Darwin's URLProtocol is unchecked Sendable; FoundationNetworking explicitly
  // marks that conformance unavailable. The locked registry is shared on both.
  extension OfflineURLProtocol: @unchecked Sendable {}
#endif
