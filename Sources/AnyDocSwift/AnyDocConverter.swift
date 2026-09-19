import Dispatch
public import Foundation

/// Converts supported document bytes to Markdown or a structured document.
///
/// Each converter performs complete operations, including hosted OCR, in FIFO order.
/// Separate converter instances may convert concurrently. Cancellation before
/// native work starts skips the native call. Once native work starts it cannot
/// be interrupted; the native result is released before cancellation is
/// reported.
public actor AnyDocConverter {
  public struct Limits: Sendable, Equatable {
    public static let standard = Limits(
      maximumInputBytes: 64 * 1024 * 1024,
      maximumOutputBytes: 16 * 1024 * 1024,
      maximumDocumentBytes: 128 * 1024 * 1024
    )

    public let maximumInputBytes: UInt64
    public let maximumOutputBytes: UInt64
    public let maximumDocumentBytes: UInt64

    public init(
      maximumInputBytes: UInt64,
      maximumOutputBytes: UInt64,
      maximumDocumentBytes: UInt64 = 128 * 1024 * 1024
    ) {
      self.maximumInputBytes = maximumInputBytes
      self.maximumOutputBytes = maximumOutputBytes
      self.maximumDocumentBytes = maximumDocumentBytes
    }
  }

  typealias Enqueue = @Sendable (@escaping @Sendable () -> Void) -> Void

  static let unavailableEngineVersion = "anydoc engine version unavailable"

  private let limits: Limits
  private let adapter: AnyDocCAdapter
  private let enqueue: Enqueue
  private let hostedOCR: HostedOCRAdapter
  private let onQueued: @Sendable () -> Void
  private var active = false
  private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

  public init(limits: Limits = .standard) {
    let queue = DispatchQueue(
      label: "io.ngutech21.AnyDocSwift.converter.\(UUID().uuidString)"
    )
    self.limits = limits
    self.adapter = .live
    self.hostedOCR = HostedOCRAdapter()
    self.onQueued = {}
    self.enqueue = { operation in
      queue.async(execute: operation)
    }
  }

  init(
    limits: Limits = .standard,
    adapter: AnyDocCAdapter,
    enqueue: @escaping Enqueue,
    hostedOCR: HostedOCRAdapter = HostedOCRAdapter(),
    onQueued: @escaping @Sendable () -> Void = {}
  ) {
    self.limits = limits
    self.adapter = adapter
    self.enqueue = enqueue
    self.hostedOCR = hostedOCR
    self.onQueued = onQueued
  }

  /// The embedded anydoc version, originating revision, and bridge ABI version.
  ///
  /// A malformed or incompatible packaged bridge produces a fixed, non-sensitive
  /// fallback because this property is intentionally nonthrowing.
  public static var engineVersion: String {
    engineVersion(using: .live)
  }

  static func engineVersion(using adapter: AnyDocCAdapter) -> String {
    (try? adapter.engineVersion()) ?? unavailableEngineVersion
  }

  /// Converts document bytes to GitHub-Flavored Markdown.
  ///
  /// A supplied format authoritatively selects its parser. Passing `nil`
  /// delegates format detection to anydoc; signature-less CSV must be named.
  public func markdown(
    from data: Data,
    format: AnyDocFormat? = nil
  ) async throws -> String {
    try await markdown(from: data, format: format, ocr: .reject)
  }

  /// Converts locally first, optionally uploading an OCR-required PDF in full.
  ///
  /// Hosted configuration is resolved only after a structured OCR-required error.
  /// Successful local conversions and other native failures never make a request.
  public func markdown(
    from data: Data,
    format: AnyDocFormat? = nil,
    ocr: OCRPolicy
  ) async throws -> String {
    try await perform(data: data) { converter in
      do {
        return try await converter.performNative { adapter, limits in
          try adapter.markdown(from: data, format: format, limits: limits)
        }
      } catch let error as AnyDocConversionError {
        guard case .needsOCR = error, case .hosted(let apiKey, let apiURL) = ocr else {
          throw error
        }
        try Task.checkCancellation()
        return try await converter.hostedOCR.markdown(
          from: data, apiKey: apiKey, apiURL: apiURL,
          maximumOutputBytes: converter.limits.maximumOutputBytes
        )
      }
    }
  }

  /// Parses document bytes into a self-contained structured document.
  ///
  /// A supplied format authoritatively selects its parser. Passing `nil`
  /// delegates format detection to anydoc. PDF has no document-model form and
  /// is supported only by ``markdown(from:format:)``.
  public func document(
    from data: Data,
    format: AnyDocFormat? = nil
  ) async throws -> AnyDocDocument {
    try await perform(data: data) { converter in
      try await converter.performNative { adapter, limits in
        try adapter.document(from: data, format: format, limits: limits)
      }
    }
  }

  private func perform<Output: Sendable>(
    data: Data,
    operation: @Sendable (isolated AnyDocConverter) async throws -> Output
  ) async throws -> Output {
    try Task.checkCancellation()

    let actualInputBytes = UInt64(data.count)
    guard actualInputBytes <= limits.maximumInputBytes else {
      throw AnyDocConversionError.inputTooLarge(
        actualBytes: actualInputBytes,
        maximumBytes: limits.maximumInputBytes
      )
    }
    try Task.checkCancellation()

    try await acquireTurn()
    defer { releaseTurn() }
    do {
      try Task.checkCancellation()
      let output = try await operation(self)
      try Task.checkCancellation()
      return output
    } catch {
      try Task.checkCancellation()
      throw error
    }
  }

  private func acquireTurn() async throws {
    if !active {
      active = true
      onQueued()
      return
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiting.append((id, continuation))
        onQueued()
      }
    } onCancel: {
      Task { await self.cancelWaiting(id) }
    }
  }

  private func cancelWaiting(_ id: UUID) {
    guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
    waiting.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func releaseTurn() {
    if waiting.isEmpty {
      active = false
    } else {
      // Transfer the slot before resuming: actor reentrancy must not admit a
      // newer request while the selected waiter is waiting for its executor.
      waiting.removeFirst().continuation.resume()
    }
  }

  private func performNative<Output: Sendable>(
    operation: @escaping @Sendable (AnyDocCAdapter, Limits) throws -> Output
  ) async throws -> Output {

    let cancellation = CancellationState()
    let adapter = self.adapter
    let enqueue = self.enqueue
    let limits = self.limits

    let output = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Output, any Error>) in
        enqueue {
          guard cancellation.begin() else {
            continuation.resume(throwing: CancellationError())
            return
          }

          let result = Result { try operation(adapter, limits) }
          if cancellation.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else {
            continuation.resume(with: result)
          }
        }
      }
    } onCancel: {
      cancellation.cancel()
    }

    try Task.checkCancellation()
    return output
  }
}

private final class CancellationState: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.withLock {
      cancelled = true
    }
  }

  func begin() -> Bool {
    lock.withLock { !cancelled }
  }

  var isCancelled: Bool {
    lock.withLock { cancelled }
  }
}
