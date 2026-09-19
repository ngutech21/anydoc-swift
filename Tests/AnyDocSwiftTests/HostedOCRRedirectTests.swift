import Foundation
import XCTest
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import AnyDocSwift

final class HostedOCRRedirectTests: XCTestCase, @unchecked Sendable {
  func testRedirectMethodsBodiesAndSameOriginAuthorization() async throws {
    for status in [301, 302, 303, 307, 308] {
      let transport = HostedTransportProbe { request, index in
        index == 0
          ? hostedReply(request, status: status, headers: ["Location": "/destination"])
          : hostedReply(request)
      }
      _ = try await hostedConverter(transport: transport).markdown(
        from: Data([0, 1, 255]), ocr: .hosted(apiKey: "secret", apiURL: "https://example.test")
      )
      let requests = transport.requests
      XCTAssertEqual(requests.count, 2)
      XCTAssertEqual(requests[1].url?.absoluteString, "https://example.test/destination")
      XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
      if [307, 308].contains(status) {
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(requests[1].httpBody, requests[0].httpBody)
        XCTAssertEqual(
          requests[1].value(forHTTPHeaderField: "Content-Type"),
          requests[0].value(forHTTPHeaderField: "Content-Type"))
      } else {
        XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertNil(requests[1].httpBody)
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Content-Type"))
      }
    }
  }

  func testCrossOriginCredentialsAreRemovedAndNeverRestored() async throws {
    for destination in [
      "https://other.test/next", "http://example.test/next", "https://example.test:444/next",
    ] {
      let transport = HostedTransportProbe { request, index in
        switch index {
        case 0: hostedReply(request, status: 307, headers: ["Location": destination])
        case 1:
          hostedReply(request, status: 308, headers: ["Location": "https://example.test/back"])
        default: hostedReply(request)
        }
      }
      _ = try await hostedConverter(transport: transport).markdown(
        from: Data([1]), ocr: .hosted(apiKey: "secret", apiURL: "https://example.test")
      )
      XCTAssertEqual(transport.requests.count, 3)
      for request in transport.requests.dropFirst() {
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.httpBody, transport.requests[0].httpBody)
      }
    }
    let transport = HostedTransportProbe { request, index in
      index == 0
        ? hostedReply(request, status: 307, headers: ["Location": "https://example.test:443/next"])
        : hostedReply(request)
    }
    _ = try await hostedConverter(transport: transport).markdown(
      from: Data([1]), ocr: .hosted(apiKey: "secret", apiURL: "https://example.test")
    )
    XCTAssertEqual(
      transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
  }

  func testTwentyRedirectsAreAllowedAndTwentyFirstFailsWithoutRetry() async throws {
    for succeeds in [true, false] {
      let transport = HostedTransportProbe { request, index in
        index == 20 && succeeds
          ? hostedReply(request)
          : hostedReply(request, status: 307, headers: ["Location": "/next/\(index)"])
      }
      do {
        _ = try await hostedConverter(transport: transport).markdown(
          from: Data([1]), ocr: .hosted())
        XCTAssertTrue(succeeds)
      } catch {
        XCTAssertFalse(succeeds)
        XCTAssertEqual(error as? AnyDocConversionError, .hostedOCR(.transport))
      }
      XCTAssertEqual(transport.requests.count, 21)
    }
  }

  func testRedirectFailureAndPOSTToGETThenPreservation() async throws {
    let transport = HostedTransportProbe { request, index in
      switch index {
      case 0: hostedReply(request, status: 302, headers: ["Location": "/get"])
      case 1: hostedReply(request, status: 307, headers: ["Location": "relative"])
      default: hostedReply(request)
      }
    }
    _ = try await hostedConverter(transport: transport).markdown(from: Data([1]), ocr: .hosted())
    XCTAssertEqual(transport.requests.map(\.httpMethod), ["POST", "GET", "GET"])
    XCTAssertNil(transport.requests[2].httpBody)
    XCTAssertEqual(transport.requests[2].url?.absoluteString, "https://api.firecrawl.dev/relative")
    for location in ["file:///secret", "https://user:secret@example.test"] {
      let invalid = HostedTransportProbe { request, _ in
        hostedReply(request, status: 302, headers: ["Location": location])
      }
      do {
        _ = try await hostedConverter(transport: invalid).markdown(from: Data([1]), ocr: .hosted())
        XCTFail("Expected transport failure")
      } catch {
        XCTAssertEqual(error as? AnyDocConversionError, .hostedOCR(.transport))
      }
      XCTAssertEqual(invalid.requests.count, 1)
    }
  }
}
