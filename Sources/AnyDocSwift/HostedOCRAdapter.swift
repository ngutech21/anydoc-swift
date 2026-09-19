import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Swift-owned hosted policy and wire handling; credentials never cross the C ABI.
struct HostedOCRAdapter: Sendable {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

  private let transport: Transport
  private let environment: @Sendable () -> [String: String]
  private let waitForDeadline: @Sendable () async throws -> Void

  init(
    transport: @escaping Transport = { try await send($0) },
    environment: @escaping @Sendable () -> [String: String] = {
      ProcessInfo.processInfo.environment
    },
    waitForDeadline: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .seconds(300))
    }
  ) {
    self.transport = transport
    self.environment = environment
    self.waitForDeadline = waitForDeadline
  }

  func markdown(
    from data: Data, apiKey: String?, apiURL: String?, maximumOutputBytes: UInt64
  ) async throws -> String {
    do {
      try Task.checkCancellation()
      let environment = environment()
      let key = apiKey ?? environment["FIRECRAWL_API_KEY"]
      let baseURL = apiURL ?? environment["FIRECRAWL_API_URL"] ?? "https://api.firecrawl.dev"
      let request = try Self.request(data: data, key: key, baseURL: baseURL)
      try Task.checkCancellation()
      let output = try await withThrowingTaskGroup(of: String.self) { group in
        // One deadline covers every redirect and the complete response body.
        // Both children cooperate with cancellation, so neither request nor
        // deadline work survives the conversion that owns it.
        group.addTask {
          let (body, response) = try await fetch(request)
          try Task.checkCancellation()
          return try Self.markdown(
            body: body, status: response.statusCode, keyless: key?.isEmpty != false,
            maximumOutputBytes: maximumOutputBytes
          )
        }
        group.addTask {
          try await waitForDeadline()
          try Task.checkCancellation()
          throw AnyDocConversionError.hostedOCR(.transport)
        }
        defer { group.cancelAll() }
        guard let output = try await group.next() else {
          throw AnyDocConversionError.hostedOCR(.transport)
        }
        return output
      }
      try Task.checkCancellation()
      return output
    } catch {
      try Task.checkCancellation()
      if let conversionError = error as? AnyDocConversionError {
        switch conversionError {
        case .hostedOCR, .outputTooLarge: throw conversionError
        default: break
        }
      }
      // NSError/userInfo, URLs, and provider errors can contain credentials or
      // document content. Only our fixed typed errors may leave this adapter.
      throw AnyDocConversionError.hostedOCR(.transport)
    }
  }

  private static func request(data: Data, key: String?, baseURL: String) throws -> URLRequest {
    let base =
      baseURL.utf8.last == 0x2F
      ? String(decoding: baseURL.utf8.dropLast(), as: UTF8.self) : baseURL
    guard let url = URL(string: base + "/v2/parse"), validURL(url) else {
      throw AnyDocConversionError.hostedOCR(.invalidConfiguration)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    if let key, !key.isEmpty {
      // Fetch accepts ByteString header values and rejects NUL/CR/LF. An empty
      // key is meaningful (it suppresses environment credentials), not invalid.
      guard key.utf16.allSatisfy({ $0 <= 255 && $0 != 0 && $0 != 10 && $0 != 13 }) else {
        throw AnyDocConversionError.hostedOCR(.invalidConfiguration)
      }
      request.setValue(
        ("Bearer " + key).trimmingCharacters(in: CharacterSet(charactersIn: " \t")),
        forHTTPHeaderField: "Authorization"
      )
    }
    let boundary = "anydoc-swift-" + UUID().uuidString
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    // Mirrors node/anydoc.js at the pinned anydoc revision. Keep the origin in
    // sync with upstream node/package.json when qualifying an engine upgrade.
    let options = #"{"parsers":[{"type":"pdf","mode":"auto"}],"origin":"anydoc@0.2.4"}"#
    var body = Data(
      ("--\(boundary)\r\nContent-Disposition: form-data; name=\"options\"\r\n\r\n"
        + options
        + "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"document.pdf\"\r\n"
        + "Content-Type: application/pdf\r\n\r\n").utf8
    )
    body.append(data)
    body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
    request.httpBody = body
    return request
  }

  private func fetch(_ initialRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var request = initialRequest
    var redirects = 0
    while true {
      try Task.checkCancellation()
      let (body, response) = try await transport(request)
      try Task.checkCancellation()
      guard [301, 302, 303, 307, 308].contains(response.statusCode),
        let location = response.value(forHTTPHeaderField: "Location")
      else { return (body, response) }

      guard redirects < 20, let previousURL = request.url,
        let nextURL = URL(string: location, relativeTo: previousURL)?.absoluteURL,
        Self.validURL(nextURL)
      else { throw AnyDocConversionError.hostedOCR(.transport) }
      redirects += 1
      if !Self.sameOrigin(previousURL, nextURL) {
        request.setValue(nil, forHTTPHeaderField: "Authorization")
      }
      if ((response.statusCode == 301 || response.statusCode == 302)
        && request.httpMethod == "POST")
        || (response.statusCode == 303 && request.httpMethod != "GET"
          && request.httpMethod != "HEAD")
      {
        request.httpMethod = "GET"
        request.httpBody = nil
        for header in [
          "Content-Encoding", "Content-Language", "Content-Location", "Content-Type",
          "Content-Length",
        ] {
          request.setValue(nil, forHTTPHeaderField: header)
        }
      }
      request.url = nextURL
    }
  }

  private static func validURL(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased())
      && url.host?.isEmpty == false && url.user == nil && url.password == nil
  }

  private static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
    func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
    return first.scheme?.lowercased() == second.scheme?.lowercased()
      && first.host?.lowercased() == second.host?.lowercased() && port(first) == port(second)
  }

  private static func markdown(
    body: Data, status: Int, keyless: Bool, maximumOutputBytes: UInt64
  ) throws -> String {
    guard (200..<300).contains(status) else {
      let failure: AnyDocConversionError.HostedOCRFailure
      switch status {
      case 401: failure = .authentication
      case 402: failure = .insufficientCredits
      case 429: failure = .rateLimited(keyless: keyless)
      case 500..<600: failure = .server(statusCode: status)
      default: failure = .http(statusCode: status)
      }
      throw AnyDocConversionError.hostedOCR(failure)
    }
    guard
      let reply = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
      truthy(reply["success"]),
      let data = reply["data"] as? [String: Any],
      let markdown = data["markdown"] as? String, !markdown.isEmpty
    else { throw AnyDocConversionError.hostedOCR(.malformedResponse) }
    // Node checks the final code unit. Swift's Character-based hasSuffix would
    // treat CRLF as one grapheme and incorrectly append another newline.
    let output = markdown.utf8.last == 0x0A ? markdown : markdown + "\n"
    guard UInt64(output.utf8.count) <= maximumOutputBytes else {
      throw AnyDocConversionError.outputTooLarge(maximumBytes: maximumOutputBytes)
    }
    return output
  }

  // Node's `!reply.success` uses JavaScript truthiness, including truthy empty
  // arrays/objects. Keep that behavior instead of silently requiring a Bool.
  private static func truthy(_ value: Any?) -> Bool {
    guard let value, !(value is NSNull) else { return false }
    if let number = value as? NSNumber { return number.doubleValue != 0 }
    if let string = value as? String { return !string.isEmpty }
    return true
  }

  static func send(
    _ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral
  ) async throws -> (Data, HTTPURLResponse) {
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 300
    configuration.timeoutIntervalForResource = 300
    let session = URLSession(
      configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    try Task.checkCancellation()
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw AnyDocConversionError.hostedOCR(.malformedResponse)
    }
    return (data, response)
  }
}

// Immutable delegate: the adapter handles redirects itself so Darwin and
// FoundationNetworking follow the same Fetch policy, including credential removal.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
