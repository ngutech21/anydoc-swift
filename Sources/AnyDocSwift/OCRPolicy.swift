/// Controls whether a PDF requiring OCR may leave the device.
public enum OCRPolicy: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Preserve the local engine's structured OCR-required error without uploading.
  case reject
  /// Upload the complete PDF after local conversion reports that OCR is required.
  ///
  /// Missing values fall back to `FIRECRAWL_API_KEY` and `FIRECRAWL_API_URL`, then
  /// keyless access and `https://api.firecrawl.dev`. An explicit empty key selects
  /// keyless access even when the environment contains a key.
  case hosted(apiKey: String? = nil, apiURL: String? = nil)

  public var description: String {
    switch self {
    case .reject: "reject"
    case .hosted: "hosted(apiKey: <redacted>, apiURL: <redacted>)"
    }
  }

  public var debugDescription: String { description }
}
