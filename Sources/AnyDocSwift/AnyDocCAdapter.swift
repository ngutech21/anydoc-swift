internal import AnyDocSwiftBridge
import Foundation

/// The non-public Swift-to-C adapter.
///
/// All unsafe buffer borrowing is concentrated in `Functions.live` and
/// `copyBuffer`. Input buffers remain alive for the synchronous native call.
/// Result buffers are copied while their opaque owner is live, and that owner
/// is released exactly once by the Rust-provided free function.
struct AnyDocCAdapter: @unchecked Sendable {
  static let expectedABIVersion: UInt32 = 1
  static let live = AnyDocCAdapter(functions: .live)

  struct Functions: @unchecked Sendable {
    typealias EngineVersion =
      @Sendable (
        UnsafeMutablePointer<Int>?
      ) -> UnsafePointer<UInt8>?
    typealias Convert =
      @Sendable (
        UnsafePointer<UInt8>?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        UInt64,
        UInt64
      ) -> OpaquePointer?
    typealias ResultStatus = @Sendable (OpaquePointer?) -> Int32
    typealias ResultAccessor =
      @Sendable (
        OpaquePointer?,
        UnsafeMutablePointer<Int>?
      ) -> UnsafePointer<UInt8>?
    typealias ResultFree = @Sendable (OpaquePointer?) -> Void
    typealias CopyBytes = @Sendable (UnsafePointer<UInt8>, Int) -> Data

    let abiVersion: @Sendable () -> UInt32
    let engineVersion: EngineVersion
    let convert: Convert
    let isSuccess: ResultStatus
    let markdown: ResultAccessor
    let errorCode: ResultAccessor
    let errorMessage: ResultAccessor
    let freeResult: ResultFree
    // Test injection proves size validation happens before any unsafe read.
    let copyBytes: CopyBytes

    static let live = Functions(
      abiVersion: { anydoc_swift_abi_version() },
      engineVersion: { anydoc_swift_engine_version($0) },
      convert: {
        anydoc_swift_convert_markdown($0, $1, $2, $3, $4, $5)
      },
      isSuccess: { anydoc_swift_result_is_success($0) },
      markdown: { anydoc_swift_result_markdown($0, $1) },
      errorCode: { anydoc_swift_result_error_code($0, $1) },
      errorMessage: { anydoc_swift_result_error_message($0, $1) },
      freeResult: { anydoc_swift_result_free($0) },
      copyBytes: { Data(bytes: $0, count: $1) }
    )
  }

  private struct NativeBuffer {
    let bytes: Data
    let isAbsent: Bool
  }

  private let functions: Functions

  init(functions: Functions) {
    self.functions = functions
  }

  func engineVersion() throws -> String {
    try validateABI()

    var length = 0
    let pointer = functions.engineVersion(&length)
    let buffer = try copyBuffer(pointer: pointer, length: length, name: "engine version")
    guard !buffer.isAbsent, !buffer.bytes.isEmpty else {
      throw bridgeFailure("Native bridge returned no engine version.")
    }
    guard let version = String(data: buffer.bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an engine version that is not valid UTF-8.")
    }
    return version
  }

  func markdown(
    from data: Data,
    fileExtension: String?,
    limits: AnyDocConverter.Limits
  ) throws -> String {
    try validateABI()

    let extensionData = fileExtension.map { Data($0.utf8) } ?? Data()
    let result = data.withUnsafeBytes { inputBuffer in
      extensionData.withUnsafeBytes { extensionBuffer in
        // SAFETY: Both `Data` values remain alive for this complete,
        // synchronous C call. Rust validates each pointer/length pair before
        // borrowing it and owns every byte reachable from the returned handle.
        functions.convert(
          inputBuffer.bindMemory(to: UInt8.self).baseAddress,
          inputBuffer.count,
          fileExtension == nil
            ? nil : extensionBuffer.bindMemory(to: UInt8.self).baseAddress,
          extensionBuffer.count,
          limits.maximumInputBytes,
          limits.maximumOutputBytes
        )
      }
    }

    guard let result else {
      throw bridgeFailure("Native bridge returned no result handle.")
    }
    defer {
      // SAFETY: This adapter exclusively owns the live handle returned above
      // and invokes the Rust free function exactly once on every exit path.
      functions.freeResult(result)
    }

    switch functions.isSuccess(result) {
    case 1:
      return try decodeSuccess(result, maximumOutputBytes: limits.maximumOutputBytes)
    case 0:
      throw try decodeFailure(result, dataCount: data.count, limits: limits)
    default:
      throw bridgeFailure("Native bridge returned an invalid result status.")
    }
  }

  private func validateABI() throws {
    let actualVersion = functions.abiVersion()
    guard actualVersion == Self.expectedABIVersion else {
      throw bridgeFailure(
        "Native bridge ABI version \(actualVersion) does not match expected version \(Self.expectedABIVersion)."
      )
    }
  }

  private func decodeSuccess(
    _ result: OpaquePointer,
    maximumOutputBytes: UInt64
  ) throws -> String {
    let markdown = try copyBuffer(
      using: functions.markdown,
      result: result,
      name: "Markdown",
      maximumBytes: maximumOutputBytes
    )
    let errorCode = try copyBuffer(
      using: functions.errorCode,
      result: result,
      name: "error code"
    )
    let errorMessage = try copyBuffer(
      using: functions.errorMessage,
      result: result,
      name: "error message"
    )

    guard errorCode.isAbsent, errorMessage.isAbsent else {
      throw bridgeFailure("Native success result also contained an error.")
    }

    let outputBytes = UInt64(markdown.bytes.count)
    guard outputBytes <= maximumOutputBytes else {
      throw AnyDocConversionError.outputTooLarge(maximumBytes: maximumOutputBytes)
    }
    guard let string = String(data: markdown.bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned Markdown that is not valid UTF-8.")
    }
    return string
  }

  private func decodeFailure(
    _ result: OpaquePointer,
    dataCount: Int,
    limits: AnyDocConverter.Limits
  ) throws -> AnyDocConversionError {
    let markdown = try copyBuffer(
      using: functions.markdown,
      result: result,
      name: "Markdown"
    )
    let errorCode = try copyBuffer(
      using: functions.errorCode,
      result: result,
      name: "error code"
    )
    let errorMessage = try copyBuffer(
      using: functions.errorMessage,
      result: result,
      name: "error message"
    )

    guard markdown.isAbsent else {
      throw bridgeFailure("Native failure result also contained Markdown.")
    }
    guard !errorCode.isAbsent, !errorCode.bytes.isEmpty else {
      throw bridgeFailure("Native failure result contained no error code.")
    }
    guard !errorMessage.isAbsent, !errorMessage.bytes.isEmpty else {
      throw bridgeFailure("Native failure result contained no error message.")
    }
    guard let code = String(data: errorCode.bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an error code that is not valid UTF-8.")
    }
    guard let message = String(data: errorMessage.bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an error message that is not valid UTF-8.")
    }

    switch code {
    case "wrapper.invalidInput":
      return .invalidInput(message)
    case "wrapper.inputLimit":
      return .inputTooLarge(
        actualBytes: UInt64(dataCount),
        maximumBytes: limits.maximumInputBytes
      )
    case "wrapper.outputLimit":
      return .outputTooLarge(maximumBytes: limits.maximumOutputBytes)
    case "unsupported":
      return .unsupported(message)
    case "needsOcr":
      return .needsOCR(message)
    case "malformed":
      return .malformed(message)
    case "encrypted":
      return .encrypted(message)
    case "resourceLimit":
      return .resourceLimit(message)
    case "missingPart":
      return .missingPart(message)
    case "io":
      return .io(message)
    case "bridge.panic":
      return .bridgeFailure(message)
    default:
      return .unrecognizedUpstream(code: code, message: message)
    }
  }

  private func copyBuffer(
    using accessor: Functions.ResultAccessor,
    result: OpaquePointer,
    name: String,
    maximumBytes: UInt64? = nil
  ) throws -> NativeBuffer {
    var length = 0
    let pointer = accessor(result, &length)
    guard length >= 0 else {
      throw bridgeFailure("Native bridge returned a negative \(name) length.")
    }
    if let maximumBytes, UInt64(length) > maximumBytes {
      throw AnyDocConversionError.outputTooLarge(maximumBytes: maximumBytes)
    }
    return try copyBuffer(pointer: pointer, length: length, name: name)
  }

  private func copyBuffer(
    pointer: UnsafePointer<UInt8>?,
    length: Int,
    name: String
  ) throws -> NativeBuffer {
    guard length >= 0 else {
      throw bridgeFailure("Native bridge returned a negative \(name) length.")
    }
    guard length > 0 else {
      return NativeBuffer(bytes: Data(), isAbsent: pointer == nil)
    }
    guard let pointer else {
      throw bridgeFailure("Native bridge returned no \(name) buffer for a non-zero length.")
    }

    // SAFETY: The C ABI guarantees that a non-null result buffer is readable
    // for its reported length until the owning result is freed. Copying here
    // prevents any borrowed pointer from escaping that lifetime.
    return NativeBuffer(bytes: functions.copyBytes(pointer, length), isAbsent: false)
  }

  private func bridgeFailure(_ message: String) -> AnyDocConversionError {
    .bridgeFailure(message)
  }
}
