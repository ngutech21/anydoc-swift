import Foundation

/// Converts supported document bytes to GitHub-Flavored Markdown.
///
/// Each converter performs native work in FIFO order on its own serial queue.
/// Separate converter instances may convert concurrently. Cancellation before
/// native work starts skips the native call. Once native work starts it cannot
/// be interrupted; the result is released before `CancellationError` is thrown.
public actor AnyDocConverter {
  public struct Limits: Sendable, Equatable {
    public static let standard = Limits(
      maximumInputBytes: 64 * 1024 * 1024,
      maximumOutputBytes: 16 * 1024 * 1024
    )

    public let maximumInputBytes: UInt64
    public let maximumOutputBytes: UInt64

    public init(maximumInputBytes: UInt64, maximumOutputBytes: UInt64) {
      self.maximumInputBytes = maximumInputBytes
      self.maximumOutputBytes = maximumOutputBytes
    }
  }

  typealias Enqueue = @Sendable (@escaping @Sendable () -> Void) -> Void

  static let unavailableEngineVersion = "AnyDoc engine version unavailable"

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

  /// The embedded AnyDoc version, originating revision, and bridge ABI version.
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
  /// - Parameters:
  ///   - data: Complete document bytes. Callers should check file size before
  ///     loading large files into `Data`.
  ///   - fileExtension: An optional extension hint. Content detection remains
  ///     authoritative; CSV requires the `csv` hint.
  /// - Returns: UTF-8 Markdown within the configured output limit.
  /// - Throws: `AnyDocConversionError` for conversion failures, or
  ///   `CancellationError` when the calling task is cancelled.
  public func markdown(from data: Data, fileExtension: String? = nil) async throws -> String {
    try Task.checkCancellation()

    let normalizedExtension = try Self.normalize(fileExtension)
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

    let markdown = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<String, any Error>) in
        enqueue {
          guard cancellation.begin() else {
            continuation.resume(throwing: CancellationError())
            return
          }

          let result: Result<String, Error>
          do {
            result = .success(
              try adapter.markdown(
                from: data,
                fileExtension: normalizedExtension,
                limits: limits
              )
            )
          } catch {
            result = .failure(error)
          }

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
    return markdown
  }

  private static func normalize(_ fileExtension: String?) throws -> String? {
    guard var normalized = fileExtension?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }
    if normalized.first == "." {
      normalized.removeFirst()
    }
    normalized = normalized.lowercased()

    guard !normalized.isEmpty else {
      return nil
    }
    guard normalized.utf8.count <= 64 else {
      throw AnyDocConversionError.invalidInput(
        "File-extension hint exceeds 64 UTF-8 bytes."
      )
    }
    return normalized
  }
}

private final class CancellationState: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  func begin() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return !cancelled
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}
