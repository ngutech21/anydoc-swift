import Foundation
import XCTest
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import AnyDocSwift

/// Records requests before invoking the offline response script.
final class HostedTransportProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  private let respond: @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)

  init(
    respond: @escaping @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse) = {
      request, _ in hostedReply(request)
    }
  ) {
    self.respond = respond
  }

  var requests: [URLRequest] { lock.withLock { recorded } }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let index = lock.withLock {
      recorded.append(request)
      return recorded.count - 1
    }
    return try await respond(request, index)
  }
}

func hostedReply(
  _ request: URLRequest,
  status: Int = 200,
  json: String = #"{"success":true,"data":{"markdown":"OCR result"}}"#,
  headers: [String: String] = [:]
) -> (Data, HTTPURLResponse) {
  (
    Data(json.utf8),
    HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
  )
}

func ocrBridge() -> FakeNativeBridge {
  FakeNativeBridge { _ in .needsOCR(pages: [2], pageCount: 3) }
}

func hostedConverter(
  bridge: FakeNativeBridge = ocrBridge(),
  transport: HostedTransportProbe,
  environment: [String: String] = [:],
  limits: AnyDocConverter.Limits = .standard
) -> AnyDocConverter {
  AnyDocConverter(
    limits: limits, adapter: bridge.makeAdapter(), enqueue: immediateEnqueue,
    hostedOCR: HostedOCRAdapter(transport: transport.send, environment: { environment })
  )
}

/// A single-use, cancellation-aware event. Completion can precede registration.
/// Tests release it explicitly; no wall-clock sleep controls an interleaving.
final class HostedEvent: @unchecked Sendable {
  let waiting = XCTestExpectation(description: "hosted operation waiting")
  let cancelled = XCTestExpectation(description: "hosted operation cancelled")
  private let lock = NSLock()
  private var result: Result<Void, any Error>?
  private var continuation: CheckedContinuation<Void, any Error>?

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let completed = lock.withLock { () -> Result<Void, any Error>? in
          if let result { return result }
          self.continuation = continuation
          return nil as Result<Void, any Error>?
        }
        if let completed { continuation.resume(with: completed) }
        waiting.fulfill()
      }
    } onCancel: {
      self.finish(.failure(CancellationError()))
      self.cancelled.fulfill()
    }
  }

  func release() { finish(.success(())) }

  private func finish(_ result: Result<Void, any Error>) {
    let pending = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
      guard self.result == nil else { return nil as CheckedContinuation<Void, any Error>? }
      self.result = result
      let pending = continuation
      continuation = nil
      return pending
    }
    pending?.resume(with: result)
  }
}
