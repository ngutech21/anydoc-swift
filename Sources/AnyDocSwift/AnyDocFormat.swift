/// A canonical parser understood by the embedded AnyDoc engine.
///
/// These cases identify parsers, not every filename extension alias. Use
/// `init(fileExtension:)` to look up an extension. When no format is supplied
/// to a converter, AnyDoc detects the parser from the document bytes.
public enum AnyDocFormat: String, Sendable, Equatable {
  case doc
  case docx
  case odt
  case pdf
  case ppt
  case pptx
  case rtf
  case epub
  /// The Excel parser family, including XLSX, XLSM, XLSB, and legacy XLS.
  case xlsx
  case ods
  case odp
  case csv

  /// Looks up the parser named by a bare filename extension.
  ///
  /// Matching is ASCII case-insensitive. Canonical names are accepted along
  /// with `docm` for `.docx`; `pps` and `pot` for `.ppt`; `pptm`, `ppsx`, and
  /// `ppsm` for `.pptx`; and `xls`, `xlsm`, and `xlsb` for `.xlsx`.
  ///
  /// Returns `nil` for unrecognized or non-ASCII input, including `potx` and
  /// `potm`. Leading dots and whitespace are not removed, and full filenames
  /// are not parsed. This lookup does not read files or inspect document bytes.
  /// Passing its result to a converter selects the named parser authoritatively
  /// when non-`nil`, or delegates detection to AnyDoc when `nil`.
  ///
  /// - Parameter fileExtension: An extension without a leading dot, such as
  ///   `"xlsm"` or a URL's `pathExtension`.
  public init?(fileExtension: String) {
    guard fileExtension.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }

    // Mirrors AnyDoc 0.2.4's Format::from_extension in src/lib.rs at revision
    // 42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c. Recheck when upgrading AnyDoc.
    switch fileExtension.lowercased() {
    case "doc": self = .doc
    case "docx", "docm": self = .docx
    case "odt": self = .odt
    case "pdf": self = .pdf
    case "ppt", "pps", "pot": self = .ppt
    case "pptx", "pptm", "ppsx", "ppsm": self = .pptx
    case "rtf": self = .rtf
    case "epub": self = .epub
    case "xlsx", "xlsm", "xlsb", "xls": self = .xlsx
    case "ods": self = .ods
    case "odp": self = .odp
    case "csv": self = .csv
    default: return nil
    }
  }
}
