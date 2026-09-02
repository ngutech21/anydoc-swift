import Dispatch
import Foundation

/// Converts supported document bytes to Markdown or a structured document.
///
/// Each converter performs native work in FIFO order on its own serial queue.
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

  public init(limits: Limits = .standard) {
    let queue = DispatchQueue(
      label: "io.ngutech21.AnyDocSwift.converter.\(UUID().uuidString)"
    )
    self.limits = limits
    self.adapter = .live
    self.enqueue = { operation in
      queue.async(execute: operation)
    }
  }

  init(limits: Limits = .standard, adapter: AnyDocCAdapter, enqueue: @escaping Enqueue) {
    self.limits = limits
    self.adapter = adapter
    self.enqueue = enqueue
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
    try await perform(data: data) { adapter, limits in
      try adapter.markdown(from: data, format: format, limits: limits)
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
    try await perform(data: data) { adapter, limits in
      try adapter.document(from: data, format: format, limits: limits)
    }
  }

  private func perform<Output: Sendable>(
    data: Data,
    operation: @escaping @Sendable (AnyDocCAdapter, Limits) throws -> Output
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
