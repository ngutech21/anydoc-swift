import Dispatch
import Foundation
import XCTest

@testable import AnyDocSwift

final class FakeNativeBridge: @unchecked Sendable {
  enum Operation: Sendable, Equatable {
    case markdown
    case document
  }

  struct Invocation: Sendable, Equatable {
    let operation: Operation
    let data: Data
    let format: String?
    let maximumInputBytes: UInt64
    let maximumResultBytes: UInt64
  }

  struct AssetResponse: Sendable {
    let status: Int32
    let bytes: [UInt8]?
    let reportedLength: Int?

    static func present(_ bytes: [UInt8], reportedLength: Int? = nil) -> AssetResponse {
      .init(status: 1, bytes: bytes, reportedLength: reportedLength)
    }

    static let missing = AssetResponse(status: 0, bytes: nil, reportedLength: nil)
  }

  struct Response: Sendable {
    let status: Int32
    let markdown: [UInt8]?
    let documentManifest: [UInt8]?
    let documentAssets: [AssetResponse]
    let errorCode: [UInt8]?
    let errorMessage: [UInt8]?
    let ocrPages: [UInt32]?
    let ocrPageCount: UInt32
    let reportedMarkdownLength: Int?
    let reportedManifestLength: Int?
    let reportedOCRPagesLength: Int?

    init(
      status: Int32,
      markdown: [UInt8]?,
      documentManifest: [UInt8]? = nil,
      documentAssets: [AssetResponse] = [],
      errorCode: [UInt8]?,
      errorMessage: [UInt8]?,
      ocrPages: [UInt32]? = nil,
      ocrPageCount: UInt32 = 0,
      reportedMarkdownLength: Int? = nil,
      reportedManifestLength: Int? = nil,
      reportedOCRPagesLength: Int? = nil
    ) {
      self.status = status
      self.markdown = markdown
      self.documentManifest = documentManifest
      self.documentAssets = documentAssets
      self.errorCode = errorCode
      self.errorMessage = errorMessage
      self.ocrPages = ocrPages
      self.ocrPageCount = ocrPageCount
      self.reportedMarkdownLength = reportedMarkdownLength
      self.reportedManifestLength = reportedManifestLength
      self.reportedOCRPagesLength = reportedOCRPagesLength
    }

    static func success(_ markdown: String) -> Response {
      Response(
        status: 1,
        markdown: Array(markdown.utf8),
        errorCode: nil,
        errorMessage: nil
      )
    }

    static func document(manifest: String, assets: [[UInt8]]) -> Response {
      Response(
        status: 2,
        markdown: nil,
        documentManifest: Array(manifest.utf8),
        documentAssets: assets.map { .present($0) },
        errorCode: nil,
        errorMessage: nil
      )
    }

    static func failure(
      code: String,
      message: String = "synthetic failure",
      ocrPages: [UInt32]? = nil,
      ocrPageCount: UInt32 = 0
    ) -> Response {
      Response(
        status: 0,
        markdown: nil,
        errorCode: Array(code.utf8),
        errorMessage: Array(message.utf8),
        ocrPages: ocrPages,
        ocrPageCount: ocrPageCount
      )
    }

    static func needsOCR(
      pages: [UInt32],
      pageCount: UInt32,
      message: String = "document requires OCR"
    ) -> Response {
      failure(
        code: "needsOcr",
        message: message,
        ocrPages: pages,
        ocrPageCount: pageCount
      )
    }
  }

  typealias ResponseProvider = @Sendable (Invocation) -> Response?

  private final class StableBytes: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<UInt8>?
    let count: Int

    init(_ bytes: [UInt8]?) {
      guard let bytes else {
        pointer = nil
        count = 0
        return
      }
      count = bytes.count
      let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
      for (index, byte) in bytes.enumerated() {
        pointer[index] = byte
      }
      self.pointer = pointer
    }

    deinit {
      pointer?.deallocate()
    }
  }

  private final class StablePages: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<UInt32>?
    let count: Int

    init(_ pages: [UInt32]?) {
      guard let pages else {
        pointer = nil
        count = 0
        return
      }
      count = pages.count
      let pointer = UnsafeMutablePointer<UInt32>.allocate(capacity: max(1, pages.count))
      for (index, page) in pages.enumerated() {
        pointer[index] = page
      }
      self.pointer = pointer
    }

    deinit {
      pointer?.deallocate()
    }
  }

  private final class StableAsset: @unchecked Sendable {
    let status: Int32
    let bytes: StableBytes
    let reportedLength: Int?

    init(_ response: AssetResponse) {
      status = response.status
      bytes = StableBytes(response.bytes)
      reportedLength = response.reportedLength
    }
  }

  private final class ResultHandle: @unchecked Sendable {
    let status: Int32
    let markdown: StableBytes
    let documentManifest: StableBytes
    let documentAssets: [StableAsset]
    let errorCode: StableBytes
    let errorMessage: StableBytes
    let ocrPages: StablePages
    let ocrPageCount: UInt32
    let reportedMarkdownLength: Int?
    let reportedManifestLength: Int?
    let reportedOCRPagesLength: Int?

    init(response: Response) {
      status = response.status
      markdown = StableBytes(response.markdown)
      documentManifest = StableBytes(response.documentManifest)
      documentAssets = response.documentAssets.map(StableAsset.init)
      errorCode = StableBytes(response.errorCode)
      errorMessage = StableBytes(response.errorMessage)
      ocrPages = StablePages(response.ocrPages)
      ocrPageCount = response.ocrPageCount
      reportedMarkdownLength = response.reportedMarkdownLength
      reportedManifestLength = response.reportedManifestLength
      reportedOCRPagesLength = response.reportedOCRPagesLength
    }
  }

  private let lock = NSLock()
  private let responseProvider: ResponseProvider
  private let version: StableBytes
  private var storedInvocations: [Invocation] = []
  private var storedFreeCount = 0
  private var storedCopyCount = 0
  private var storedPageCopyCount = 0

  let abiVersion: UInt32

  init(
    abiVersion: UInt32 = AnyDocCAdapter.expectedABIVersion,
    versionBytes: [UInt8]? = Array(
      "AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 3".utf8
    ),
    responseProvider: @escaping ResponseProvider = { _ in .success("Markdown") }
  ) {
    self.abiVersion = abiVersion
    self.version = StableBytes(versionBytes)
    self.responseProvider = responseProvider
  }

  var invocations: [Invocation] {
    lock.withLock { storedInvocations }
  }

  var freeCount: Int {
    lock.withLock { storedFreeCount }
  }

  var copyCount: Int {
    lock.withLock { storedCopyCount }
  }

  var pageCopyCount: Int {
    lock.withLock { storedPageCopyCount }
  }

  func makeAdapter() -> AnyDocCAdapter {
    AnyDocCAdapter(
      functions: AnyDocCAdapter.Functions(
        abiVersion: { [abiVersion] in abiVersion },
        engineVersion: { [self] outLength in
          guard let outLength else {
            return nil
          }
          outLength.pointee = version.count
          return version.pointer.map { UnsafePointer($0) }
        },
        convertMarkdown: { [self] in
          makeResult(
            operation: .markdown,
            bytes: $0,
            bytesLength: $1,
            formatBytes: $2,
            formatLength: $3,
            maximumInputBytes: $4,
            maximumResultBytes: $5
          )
        },
        convertDocument: { [self] in
          makeResult(
            operation: .document,
            bytes: $0,
            bytesLength: $1,
            formatBytes: $2,
            formatLength: $3,
            maximumInputBytes: $4,
            maximumResultBytes: $5
          )
        },
        resultKind: { handle in
          Self.result(for: handle)?.status ?? -1
        },
        markdown: { handle, outLength in
          let result = Self.result(for: handle)
          return Self.buffer(
            result?.markdown,
            reportedLength: result?.reportedMarkdownLength,
            outLength: outLength
          )
        },
        documentManifest: { handle, outLength in
          let result = Self.result(for: handle)
          return Self.buffer(
            result?.documentManifest,
            reportedLength: result?.reportedManifestLength,
            outLength: outLength
          )
        },
        documentAsset: { handle, index, outBytes, outLength in
          Self.asset(
            Self.result(for: handle),
            index: index,
            outBytes: outBytes,
            outLength: outLength
          )
        },
        errorCode: { handle, outLength in
          Self.buffer(Self.result(for: handle)?.errorCode, outLength: outLength)
        },
        errorMessage: { handle, outLength in
          Self.buffer(Self.result(for: handle)?.errorMessage, outLength: outLength)
        },
        needsOCRPages: { handle, outLength, outPageCount in
          Self.ocrMetadata(
            Self.result(for: handle),
            outLength: outLength,
            outPageCount: outPageCount
          )
        },
        freeResult: { [self] handle in
          guard let handle else {
            return
          }
          lock.withLock {
            storedFreeCount += 1
          }
          Unmanaged<ResultHandle>.fromOpaque(UnsafeRawPointer(handle)).release()
        },
        copyBytes: { [self] pointer, length in
          lock.withLock {
            storedCopyCount += 1
          }
          return Data(bytes: pointer, count: length)
        },
        copyPages: { [self] pointer, length in
          lock.withLock {
            storedPageCopyCount += 1
          }
          return Array(UnsafeBufferPointer(start: pointer, count: length))
        }
      )
    )
  }

  private func makeResult(
    operation: Operation,
    bytes: UnsafePointer<UInt8>?,
    bytesLength: Int,
    formatBytes: UnsafePointer<UInt8>?,
    formatLength: Int,
    maximumInputBytes: UInt64,
    maximumResultBytes: UInt64
  ) -> OpaquePointer? {
    let formatData = Self.data(pointer: formatBytes, length: formatLength)
    let invocation = Invocation(
      operation: operation,
      data: Self.data(pointer: bytes, length: bytesLength),
      format: formatData.isEmpty ? nil : String(data: formatData, encoding: .utf8),
      maximumInputBytes: maximumInputBytes,
      maximumResultBytes: maximumResultBytes
    )
    lock.withLock {
      storedInvocations.append(invocation)
    }

    guard let response = responseProvider(invocation) else {
      return nil
    }
    return OpaquePointer(Unmanaged.passRetained(ResultHandle(response: response)).toOpaque())
  }

  private static func data(pointer: UnsafePointer<UInt8>?, length: Int) -> Data {
    guard length > 0, let pointer else {
      return Data()
    }
    return Data(bytes: pointer, count: length)
  }

  private static func result(for handle: OpaquePointer?) -> ResultHandle? {
    guard let handle else {
      return nil
    }
    return Unmanaged<ResultHandle>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue()
  }

  private static func buffer(
    _ buffer: StableBytes?,
    reportedLength: Int? = nil,
    outLength: UnsafeMutablePointer<Int>?
  ) -> UnsafePointer<UInt8>? {
    outLength?.pointee = 0
    guard let outLength, let buffer else {
      return nil
    }
    outLength.pointee = reportedLength ?? buffer.count
    return buffer.pointer.map { UnsafePointer($0) }
  }

  private static func asset(
    _ result: ResultHandle?,
    index: Int,
    outBytes: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
    outLength: UnsafeMutablePointer<Int>?
  ) -> Int32 {
    outBytes?.pointee = nil
    outLength?.pointee = 0
    guard
      let outBytes,
      let outLength,
      let result,
      index >= 0,
      index < result.documentAssets.count
    else {
      return 0
    }
    let asset = result.documentAssets[index]
    guard asset.status == 1 else {
      return asset.status
    }
    outBytes.pointee = asset.bytes.pointer.map { UnsafePointer($0) }
    outLength.pointee = asset.reportedLength ?? asset.bytes.count
    return 1
  }

  private static func ocrMetadata(
    _ result: ResultHandle?,
    outLength: UnsafeMutablePointer<Int>?,
    outPageCount: UnsafeMutablePointer<UInt32>?
  ) -> UnsafePointer<UInt32>? {
    outLength?.pointee = 0
    outPageCount?.pointee = 0
    guard let outLength, let outPageCount, let result else {
      return nil
    }
    outLength.pointee = result.reportedOCRPagesLength ?? result.ocrPages.count
    outPageCount.pointee = result.ocrPageCount
    return result.ocrPages.pointer.map { UnsafePointer($0) }
  }
}

final class BlockingGate: @unchecked Sendable {
  let entered: XCTestExpectation
  private let permit = DispatchSemaphore(value: 0)

  init(description: String, expectedFulfillmentCount: Int = 1) {
    entered = XCTestExpectation(description: description)
    entered.expectedFulfillmentCount = expectedFulfillmentCount
  }

  func block() {
    entered.fulfill()
    permit.wait()
  }

  func release(count: Int = 1) {
    for _ in 0..<count {
      permit.signal()
    }
  }
}

final class ManualScheduler: @unchecked Sendable {
  let enqueued: XCTestExpectation
  private let lock = NSLock()
  private var operations: [@Sendable () -> Void] = []

  init(expectedCount: Int = 1) {
    enqueued = XCTestExpectation(description: "conversion enqueued")
    enqueued.expectedFulfillmentCount = expectedCount
  }

  var enqueue: AnyDocConverter.Enqueue {
    { [self] operation in
      lock.withLock {
        operations.append(operation)
      }
      enqueued.fulfill()
    }
  }

  func runNext() {
    let operation = lock.withLock { operations.removeFirst() }
    operation()
  }
}

final class AsyncStartGate: @unchecked Sendable {
  let waiting = XCTestExpectation(description: "task waiting at start gate")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.withLock {
        self.continuation = continuation
      }
      waiting.fulfill()
    }
  }

  func release() {
    let storedContinuation = lock.withLock {
      let value = self.continuation
      self.continuation = nil
      return value
    }
    storedContinuation?.resume()
  }
}

final class ActivityProbe: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var order: [String] = []
  private(set) var maximumActiveCount = 0
  private var activeCount = 0

  func enter(_ value: String) {
    lock.withLock {
      order.append(value)
      activeCount += 1
      maximumActiveCount = max(maximumActiveCount, activeCount)
    }
  }

  func leave() {
    lock.withLock {
      activeCount -= 1
    }
  }

  func snapshot() -> (order: [String], maximumActiveCount: Int) {
    lock.withLock { (order, maximumActiveCount) }
  }
}

let immediateEnqueue: AnyDocConverter.Enqueue = { operation in
  operation()
}

func fixtureData(_ relativePath: String) throws -> Data {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try Data(contentsOf: testsDirectory.appendingPathComponent("Fixtures/\(relativePath)"))
}

func sha256Hex(_ data: Data) -> String {
  let constants: [UInt32] = [
    0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1,
    0x923F_82A4, 0xAB1C_5ED5, 0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3,
    0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174, 0xE49B_69C1, 0xEFBE_4786,
    0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
    0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147,
    0x06CA_6351, 0x1429_2967, 0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13,
    0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85, 0xA2BF_E8A1, 0xA81A_664B,
    0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
    0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A,
    0x5B9C_CA4F, 0x682E_6FF3, 0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208,
    0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
  ]
  var message = Array(data)
  let bitLength = UInt64(message.count) * 8
  message.append(0x80)
  while message.count % 64 != 56 {
    message.append(0)
  }
  for shift in stride(from: 56, through: 0, by: -8) {
    message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
  }

  var hash: [UInt32] = [
    0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
    0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
  ]
  for chunkStart in stride(from: 0, to: message.count, by: 64) {
    var words = Array(repeating: UInt32(0), count: 64)
    for index in 0..<16 {
      let offset = chunkStart + index * 4
      words[index] =
        UInt32(message[offset]) << 24 | UInt32(message[offset + 1]) << 16
        | UInt32(message[offset + 2]) << 8 | UInt32(message[offset + 3])
    }
    for index in 16..<64 {
      let first =
        rotateRight(words[index - 15], by: 7) ^ rotateRight(words[index - 15], by: 18)
        ^ (words[index - 15] >> 3)
      let second =
        rotateRight(words[index - 2], by: 17) ^ rotateRight(words[index - 2], by: 19)
        ^ (words[index - 2] >> 10)
      words[index] = words[index - 16] &+ first &+ words[index - 7] &+ second
    }

    var a = hash[0]
    var b = hash[1]
    var c = hash[2]
    var d = hash[3]
    var e = hash[4]
    var f = hash[5]
    var g = hash[6]
    var h = hash[7]
    for index in 0..<64 {
      let sumOne = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
      let choice = (e & f) ^ (~e & g)
      let temporaryOne = h &+ sumOne &+ choice &+ constants[index] &+ words[index]
      let sumZero = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temporaryTwo = sumZero &+ majority
      h = g
      g = f
      f = e
      e = d &+ temporaryOne
      d = c
      c = b
      b = a
      a = temporaryOne &+ temporaryTwo
    }
    for (index, value) in [a, b, c, d, e, f, g, h].enumerated() {
      hash[index] = hash[index] &+ value
    }
  }

  return hash.map { String(format: "%08x", $0) }.joined()
}

private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
  (value >> amount) | (value << (32 - amount))
}
