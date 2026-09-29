public import Foundation

/// A typed failure produced while converting document bytes.
///
/// Handle cases directly instead of parsing ``errorDescription``. Task
/// cancellation is reported separately as `CancellationError`.
public enum AnyDocConversionError: Error, Sendable, Equatable, LocalizedError {
  /// The complete input exceeds the converter's input limit.
  case inputTooLarge(actualBytes: UInt64, maximumBytes: UInt64)
  /// The UTF-8 Markdown result exceeds the converter's output limit.
  case outputTooLarge(maximumBytes: UInt64)
  /// The encoded document manifest and assets exceed the structured limit.
  case documentTooLarge(maximumBytes: UInt64)
  /// The engine rejected the input as invalid.
  case invalidInput(String)
  /// The engine does not support the requested input or output form.
  case unsupported(String)
  /// The sorted, unique, one-based pages requiring OCR and total PDF page count.
  case needsOCR(pages: [Int], pageCount: Int)
  /// A hosted OCR failure with no provider response or credentials attached.
  case hostedOCR(HostedOCRFailure)
  /// The document contains malformed data.
  case malformed(String)
  /// The document is encrypted.
  case encrypted(String)
  /// Parsing exceeded an engine resource limit.
  case resourceLimit(String)
  /// The document is missing a required part.
  case missingPart(String)
  /// The engine encountered an I/O failure.
  case io(String)
  /// An engine error code not recognized by this Swift wrapper.
  case unrecognizedUpstream(code: String, message: String)
  /// A native bridge failure, including incompatible ABI or malformed results.
  case bridgeFailure(String)

  /// Hosted failure categories that exclude provider bodies and credentials.
  public enum HostedOCRFailure: Sendable, Equatable {
    /// The endpoint or authorization header configuration is invalid.
    case invalidConfiguration
    /// The provider rejected authentication with HTTP 401.
    case authentication
    /// The provider reported insufficient credits with HTTP 402.
    case insufficientCredits
    /// HTTP 429, with a flag indicating whether the request used keyless access.
    case rateLimited(keyless: Bool)
    /// A provider failure with an HTTP status in the 500–599 range.
    case server(statusCode: Int)
    /// Another unsuccessful HTTP status.
    case http(statusCode: Int)
    /// A network or redirect failure, or expiry of the overall deadline.
    case transport
    /// A successful HTTP response with invalid or unsuccessful Markdown data.
    case malformedResponse

    fileprivate var description: String {
      switch self {
      case .invalidConfiguration:
        "Hosted OCR configuration is invalid."
      case .authentication:
        "Hosted OCR rejected the API key."
      case .insufficientCredits:
        "Hosted OCR has insufficient credits."
      case .rateLimited(keyless: true):
        "Hosted OCR's keyless limit was reached. Supply an API key or set FIRECRAWL_API_KEY."
      case .rateLimited(keyless: false):
        "Hosted OCR's rate limit was reached."
      case .server(let statusCode):
        "Hosted OCR encountered a server failure (HTTP \(statusCode))."
      case .http(let statusCode):
        "Hosted OCR failed (HTTP \(statusCode))."
      case .transport:
        "Hosted OCR encountered a network failure or exceeded its deadline."
      case .malformedResponse:
        "Hosted OCR returned an unsuccessful or malformed response."
      }
    }
  }

  /// A display description; hosted failures use fixed text and status codes.
  public var errorDescription: String? {
    switch self {
    case .inputTooLarge(let actualBytes, let maximumBytes):
      "Input is \(actualBytes) bytes, exceeding the \(maximumBytes)-byte limit."
    case .outputTooLarge(let maximumBytes):
      "Converted Markdown exceeds the \(maximumBytes)-byte output limit."
    case .documentTooLarge(let maximumBytes):
      "Structured document exceeds the \(maximumBytes)-byte wire-result limit."
    case .invalidInput(let message):
      "Invalid document input: \(message)"
    case .unsupported(let message):
      "Unsupported document: \(message)"
    case .needsOCR(let pages, let pageCount):
      if pageCount > 0, pages.count == pageCount {
        "All \(pageCount) document pages require optical character recognition."
      } else if pages.count == 1, let page = pages.first {
        "Document page \(page) of \(pageCount) requires optical character recognition."
      } else {
        "Document pages \(pages.map(String.init).joined(separator: ", ")) of \(pageCount) require optical character recognition."
      }
    case .hostedOCR(let failure):
      failure.description
    case .malformed(let message):
      "Malformed document: \(message)"
    case .encrypted(let message):
      "Encrypted document: \(message)"
    case .resourceLimit(let message):
      "Document conversion exceeded an engine resource limit: \(message)"
    case .missingPart(let message):
      "Document is missing a required part: \(message)"
    case .io(let message):
      "Document conversion encountered an I/O failure: \(message)"
    case .unrecognizedUpstream(let code, let message):
      "Document conversion failed with unrecognized engine code '\(code)': \(message)"
    case .bridgeFailure(let message):
      "The native document-conversion bridge failed: \(message)"
    }
  }
}
