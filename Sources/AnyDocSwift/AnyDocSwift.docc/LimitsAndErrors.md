# Limits, cancellation, and errors

Bound document sizes and handle conversion failures through typed errors.

## Overview

``AnyDocConverter/Limits/standard`` permits 64 MiB of input, 16 MiB of UTF-8
Markdown, and 128 MiB for a structured result. The structured limit counts the
encoded manifest plus all retained asset buffers.

These are input and result limits, not a peak-memory budget. Parsing can use
more memory while building a result. Check file size before loading large or
untrusted documents into `Data`.

```swift
import AnyDocSwift
import Foundation

let converter = AnyDocConverter(
  limits: .init(
    maximumInputBytes: 20 * 1024 * 1024,
    maximumOutputBytes: 5 * 1024 * 1024,
    maximumDocumentBytes: 64 * 1024 * 1024
  )
)
let markdown = try await converter.markdown(
  from: Data("name,value\nexample,42\n".utf8), format: .csv
)
print(markdown)
```

### Handle typed errors

Conversion failures use ``AnyDocConversionError``. Switch on cases rather than
parsing their display descriptions:

```swift
import AnyDocSwift
import Foundation

func convertPDF(_ data: Data) async throws -> String? {
  do {
    return try await AnyDocConverter().markdown(from: data, format: .pdf)
  } catch AnyDocConversionError.needsOCR(let pages, let pageCount) {
    print("OCR is required on pages \(pages) of \(pageCount)")
    return nil
  } catch is CancellationError {
    throw CancellationError()
  } catch let error as AnyDocConversionError {
    print(error.localizedDescription)
    throw error
  }
}
```

Other cases distinguish oversized input/results, unsupported, invalid,
malformed, encrypted, missing-part, resource-limit, and I/O failures.
``AnyDocConversionError/unrecognizedUpstream(code:message:)`` preserves unknown
engine codes. ``AnyDocConversionError/bridgeFailure(_:)`` reports a native
bridge failure, including malformed transport.

Hosted failures use ``AnyDocConversionError/HostedOCRFailure`` with fixed
descriptions and status codes. They do not contain provider response bodies,
credentials, destination URLs, or underlying transport descriptions. See
<doc:HostedOCR> for fallback behavior.

### Understand scheduling and cancellation

Markdown and structured conversions share one FIFO queue per converter.
The slot covers the complete operation, including hosted requests and cleanup.
Separate instances may convert concurrently. Native parsing runs off the
caller's executor, and hosted HTTP suspends asynchronously.

Cancellation before native work starts skips the call. An active native parser
cannot be interrupted: conversion and cleanup finish before the awaiting task
receives `CancellationError`. Cancellation prevents an unstarted hosted request
and cancels an active HTTP task. Cancellation observed before returning takes
precedence over success or another failure.
