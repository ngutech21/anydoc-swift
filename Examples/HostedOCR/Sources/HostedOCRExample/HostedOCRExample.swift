import AnyDocSwift
import Foundation

@main
struct HostedOCRExample {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2, arguments[0] == "--allow-upload" else {
      print("Usage: swift run HostedOCRExample --allow-upload <document.pdf>")
      print("Allows uploading the entire PDF if local conversion requires OCR.")
      print("FIRECRAWL_API_URL selects the destination; default: https://api.firecrawl.dev.")
      return
    }
    let pdf = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let markdown = try await AnyDocConverter().markdown(
      from: pdf, format: .pdf, ocr: .hosted()
    )
    print(markdown, terminator: "")
  }
}
