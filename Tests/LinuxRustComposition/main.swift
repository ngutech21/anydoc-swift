import AnyDocSwift
import Foundation
import RustUnwindCompanion

@main
enum CompositionConsumer {
  static func main() async throws {
    guard anydoc_unwind_companion_value(42) == 42 else {
      fatalError("the independent unwind-enabled Rust library did not run")
    }
    guard CommandLine.arguments.count == 2 else {
      fatalError("expected one RTF fixture path")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let markdown = try await AnyDocConverter().markdown(from: data, fileExtension: "rtf")
    guard markdown.contains("fn main()") else {
      fatalError("the AnyDoc bridge did not convert the real RTF fixture")
    }
  }
}
