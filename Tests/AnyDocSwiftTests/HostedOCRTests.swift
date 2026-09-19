import Foundation
import XCTest
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import AnyDocSwift

/// Conformance cases from node/anydoc.js and python/anydoc/__init__.py at
/// 42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c. Node is the tie-breaker.
final class HostedOCRTests: XCTestCase, @unchecked Sendable {
  func testOnlyStructuredOCRFailureCanOptIntoHostedConversion() async throws {
    let transport = HostedTransportProbe()
    let rejected = hostedConverter(transport: transport, environment: ["FIRECRAWL_API_KEY": "env"])
    await expect(.needsOCR(pages: [2], pageCount: 3)) {
      try await rejected.markdown(from: Data([1]))
    }
    await expect(.needsOCR(pages: [2], pageCount: 3)) {
      try await rejected.markdown(from: Data([1]), ocr: .reject)
    }
    let local = hostedConverter(
      bridge: FakeNativeBridge { _ in .success("local") }, transport: transport
    )
    let result = try await local.markdown(from: Data([1]), ocr: .hosted(apiURL: ""))
    XCTAssertEqual(result, "local")
    for code in ["unsupported", "malformed", "encrypted", "resourceLimit", "io", "futureCode"] {
      let bridge = FakeNativeBridge { _ in .failure(code: code, message: "needsOcr") }
      let converter = hostedConverter(bridge: bridge, transport: transport)
      do {
        _ = try await converter.markdown(from: Data([1]), ocr: .hosted())
        XCTFail("Expected native error for \(code)")
      } catch {
        XCTAssertFalse(error is CancellationError)
        if case .hostedOCR = error as? AnyDocConversionError { XCTFail("Unexpected fallback") }
      }
      XCTAssertEqual(bridge.freeCount, 1)
    }
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testRealPDFsUseLocalSuccessOrUploadTheCompleteOriginal() async throws {
    for format: AnyDocFormat? in [nil, .pdf] {
      for fixture in ["text.pdf", "handmade-mixed.pdf", "handmade-scanned.pdf"] {
        let data = try fixtureData("pdf/\(fixture)")
        let transport = HostedTransportProbe()
        let converter = AnyDocConverter(
          adapter: .live, enqueue: immediateEnqueue,
          hostedOCR: .init(transport: transport.send, environment: { [:] })
        )
        let markdown = try await converter.markdown(from: data, format: format, ocr: .hosted())
        if fixture == "text.pdf" {
          XCTAssertFalse(markdown.isEmpty)
          XCTAssertTrue(transport.requests.isEmpty)
        } else {
          XCTAssertEqual(markdown, "OCR result\n")
          XCTAssertEqual(transport.requests.count, 1)
          try assertMultipart(transport.requests[0], pdf: data)
        }
      }
    }
  }

  func testEnvironmentIsResolvedOnlyWhenFallbackBegins() async throws {
    let consulted = XCTestExpectation(description: "environment resolved")
    let bridge = FakeNativeBridge { invocation in
      invocation.data == Data([1]) ? .success("local") : .needsOCR(pages: [1], pageCount: 1)
    }
    let transport = HostedTransportProbe()
    let converter = AnyDocConverter(
      adapter: bridge.makeAdapter(), enqueue: immediateEnqueue,
      hostedOCR: .init(
        transport: transport.send,
        environment: {
          // The native result is already freed before configuration is consulted.
          XCTAssertEqual(bridge.freeCount, 3)
          consulted.fulfill()
          return [:]
        }
      )
    )
    _ = try await converter.markdown(from: Data([1]), ocr: .hosted())
    await expect(.needsOCR(pages: [1], pageCount: 1)) {
      try await converter.markdown(from: Data([2]))
    }
    _ = try await converter.markdown(from: Data([2]), ocr: .hosted())
    await fulfillment(of: [consulted], timeout: 5)
  }

  func testAuthenticationResolutionMatchesNullishNodeOverrides() async throws {
    let cases: [(String?, String?, String?)] = [
      (nil, nil, nil), (nil, "env-key", "Bearer env-key"),
      ("explicit", "env-key", "Bearer explicit"), ("explicit", nil, "Bearer explicit"),
      ("", "env-key", nil), (nil, "", nil), ("", nil, nil),
    ]
    for (key, environmentKey, authorization) in cases {
      let transport = HostedTransportProbe()
      let environment = environmentKey.map { ["FIRECRAWL_API_KEY": $0] } ?? [:]
      let converter = hostedConverter(transport: transport, environment: environment)
      _ = try await converter.markdown(from: Data([1]), ocr: .hosted(apiKey: key))
      XCTAssertEqual(transport.requests.count, 1)
      XCTAssertEqual(
        transport.requests[0].value(forHTTPHeaderField: "Authorization"), authorization)
    }
  }

  func testEndpointResolutionAndExactlyOneTrailingSlashRemoval() async throws {
    let cases: [(String?, String?, String)] = [
      (nil, nil, "https://api.firecrawl.dev/v2/parse"),
      (nil, "https://env.test", "https://env.test/v2/parse"),
      ("https://explicit.test/base", "https://env.test", "https://explicit.test/base/v2/parse"),
      ("http://localhost:8080/", nil, "http://localhost:8080/v2/parse"),
      ("https://example.test///", nil, "https://example.test///v2/parse"),
    ]
    for (url, environmentURL, expected) in cases {
      let transport = HostedTransportProbe()
      let environment = environmentURL.map { ["FIRECRAWL_API_URL": $0] } ?? [:]
      let converter = hostedConverter(transport: transport, environment: environment)
      _ = try await converter.markdown(from: Data([1]), ocr: .hosted(apiURL: url))
      XCTAssertEqual(transport.requests[0].url?.absoluteString, expected)
      XCTAssertEqual(transport.requests[0].timeoutInterval, 300)
    }
    for (url, environment) in [
      ("", ["FIRECRAWL_API_URL": "https://env.test"]),
      (nil, ["FIRECRAWL_API_URL": ""]),
      ("relative", [:]), ("ftp://example.test", [:]), ("https://user:secret@example.test", [:]),
    ] as [(String?, [String: String])] {
      let transport = HostedTransportProbe()
      let converter = hostedConverter(transport: transport, environment: environment)
      await expect(.hostedOCR(.invalidConfiguration)) {
        try await converter.markdown(from: Data([1]), ocr: .hosted(apiURL: url))
      }
      XCTAssertTrue(transport.requests.isEmpty)
    }
  }

  func testMultipartContainsPinnedOptionsThenAllOriginalBytes() async throws {
    let data = Data([0, 255, 13, 10, 0, 128])
    let transport = HostedTransportProbe()
    let bridge = ocrBridge()
    _ = try await hostedConverter(bridge: bridge, transport: transport).markdown(
      from: data, format: .pdf, ocr: .hosted()
    )
    XCTAssertEqual(bridge.invocations.first?.format, "pdf")
    XCTAssertEqual(bridge.freeCount, 1)
    try assertMultipart(transport.requests[0], pdf: data)
  }

  func testSuccessful2xxAndJavaScriptSuccessTruthiness() async throws {
    for status in [200, 201, 202, 206, 299] {
      for success in ["true", "1", "-1", #""yes""#, "[]", "{}"] {
        let transport = HostedTransportProbe { request, _ in
          hostedReply(
            request, status: status, json: "{\"success\":\(success),\"data\":{\"markdown\":\"ok\"}}"
          )
        }
        let result = try await hostedConverter(transport: transport).markdown(
          from: Data([1]), ocr: .hosted())
        XCTAssertEqual(result, "ok\n", "status \(status), success \(success)")
      }
    }
  }

  func testUnsuccessfulOrMalformedResponses() async {
    let invalid =
      [
        "not JSON", "null", "[]", "{}", #"{"success":true}"#,
        #"{"success":true,"data":null}"#, #"{"success":true,"data":{"markdown":""}}"#,
        #"{"success":true,"data":{"markdown":42}}"#, #"{"success":true,"data":{"markdown":false}}"#,
        #"{"success":true,"data":{"markdown":null}}"#,
      ]
      + ["false", "0", "null", #""""#].map {
        "{\"success\":\($0),\"data\":{\"markdown\":\"ok\"}}"
      }
    for json in invalid {
      let transport = HostedTransportProbe { request, _ in hostedReply(request, json: json) }
      await expect(.hostedOCR(.malformedResponse)) {
        try await hostedConverter(transport: transport).markdown(from: Data([1]), ocr: .hosted())
      }
      XCTAssertEqual(transport.requests.count, 1)
    }
    let empty = HostedTransportProbe { request, _ in hostedReply(request, status: 204, json: "") }
    await expect(.hostedOCR(.malformedResponse)) {
      try await hostedConverter(transport: empty).markdown(from: Data([1]), ocr: .hosted())
    }
  }

  func testFinalUTF8LimitIncludesNormalizedNewline() async throws {
    let cases: [(String, UInt64, String?)] = [
      ("é", 3, "é\n"), ("é", 2, nil), ("é\n", 3, "é\n"),
      ("é\n\n", 4, "é\n\n"), ("🦉", 5, "🦉\n"), ("🦉", 4, nil),
      ("\n", 1, "\n"), (" ", 2, " \n"), ("x", 0, nil),
      ("\r\n", 2, "\r\n"), ("x\r\n", 3, "x\r\n"), ("x\r", 3, "x\r\n"),
    ]
    for (markdown, maximum, expected) in cases {
      let body = try JSONSerialization.data(withJSONObject: [
        "success": true, "data": ["markdown": markdown],
      ])
      let transport = HostedTransportProbe { request, _ in
        (body, hostedReply(request).1)
      }
      let converter = hostedConverter(
        transport: transport, limits: .init(maximumInputBytes: 10, maximumOutputBytes: maximum)
      )
      if let expected {
        let actual = try await converter.markdown(from: Data([1]), ocr: .hosted())
        XCTAssertEqual(actual, expected)
      } else {
        await expect(.outputTooLarge(maximumBytes: maximum)) {
          try await converter.markdown(from: Data([1]), ocr: .hosted())
        }
      }
    }
  }

  func testInputLimitPrecedesNativeAndHostedButThereIsNo50MiBCap() async throws {
    let bridge = ocrBridge()
    let transport = HostedTransportProbe()
    let converter = hostedConverter(
      bridge: bridge, transport: transport,
      limits: .init(maximumInputBytes: 1, maximumOutputBytes: 100)
    )
    await expect(.inputTooLarge(actualBytes: 2, maximumBytes: 1)) {
      try await converter.markdown(from: Data([1, 2]), ocr: .hosted())
    }
    XCTAssertTrue(bridge.invocations.isEmpty)
    XCTAssertTrue(transport.requests.isEmpty)
    let largePDF = Data(repeating: 0xAF, count: 50 * 1024 * 1024 + 1)
    _ = try await hostedConverter(transport: transport).markdown(from: largePDF, ocr: .hosted())
    try assertMultipart(transport.requests[0], pdf: largePDF)
  }

  func testTypedHTTPFailuresNeverRetryOrExposeProviderBodies() async {
    let cases: [(Int, AnyDocConversionError.HostedOCRFailure)] = [
      (401, .authentication), (402, .insufficientCredits), (400, .http(statusCode: 400)),
      (413, .http(statusCode: 413)), (302, .http(statusCode: 302)),
      (500, .server(statusCode: 500)), (503, .server(statusCode: 503)),
    ]
    for (status, failure) in cases {
      let transport = HostedTransportProbe { request, _ in
        hostedReply(request, status: status, json: "private-document api-secret")
      }
      await expect(.hostedOCR(failure)) {
        try await hostedConverter(transport: transport).markdown(
          from: Data([1]), ocr: .hosted(apiKey: "api-secret"))
      }
      XCTAssertEqual(transport.requests.count, 1)
    }
    for key: String? in [nil, "", "key"] {
      let transport = HostedTransportProbe { request, _ in hostedReply(request, status: 429) }
      await expect(.hostedOCR(.rateLimited(keyless: key?.isEmpty != false))) {
        try await hostedConverter(transport: transport).markdown(
          from: Data([1]), ocr: .hosted(apiKey: key))
      }
      XCTAssertEqual(transport.requests.count, 1)
    }
    let transport = HostedTransportProbe { _, _ in
      throw NSError(
        domain: "secret", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "private-document api-secret"])
    }
    await expect(.hostedOCR(.transport)) {
      try await hostedConverter(transport: transport).markdown(from: Data([1]), ocr: .hosted())
    }
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testPolicyAndHostedErrorsHaveRedactedDescriptions() {
    let policy = OCRPolicy.hosted(apiKey: "api-secret", apiURL: "https://private-destination.test")
    for description in [String(describing: policy), String(reflecting: policy)] {
      XCTAssertFalse(description.contains("api-secret"))
      XCTAssertFalse(description.contains("private-destination"))
      XCTAssertTrue(description.contains("redacted"))
    }
    XCTAssertEqual(String(describing: OCRPolicy.reject), "reject")
    for failure: AnyDocConversionError.HostedOCRFailure in [
      .invalidConfiguration, .authentication, .insufficientCredits, .rateLimited(keyless: true),
      .rateLimited(keyless: false), .server(statusCode: 503), .http(statusCode: 413), .transport,
      .malformedResponse,
    ] {
      let error = AnyDocConversionError.hostedOCR(failure)
      XCTAssertFalse(error.localizedDescription.isEmpty)
      XCTAssertFalse(error.localizedDescription.contains("api-secret"))
    }
    XCTAssertTrue(
      AnyDocConversionError.hostedOCR(.rateLimited(keyless: true)).localizedDescription.contains(
        "keyless"))
    XCTAssertFalse(
      AnyDocConversionError.hostedOCR(.rateLimited(keyless: false)).localizedDescription.contains(
        "keyless"))
  }

  private func assertMultipart(
    _ request: URLRequest, pdf: Data, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
    let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
    let boundary = try XCTUnwrap(contentType.components(separatedBy: "boundary=").last)
    let body = try XCTUnwrap(request.httpBody)
    let expectedPrefix = Data(
      ("--\(boundary)\r\nContent-Disposition: form-data; name=\"options\"\r\n\r\n"
        + #"{"parsers":[{"type":"pdf","mode":"auto"}],"origin":"anydoc@0.2.4"}"#
        + "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"document.pdf\"\r\n"
        + "Content-Type: application/pdf\r\n\r\n").utf8)
    let suffix = Data("\r\n--\(boundary)--\r\n".utf8)
    XCTAssertEqual(
      body.count, expectedPrefix.count + pdf.count + suffix.count, file: file, line: line)
    XCTAssertEqual(body.prefix(expectedPrefix.count), expectedPrefix, file: file, line: line)
    XCTAssertEqual(
      body.dropFirst(expectedPrefix.count).prefix(pdf.count), pdf, file: file, line: line)
    XCTAssertEqual(body.suffix(suffix.count), suffix, file: file, line: line)
  }

  private func expect(
    _ expected: AnyDocConversionError, file: StaticString = #filePath, line: UInt = #line,
    operation: () async throws -> String
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
      XCTAssertEqual(error as? AnyDocConversionError, expected, file: file, line: line)
    }
  }
}
