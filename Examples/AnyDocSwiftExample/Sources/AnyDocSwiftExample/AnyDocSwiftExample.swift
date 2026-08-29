import AnyDocSwift
import Foundation

@main
struct AnyDocSwiftExample {
  static func main() async throws {
    guard let path = CommandLine.arguments.dropFirst().first else {
      print("Usage: swift run AnyDocSwiftExample <document>")
      return
    }

    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)

    let converter = AnyDocConverter()
    let markdown = try await converter.markdown(
      from: data,
      fileExtension: url.pathExtension
    )
    print(markdown)
  }
}
