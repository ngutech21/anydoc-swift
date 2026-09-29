import AnyDocSwift

@main
struct PublicConsumerSmoke {
  static func main() {
    _ = AnyDocConverter.engineVersion
    _ = AnyDocConverter()
  }
}
