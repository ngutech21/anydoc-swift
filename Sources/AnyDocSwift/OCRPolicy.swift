/// Controls whether a PDF requiring OCR may leave the device.
public enum OCRPolicy: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Preserve the local engine's structured OCR-required error without uploading.
  case reject
  /// Upload the complete PDF after local conversion reports that OCR is required.
  ///
  /// Missing values fall back to `FIRECRAWL_API_KEY` and `FIRECRAWL_API_URL`, then
  /// keyless access and `https://api.firecrawl.dev`. An explicit empty key selects
  /// keyless access even when the environment contains a key.
  ///
  /// Obtain application consent for the full upload, including the recipient.
  /// Environment variables alone never enable hosted mode.
  ///
  /// - Parameters:
  ///   - apiKey: An explicit key, an empty string for keyless access, or `nil`
  ///     to consult the environment.
  ///   - apiURL: The service base URL before `/v2/parse`, or `nil` to consult
  ///     the environment and then the default. An empty string is invalid.
  case hosted(apiKey: String? = nil, apiURL: String? = nil)

  /// A policy description with the key and URL redacted.
  public var description: String {
    switch self {
    case .reject: "reject"
    case .hosted: "hosted(apiKey: <redacted>, apiURL: <redacted>)"
    }
  }

  /// A debug description with the same redaction as ``description``.
  public var debugDescription: String { description }
}
