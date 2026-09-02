import AnyDocSwift
import Foundation

@main
enum MemoryProbe {
  private static let assetByteCount = 24 * 1024 * 1024
  private static let manifestBlockCount = 40_000

  static func main() async throws {
    guard CommandLine.arguments.count == 3 else {
      fatalError("expected a fixture path and either asset or manifest")
    }

    let fixture = CommandLine.arguments[1]
    let profile = CommandLine.arguments[2]
    let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
    let document = try await AnyDocConverter().document(from: data, format: .docx)

    switch profile {
    case "asset":
      guard document.assets.count == 1,
        document.assets[0].bytes.count == assetByteCount
      else {
        fatalError("asset-heavy fixture did not retain its declared asset")
      }
    case "manifest":
      guard document.assets.isEmpty, document.blocks.count == manifestBlockCount else {
        fatalError("manifest-heavy fixture did not retain every block")
      }
    default:
      fatalError("unknown memory profile: \(profile)")
    }

    // Keep the complete public graph live until the measurement process exits.
    print("\(profile): \(document.blocks.count) blocks, \(document.assets.count) assets")
  }
}
