# Hosted OCR

Explicitly permit a PDF that requires OCR to be sent to a remote service.

## Overview

``AnyDocConverter/markdown(from:format:)`` remains local-only.
``AnyDocConverter/markdown(from:format:ocr:)`` with
``OCRPolicy/hosted(apiKey:apiURL:)`` enables fallback only after local conversion
throws ``AnyDocConversionError/needsOCR(pages:pageCount:)``. Successful local
conversions and other local errors never trigger an upload. Structured document
conversion has no hosted fallback.

> Important: Obtain consent to upload the **entire original PDF** to the chosen
> service before selecting hosted mode. Pages that already contain text are
> included in the upload.

```swift
import AnyDocSwift
import Foundation

// Call only after the application has obtained consent for the upload.
func convertPDFWithHostedOCR(_ pdf: Data, apiKey: String) async throws -> String {
  try await AnyDocConverter().markdown(
    from: pdf, format: .pdf, ocr: .hosted(apiKey: apiKey)
  )
}
```

Use ``OCRPolicy/reject`` to preserve local-only behavior and the OCR-required
page metadata. Environment variables alone never enable uploads.

### Resolve configuration

| Setting | Resolution, in order |
| --- | --- |
| API key | Explicit `apiKey`, `FIRECRAWL_API_KEY`, then keyless access |
| Base URL | Explicit `apiURL`, `FIRECRAWL_API_URL`, then `https://api.firecrawl.dev` |

Only `nil` falls through. An explicit empty key suppresses environment
credentials and omits authorization. An explicit empty URL is invalid.

The adapter removes at most one trailing slash before appending `/v2/parse`.
A custom base URL changes the recipient of the entire document and must
implement the upstream multipart parse API. Include that recipient in consent.

Credentials belong to the application. Keep them in application-owned
configuration or an appropriate credential store; do not embed secrets in
distributed applications. Sandboxed macOS apps need the outgoing network
entitlement `com.apple.security.network.client` for hosted requests.

### Handle failures and cancellation

The converter preserves its input and Markdown output limits. It applies a
300-second overall deadline and makes no application retries or anonymous
retry after a rejected key. Provider limits may vary; keyless HTTP 429 is
distinguished from authenticated rate limiting.

``AnyDocConversionError/HostedOCRFailure`` distinguishes configuration,
authentication, credits, rate limits, HTTP status, transport, and response
failures. Policy descriptions redact both key and URL, and hosted errors do
not expose provider bodies or credentials.

The converter retains its FIFO slot throughout fallback and cleanup.
Cancelling its task cancels active HTTP work. See <doc:LimitsAndErrors> and the
[buildable hosted OCR example](https://github.com/ngutech21/anydoc-swift/tree/master/Examples/HostedOCR).
