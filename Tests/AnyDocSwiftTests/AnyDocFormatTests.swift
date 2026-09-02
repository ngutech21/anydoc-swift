import AnyDocSwift
import XCTest

final class AnyDocFormatTests: XCTestCase, @unchecked Sendable {
  func testExtensionLookupMatchesPinnedUpstream() {
    // anydoc 0.2.4, revision 42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c:
    // Format::from_extension in src/lib.rs.
    let recognized: [(String, AnyDocFormat)] = [
      ("doc", .doc),
      ("docx", .docx),
      ("docm", .docx),
      ("odt", .odt),
      ("pdf", .pdf),
      ("ppt", .ppt),
      ("pps", .ppt),
      ("pot", .ppt),
      ("pptx", .pptx),
      ("pptm", .pptx),
      ("ppsx", .pptx),
      ("ppsm", .pptx),
      ("rtf", .rtf),
      ("epub", .epub),
      ("xlsx", .xlsx),
      ("xlsm", .xlsx),
      ("xlsb", .xlsx),
      ("xls", .xlsx),
      ("ods", .ods),
      ("odp", .odp),
      ("csv", .csv),
    ]
    for (fileExtension, expected) in recognized {
      let mixedCase = fileExtension.prefix(1).uppercased() + fileExtension.dropFirst()
      for spelling in [fileExtension, fileExtension.uppercased(), mixedCase] {
        XCTAssertEqual(AnyDocFormat(fileExtension: spelling), expected, spelling)
      }
    }

    for unrecognized in [
      "", "unknown", "txt", "excel", "potx", "POTM", ".xlsx", "..csv",
      " xlsm", "xlsm ", "\tcsv", "csv\n", "report.xlsx", "/tmp/report.docx",
      "épub", "ｃｓｖ", "xlſ", "docx\u{00A0}", "xlsx\0",
    ] {
      XCTAssertNil(AnyDocFormat(fileExtension: unrecognized), unrecognized)
    }
  }

  func testCanonicalRawValuesRemainUnchanged() {
    let canonical: [(String, AnyDocFormat)] = [
      ("doc", .doc), ("docx", .docx), ("odt", .odt), ("pdf", .pdf),
      ("ppt", .ppt), ("pptx", .pptx), ("rtf", .rtf), ("epub", .epub),
      ("xlsx", .xlsx), ("ods", .ods), ("odp", .odp), ("csv", .csv),
    ]
    for (rawValue, format) in canonical {
      XCTAssertEqual(format.rawValue, rawValue)
      XCTAssertEqual(AnyDocFormat(rawValue: rawValue), format)
      XCTAssertNil(AnyDocFormat(rawValue: rawValue.uppercased()))
    }
    for alias in ["docm", "pps", "pot", "pptm", "ppsx", "ppsm", "xls", "xlsm", "xlsb"] {
      XCTAssertNil(AnyDocFormat(rawValue: alias), alias)
    }
  }

  func testAliasSelectsCanonicalParserForBothConversions() async throws {
    let converter = AnyDocConverter()
    let data = try fixtureData("docx/text.docx")
    let format = try XCTUnwrap(AnyDocFormat(fileExtension: "DoCm"))

    let markdown = try await converter.markdown(from: data, format: format)
    let canonicalMarkdown = try await converter.markdown(from: data, format: .docx)
    XCTAssertFalse(markdown.isEmpty)
    XCTAssertEqual(markdown, canonicalMarkdown)

    let document = try await converter.document(from: data, format: format)
    let canonicalDocument = try await converter.document(from: data, format: .docx)
    XCTAssertFalse(document.blocks.isEmpty)
    XCTAssertEqual(document, canonicalDocument)
  }

  func testCSVLookupSelectsParserAuthoritativelyForBothConversions() async throws {
    let converter = AnyDocConverter()
    let format = try XCTUnwrap(AnyDocFormat(fileExtension: "CsV"))
    let csvData = try fixtureData("csv/handmade-quoted.csv")

    let csvMarkdown = try await converter.markdown(from: csvData, format: format)
    XCTAssertTrue(csvMarkdown.contains("| padded | comma, inside | 3 |"))
    let csvDocument = try await converter.document(from: csvData, format: format)
    guard case .table = csvDocument.blocks.first else {
      return XCTFail("Expected a CSV table")
    }

    // A supplied format wins even when the bytes carry another signature.
    let rtfData = try fixtureData("rtf/handmade-blockstyle.rtf")
    let selectedMarkdown = try await converter.markdown(from: rtfData, format: format)
    let canonicalMarkdown = try await converter.markdown(from: rtfData, format: .csv)
    let automaticMarkdown = try await converter.markdown(from: rtfData)
    XCTAssertEqual(selectedMarkdown, canonicalMarkdown)
    XCTAssertNotEqual(selectedMarkdown, automaticMarkdown)

    let selectedDocument = try await converter.document(from: rtfData, format: format)
    let canonicalDocument = try await converter.document(from: rtfData, format: .csv)
    let automaticDocument = try await converter.document(from: rtfData)
    XCTAssertEqual(selectedDocument, canonicalDocument)
    XCTAssertNotEqual(selectedDocument, automaticDocument)
  }

  func testUnknownExtensionDelegatesToDetectionForBothConversions() async throws {
    let converter = AnyDocConverter()
    let data = try fixtureData("rtf/handmade-blockstyle.rtf")
    let format = AnyDocFormat(fileExtension: "unknown")
    XCTAssertNil(format)

    let markdown = try await converter.markdown(from: data, format: format)
    let automaticMarkdown = try await converter.markdown(from: data)
    XCTAssertTrue(markdown.contains("fn main()"))
    XCTAssertEqual(markdown, automaticMarkdown)

    let document = try await converter.document(from: data, format: format)
    let automaticDocument = try await converter.document(from: data)
    XCTAssertFalse(document.blocks.isEmpty)
    XCTAssertEqual(document, automaticDocument)
  }
}
