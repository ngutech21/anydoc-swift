import Foundation

/// A typed failure produced while converting document bytes to Markdown.
public enum AnyDocConversionError: Error, Sendable, Equatable, LocalizedError {
  case inputTooLarge(actualBytes: UInt64, maximumBytes: UInt64)
  case outputTooLarge(maximumBytes: UInt64)
  case invalidInput(String)
  case unsupported(String)
  /// The sorted, unique, one-based pages requiring OCR and total PDF page count.
  case needsOCR(pages: [Int], pageCount: Int)
  case malformed(String)
  case encrypted(String)
  case resourceLimit(String)
  case missingPart(String)
  case io(String)
  case unrecognizedUpstream(code: String, message: String)
  case bridgeFailure(String)

  public var errorDescription: String? {
    switch self {
    case .inputTooLarge(let actualBytes, let maximumBytes):
      "Input is \(actualBytes) bytes, exceeding the \(maximumBytes)-byte limit."
    case .outputTooLarge(let maximumBytes):
      "Converted Markdown exceeds the \(maximumBytes)-byte output limit."
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
