# Hosted OCR example — pending release

This example compiles against the candidate checkout. Hosted OCR is not in the
released `0.2.0` Swift API. The existing
[`AnyDocSwiftExample`](../AnyDocSwiftExample) remains a local-only consumer pinned
to that released version.

From the repository root:

```sh
# Build only; no OCR request is made.
swift build --package-path Examples/HostedOCR

# Safe local fixture: succeeds locally, even with hosted fallback selected.
swift run --package-path Examples/HostedOCR HostedOCRExample \
  --allow-upload Tests/Fixtures/pdf/text.pdf
```

For a scanned or mixed PDF, the explicit `--allow-upload` flag consents to sending
the **entire original PDF**, including text pages, if local parsing requires OCR.
The example resolves `FIRECRAWL_API_KEY` and `FIRECRAWL_API_URL` only when fallback
begins. Without a URL it calls `https://api.firecrawl.dev/v2/parse`; without a key
it uses the service's keyless allowance. A custom URL changes the recipient and
must implement the upstream parse API. Merely setting environment variables
does not enable hosted conversion in applications using the local-only API.

Applications can pass `.hosted(apiKey:apiURL:)` directly. Only `nil` falls through
to the environment; an empty key suppresses authorization and an empty URL is an
error. Credentials are application-owned. Sandboxed macOS applications need
`com.apple.security.network.client` for outgoing requests.

After the Swift API is published, update this example's dependency to the exact
published version and resolve its lockfile. Do not change the released-version
example's pin before publication. Native artifact pins remain unchanged.
