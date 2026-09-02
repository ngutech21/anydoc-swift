internal import AnyDocSwiftBridge
import Foundation

/// The non-public Swift-to-C adapter.
///
/// All unsafe buffer borrowing is concentrated in `Functions.live`,
/// `invoke`, and the immediate copy helpers. Input buffers remain alive for
/// each synchronous native call. Result buffers are copied while their opaque
/// owner is live, and that owner is released exactly once on every exit path.
struct AnyDocCAdapter: @unchecked Sendable {
  static let expectedABIVersion: UInt32 = 3
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
    typealias ResultKind = @Sendable (OpaquePointer?) -> Int32
    typealias ResultAccessor =
      @Sendable (
        OpaquePointer?,
        UnsafeMutablePointer<Int>?
      ) -> UnsafePointer<UInt8>?
    typealias DocumentAssetAccessor =
      @Sendable (
        OpaquePointer?,
        Int,
        UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
      ) -> Int32
    typealias OCRMetadataAccessor =
      @Sendable (
        OpaquePointer?,
        UnsafeMutablePointer<Int>?,
        UnsafeMutablePointer<UInt32>?
      ) -> UnsafePointer<UInt32>?
    typealias ResultFree = @Sendable (OpaquePointer?) -> Void
    typealias CopyBytes = @Sendable (UnsafePointer<UInt8>, Int) -> Data
    typealias CopyPages = @Sendable (UnsafePointer<UInt32>, Int) -> [UInt32]

    let abiVersion: @Sendable () -> UInt32
    let engineVersion: EngineVersion
    let convertMarkdown: Convert
    let convertDocument: Convert
    let resultKind: ResultKind
    let markdown: ResultAccessor
    let documentManifest: ResultAccessor
    let documentAsset: DocumentAssetAccessor
    let errorCode: ResultAccessor
    let errorMessage: ResultAccessor
    let needsOCRPages: OCRMetadataAccessor
    let freeResult: ResultFree
    // Test injection proves size validation happens before any unsafe read.
    let copyBytes: CopyBytes
    let copyPages: CopyPages

    static let live = Functions(
      abiVersion: { anydoc_swift_abi_version() },
      engineVersion: { anydoc_swift_engine_version($0) },
      convertMarkdown: {
        anydoc_swift_convert_markdown($0, $1, $2, $3, $4, $5)
      },
      convertDocument: {
        anydoc_swift_convert_document($0, $1, $2, $3, $4, $5)
      },
      resultKind: { anydoc_swift_result_kind($0) },
      markdown: { anydoc_swift_result_markdown($0, $1) },
      documentManifest: { anydoc_swift_result_document_manifest($0, $1) },
      documentAsset: { anydoc_swift_result_document_asset($0, $1, $2, $3) },
      errorCode: { anydoc_swift_result_error_code($0, $1) },
      errorMessage: { anydoc_swift_result_error_message($0, $1) },
      needsOCRPages: { anydoc_swift_result_needs_ocr_pages($0, $1, $2) },
      freeResult: { anydoc_swift_result_free($0) },
      copyBytes: { Data(bytes: $0, count: $1) },
      copyPages: { Array(UnsafeBufferPointer(start: $0, count: $1)) }
    )
  }

  private struct NativeBuffer {
    let pointer: UnsafePointer<UInt8>?
    let length: Int

    var isAbsent: Bool {
      pointer == nil && length == 0
    }
  }

  private struct NativeOCRMetadata {
    let pages: [Int]
    let pageCount: Int
  }

  private let functions: Functions

  init(functions: Functions) {
    self.functions = functions
  }

  func engineVersion() throws -> String {
    try validateABI()

    var length = 0
    let pointer = functions.engineVersion(&length)
    let buffer = try inspectBuffer(pointer: pointer, length: length, name: "engine version")
    guard !buffer.isAbsent, buffer.length > 0 else {
      throw bridgeFailure("Native bridge returned no engine version.")
    }
    let bytes = try copy(buffer)
    guard let version = String(data: bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an engine version that is not valid UTF-8.")
    }
    return version
  }

  func markdown(
    from data: Data,
    format: AnyDocFormat?,
    limits: AnyDocConverter.Limits
  ) throws -> String {
    try invoke(
      data: data,
      format: format,
      maximumResultBytes: limits.maximumOutputBytes,
      limits: limits,
      convert: functions.convertMarkdown
    ) { result in
      switch functions.resultKind(result) {
      case 1:
        return try decodeMarkdown(result, maximumOutputBytes: limits.maximumOutputBytes)
      case 0:
        throw try decodeFailure(result, dataCount: data.count, limits: limits)
      default:
        throw bridgeFailure("Native bridge returned a non-Markdown result kind.")
      }
    }
  }

  func document(
    from data: Data,
    format: AnyDocFormat?,
    limits: AnyDocConverter.Limits
  ) throws -> AnyDocDocument {
    try invoke(
      data: data,
      format: format,
      maximumResultBytes: limits.maximumDocumentBytes,
      limits: limits,
      convert: functions.convertDocument
    ) { result in
      switch functions.resultKind(result) {
      case 2:
        return try decodeDocument(result, maximumDocumentBytes: limits.maximumDocumentBytes)
      case 0:
        throw try decodeFailure(result, dataCount: data.count, limits: limits)
      default:
        throw bridgeFailure("Native bridge returned a non-document result kind.")
      }
    }
  }

  private func invoke<Output>(
    data: Data,
    format: AnyDocFormat?,
    maximumResultBytes: UInt64,
    limits: AnyDocConverter.Limits,
    convert: Functions.Convert,
    decode: (OpaquePointer) throws -> Output
  ) throws -> Output {
    try validateABI()

    let formatData = format.map { Data($0.rawValue.utf8) } ?? Data()
    let result = data.withUnsafeBytes { inputBuffer in
      formatData.withUnsafeBytes { formatBuffer in
        // SAFETY: Both `Data` values remain alive for this complete,
        // synchronous C call. Rust validates each pointer/length pair before
        // borrowing it and owns every byte reachable from the returned handle.
        convert(
          inputBuffer.bindMemory(to: UInt8.self).baseAddress,
          inputBuffer.count,
          format == nil ? nil : formatBuffer.bindMemory(to: UInt8.self).baseAddress,
          formatBuffer.count,
          limits.maximumInputBytes,
          maximumResultBytes
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
    return try decode(result)
  }

  private func validateABI() throws {
    let actualVersion = functions.abiVersion()
    guard actualVersion == Self.expectedABIVersion else {
      throw bridgeFailure(
        "Native bridge ABI version \(actualVersion) does not match expected version \(Self.expectedABIVersion)."
      )
    }
  }

  private func decodeMarkdown(
    _ result: OpaquePointer,
    maximumOutputBytes: UInt64
  ) throws -> String {
    try requireAbsent(functions.documentManifest, result: result, name: "document manifest")
    try requireNoDocumentAsset(result)
    try requireNoError(result)

    let markdown = try inspect(
      functions.markdown,
      result: result,
      name: "Markdown",
      maximumBytes: maximumOutputBytes,
      limitError: .outputTooLarge(maximumBytes: maximumOutputBytes)
    )
    let bytes = try copy(markdown)
    guard let string = String(data: bytes, encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned Markdown that is not valid UTF-8.")
    }
    return string
  }

  private func decodeDocument(
    _ result: OpaquePointer,
    maximumDocumentBytes: UInt64
  ) throws -> AnyDocDocument {
    try requireAbsent(functions.markdown, result: result, name: "Markdown")
    try requireNoError(result)

    let prepared = try prepareManifest(
      result,
      maximumDocumentBytes: maximumDocumentBytes
    )
    try validateCumulativeLimit(
      prepared,
      maximumDocumentBytes: maximumDocumentBytes
    )

    var assets: [Data] = []
    assets.reserveCapacity(prepared.assetByteLengths.count)
    for (index, declaredLength) in prepared.assetByteLengths.enumerated() {
      assets.append(
        try copyDocumentAsset(
          result,
          index: index,
          declaredLength: declaredLength
        )
      )
    }
    try requireNoDocumentAsset(result, index: prepared.assetByteLengths.count)
    return try prepared.materialize(assetBytes: assets)
  }

  private func prepareManifest(
    _ result: OpaquePointer,
    maximumDocumentBytes: UInt64
  ) throws -> AnyDocDocumentDecoder.Prepared {
    let manifest = try inspect(
      functions.documentManifest,
      result: result,
      name: "document manifest",
      maximumBytes: maximumDocumentBytes,
      limitError: .documentTooLarge(maximumBytes: maximumDocumentBytes)
    )
    guard !manifest.isAbsent, manifest.length > 0 else {
      throw bridgeFailure("Native bridge returned no document manifest.")
    }
    // The copied JSON `Data` dies when this helper returns; only decoded
    // structural values and declared lengths survive while assets are copied.
    return try AnyDocDocumentDecoder.prepare(manifest: copy(manifest))
  }

  private func validateCumulativeLimit(
    _ prepared: AnyDocDocumentDecoder.Prepared,
    maximumDocumentBytes: UInt64
  ) throws {
    var total = prepared.manifestByteCount
    for length in prepared.assetByteLengths {
      let (next, overflow) = total.addingReportingOverflow(length)
      guard !overflow, next <= maximumDocumentBytes else {
        throw AnyDocConversionError.documentTooLarge(maximumBytes: maximumDocumentBytes)
      }
      guard Int(exactly: length) != nil else {
        throw bridgeFailure("Native bridge returned an invalid asset length.")
      }
      total = next
    }
  }

  private func copyDocumentAsset(
    _ result: OpaquePointer,
    index: Int,
    declaredLength: UInt64
  ) throws -> Data {
    var pointer: UnsafePointer<UInt8>?
    var length = 0
    let status = functions.documentAsset(result, index, &pointer, &length)
    guard status == 1 else {
      if status == 0, pointer == nil, length == 0 {
        throw bridgeFailure("Native bridge returned no declared document asset.")
      }
      throw bridgeFailure("Native bridge returned an invalid document-asset status.")
    }
    let buffer = try inspectBuffer(pointer: pointer, length: length, name: "document asset")
    guard UInt64(length) == declaredLength else {
      throw bridgeFailure("Native bridge returned a document asset with the wrong length.")
    }
    return try copy(buffer)
  }

  private func requireNoDocumentAsset(_ result: OpaquePointer, index: Int = 0) throws {
    var pointer: UnsafePointer<UInt8>?
    var length = 0
    let status = functions.documentAsset(result, index, &pointer, &length)
    guard status == 0, pointer == nil, length == 0 else {
      throw bridgeFailure("Native result contained an unexpected document asset.")
    }
  }

  private func requireNoError(_ result: OpaquePointer) throws {
    try requireAbsent(functions.errorCode, result: result, name: "error code")
    try requireAbsent(functions.errorMessage, result: result, name: "error message")
    guard try copyOCRMetadata(result: result) == nil else {
      throw bridgeFailure("Native success result also contained OCR metadata.")
    }
  }

  private func decodeFailure(
    _ result: OpaquePointer,
    dataCount: Int,
    limits: AnyDocConverter.Limits
  ) throws -> AnyDocConversionError {
    try requireAbsent(functions.markdown, result: result, name: "Markdown")
    try requireAbsent(functions.documentManifest, result: result, name: "document manifest")
    try requireNoDocumentAsset(result)

    let errorCode = try inspect(functions.errorCode, result: result, name: "error code")
    let errorMessage = try inspect(functions.errorMessage, result: result, name: "error message")
    let ocrMetadata = try copyOCRMetadata(result: result)

    guard !errorCode.isAbsent, errorCode.length > 0 else {
      throw bridgeFailure("Native failure result contained no error code.")
    }
    guard !errorMessage.isAbsent, errorMessage.length > 0 else {
      throw bridgeFailure("Native failure result contained no error message.")
    }
    guard let code = String(data: try copy(errorCode), encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an error code that is not valid UTF-8.")
    }
    guard let message = String(data: try copy(errorMessage), encoding: .utf8) else {
      throw bridgeFailure("Native bridge returned an error message that is not valid UTF-8.")
    }

    if code == "needsOcr" {
      guard let ocrMetadata else {
        throw bridgeFailure("Native needsOcr failure contained no OCR page metadata.")
      }
      return .needsOCR(pages: ocrMetadata.pages, pageCount: ocrMetadata.pageCount)
    }
    guard ocrMetadata == nil else {
      throw bridgeFailure("Native non-OCR failure also contained OCR page metadata.")
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
    case "wrapper.documentLimit":
      return .documentTooLarge(maximumBytes: limits.maximumDocumentBytes)
    case "unsupported":
      return .unsupported(message)
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
    case "bridge.panic", "bridge.transport":
      return .bridgeFailure(message)
    default:
      return .unrecognizedUpstream(code: code, message: message)
    }
  }

  private func copyOCRMetadata(result: OpaquePointer) throws -> NativeOCRMetadata? {
    var length = 0
    var pageCount: UInt32 = 0
    let pointer = functions.needsOCRPages(result, &length, &pageCount)

    guard length >= 0 else {
      throw bridgeFailure("Native bridge returned a negative OCR page-array length.")
    }
    guard length > 0 else {
      guard pointer == nil, pageCount == 0 else {
        throw bridgeFailure("Native bridge returned inconsistent empty OCR page metadata.")
      }
      return nil
    }
    guard let pointer else {
      throw bridgeFailure("Native bridge returned no OCR page array for a non-zero length.")
    }
    guard pageCount > 0, UInt64(length) <= UInt64(pageCount) else {
      throw bridgeFailure("Native bridge returned an invalid OCR page count.")
    }

    // SAFETY: The C ABI guarantees that a non-null page array is readable for
    // its reported length until the result is freed. Bounds are validated
    // before this immediate copy.
    let rawPages = functions.copyPages(pointer, length)
    let totalPages = Int(pageCount)
    let pages = rawPages.map(Int.init)
    var previousPage = 0
    for page in pages {
      guard page > previousPage, page <= totalPages else {
        throw bridgeFailure(
          "Native bridge returned OCR pages that are not sorted, unique, and within the document page count."
        )
      }
      previousPage = page
    }
    return NativeOCRMetadata(pages: pages, pageCount: totalPages)
  }

  private func requireAbsent(
    _ accessor: Functions.ResultAccessor,
    result: OpaquePointer,
    name: String
  ) throws {
    let buffer = try inspect(accessor, result: result, name: name)
    guard buffer.isAbsent else {
      throw bridgeFailure("Native result contained unexpected \(name).")
    }
  }

  private func inspect(
    _ accessor: Functions.ResultAccessor,
    result: OpaquePointer,
    name: String,
    maximumBytes: UInt64? = nil,
    limitError: AnyDocConversionError? = nil
  ) throws -> NativeBuffer {
    var length = 0
    let pointer = accessor(result, &length)
    let buffer = try inspectBuffer(pointer: pointer, length: length, name: name)
    if let maximumBytes, UInt64(buffer.length) > maximumBytes {
      throw limitError ?? bridgeFailure("Native bridge returned an oversized \(name) buffer.")
    }
    return buffer
  }

  private func inspectBuffer(
    pointer: UnsafePointer<UInt8>?,
    length: Int,
    name: String
  ) throws -> NativeBuffer {
    guard length >= 0 else {
      throw bridgeFailure("Native bridge returned a negative \(name) length.")
    }
    guard length == 0 || pointer != nil else {
      throw bridgeFailure("Native bridge returned no \(name) buffer for a non-zero length.")
    }
    return NativeBuffer(pointer: pointer, length: length)
  }

  private func copy(_ buffer: NativeBuffer) throws -> Data {
    guard buffer.length > 0 else {
      return Data()
    }
    guard let pointer = buffer.pointer else {
      throw bridgeFailure("Native bridge returned an unreadable buffer.")
    }
    // SAFETY: The C ABI guarantees that the buffer is readable for its
    // validated length until the owning result is freed. Copy immediately.
    return functions.copyBytes(pointer, buffer.length)
  }

  private func bridgeFailure(_ message: String) -> AnyDocConversionError {
    .bridgeFailure(message)
  }
}
