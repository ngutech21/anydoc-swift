# Conversion errors

All conversions use `AnyDocConversionError`; cancellation uses
`CancellationError` and takes precedence when observed before returning.
Local errors and OCR page metadata retain their existing behavior. The
`markdown(from:format:)` overload and `.reject` return
`.needsOCR(pages:pageCount:)` with sorted, unique, one-based page numbers and
no partial Markdown.

Hosted OCR failures use `.hostedOCR(HostedOCRFailure)`:

| Failure | Meaning |
| --- | --- |
| `.invalidConfiguration` | Invalid endpoint or authorization header configuration, including an explicit empty URL. |
| `.authentication` | HTTP 401. No retry without credentials. |
| `.insufficientCredits` | HTTP 402. |
| `.rateLimited(keyless: true)` | HTTP 429 after keyless selection. The description suggests supplying an API key. |
| `.rateLimited(keyless: false)` | HTTP 429 after selecting a nonempty key. |
| `.server(statusCode:)` | HTTP 500–599. |
| `.http(statusCode:)` | Other unsuccessful HTTP status, including provider upload-size rejections. |
| `.transport` | Network failure, redirect failure/exhaustion, or the overall 300-second deadline. |
| `.malformedResponse` | Invalid JSON, unsuccessful `success`, or missing/empty/non-string Markdown in a 2xx response. |

Successful hosted output still throws `.outputTooLarge(maximumBytes:)` when its
final UTF-8 bytes, including any appended newline, exceed the configured limit.
Input limits are checked before native conversion or HTTP.

Hosted error values and descriptions contain fixed text and status codes only:
never provider bodies, credentials, destination URLs, document contents, or
underlying error descriptions. `OCRPolicy` string/debug descriptions redact both
key and URL. Applications should handle typed cases rather than parsing display
strings. The library never retries a hosted failure automatically.
