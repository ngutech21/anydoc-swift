import Foundation
import XCTest

@testable import AnyDocSwift

final class FakeNativeBridge: @unchecked Sendable {
  struct Invocation: Sendable, Equatable {
    let data: Data
    let fileExtension: String?
    let maximumInputBytes: UInt64
    let maximumOutputBytes: UInt64
  }

  struct Response: Sendable {
    let status: Int32
    let markdown: [UInt8]?
    let errorCode: [UInt8]?
    let errorMessage: [UInt8]?

    static func success(_ markdown: String) -> Response {
      Response(
        status: 1,
        markdown: Array(markdown.utf8),
        errorCode: nil,
        errorMessage: nil
      )
    }

    static func failure(code: String, message: String = "synthetic failure") -> Response {
      Response(
        status: 0,
        markdown: nil,
        errorCode: Array(code.utf8),
        errorMessage: Array(message.utf8)
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

  private final class ResultHandle: @unchecked Sendable {
    let status: Int32
    let markdown: StableBytes
    let errorCode: StableBytes
    let errorMessage: StableBytes

    init(response: Response) {
      status = response.status
      markdown = StableBytes(response.markdown)
      errorCode = StableBytes(response.errorCode)
      errorMessage = StableBytes(response.errorMessage)
    }
  }

  private let lock = NSLock()
  private let responseProvider: ResponseProvider
  private let version: StableBytes
  private var storedInvocations: [Invocation] = []
  private var storedFreeCount = 0
  private var storedCopyCount = 0

  let abiVersion: UInt32

  init(
    abiVersion: UInt32 = AnyDocCAdapter.expectedABIVersion,
    versionBytes: [UInt8]? = Array(
      "AnyDoc 0.2.3 (bf3d33e61731580d1ee1c6a85e56093d715a21a6); AnyDocSwift bridge ABI 1".utf8
    ),
    responseProvider: @escaping ResponseProvider = { _ in .success("Markdown") }
  ) {
    self.abiVersion = abiVersion
    self.version = StableBytes(versionBytes)
    self.responseProvider = responseProvider
  }

  var invocations: [Invocation] {
    lock.lock()
    defer { lock.unlock() }
    return storedInvocations
  }

  var freeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedFreeCount
  }

  var copyCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedCopyCount
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
          return version.pointer.map { UnsafePointer<UInt8>($0) }
        },
        convert: { [self] in
          makeResult(
            bytes: $0,
            bytesLength: $1,
            extensionBytes: $2,
            extensionLength: $3,
            maximumInputBytes: $4,
            maximumOutputBytes: $5
          )
        },
        isSuccess: { handle in
          Self.result(for: handle)?.status ?? 0
        },
        markdown: { handle, outLength in
          Self.buffer(
            Self.result(for: handle)?.markdown,
            outLength: outLength
          )
        },
        errorCode: { handle, outLength in
          Self.buffer(
            Self.result(for: handle)?.errorCode,
            outLength: outLength
          )
        },
        errorMessage: { handle, outLength in
          Self.buffer(
            Self.result(for: handle)?.errorMessage,
            outLength: outLength
          )
        },
        freeResult: { [self] handle in
          guard let handle else {
            return
          }
          lock.lock()
          storedFreeCount += 1
          lock.unlock()
          Unmanaged<ResultHandle>.fromOpaque(UnsafeRawPointer(handle)).release()
        },
        copyBytes: { [self] pointer, length in
          lock.lock()
          storedCopyCount += 1
          lock.unlock()
          return Data(bytes: pointer, count: length)
        }
      )
    )
  }

  private func makeResult(
    bytes: UnsafePointer<UInt8>?,
    bytesLength: Int,
    extensionBytes: UnsafePointer<UInt8>?,
    extensionLength: Int,
    maximumInputBytes: UInt64,
    maximumOutputBytes: UInt64
  ) -> OpaquePointer? {
    let data = Self.data(pointer: bytes, length: bytesLength)
    let extensionData = Self.data(pointer: extensionBytes, length: extensionLength)
    let invocation = Invocation(
      data: data,
      fileExtension: extensionData.isEmpty
        ? nil : String(data: extensionData, encoding: .utf8),
      maximumInputBytes: maximumInputBytes,
      maximumOutputBytes: maximumOutputBytes
    )

    lock.lock()
    storedInvocations.append(invocation)
    lock.unlock()

    guard let response = responseProvider(invocation) else {
      return nil
    }
    let result = ResultHandle(response: response)
    return OpaquePointer(Unmanaged.passRetained(result).toOpaque())
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
    outLength: UnsafeMutablePointer<Int>?
  ) -> UnsafePointer<UInt8>? {
    guard let outLength, let buffer else {
      return nil
    }
    outLength.pointee = buffer.count
    return buffer.pointer.map { UnsafePointer<UInt8>($0) }
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
      lock.lock()
      operations.append(operation)
      lock.unlock()
      enqueued.fulfill()
    }
  }

  func runNext() {
    lock.lock()
    let operation = operations.removeFirst()
    lock.unlock()
    operation()
  }
}

final class AsyncStartGate: @unchecked Sendable {
  let waiting = XCTestExpectation(description: "task waiting at start gate")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()
      waiting.fulfill()
    }
  }

  func release() {
    lock.lock()
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume()
  }
}

final class ActivityProbe: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var order: [String] = []
  private(set) var maximumActiveCount = 0
  private var activeCount = 0

  func enter(_ value: String) {
    lock.lock()
    order.append(value)
    activeCount += 1
    maximumActiveCount = max(maximumActiveCount, activeCount)
    lock.unlock()
  }

  func leave() {
    lock.lock()
    activeCount -= 1
    lock.unlock()
  }

  func snapshot() -> (order: [String], maximumActiveCount: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (order, maximumActiveCount)
  }
}

let immediateEnqueue: AnyDocConverter.Enqueue = { operation in
  operation()
}

func fixtureData(_ relativePath: String) throws -> Data {
  guard let resourceURL = Bundle.module.resourceURL else {
    throw CocoaError(.fileNoSuchFile)
  }
  return try Data(
    contentsOf:
      resourceURL
      .appendingPathComponent("Fixtures", isDirectory: true)
      .appendingPathComponent(relativePath)
  )
}
