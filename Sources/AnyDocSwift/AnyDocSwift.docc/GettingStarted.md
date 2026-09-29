# Getting started

Add AnyDocSwift to your application and convert your first document.

## Overview

Add `https://github.com/ngutech21/anydoc-swift.git` as a Swift package dependency
and select the `AnyDocSwift` product for your application's target. Use a Swift
package release tag, rather than a `binary-*` artifact tag. The
[installation example](https://github.com/ngutech21/anydoc-swift#installation)
contains the current release version and a complete package manifest.

SwiftPM downloads and verifies the native engine. No Rust installation or
external conversion process is needed by consumers.

### Convert bytes to Markdown

Create a converter and pass it a complete in-memory document. This example uses
CSV so it can run without a sample file:

```swift
import AnyDocSwift
import Foundation

let converter = AnyDocConverter()
let bytes = Data("name,value\nexample,42\n".utf8)
let markdown = try await converter.markdown(from: bytes, format: .csv)
print(markdown)
```

Use the same converter for repeated operations. Each instance processes complete
operations in FIFO order; separate instances may convert concurrently.

### Load a file

File access belongs to the application. Check the file size before loading
untrusted or large input, and obtain any required security-scoped access in
your application:

```swift
import AnyDocSwift
import Foundation

let url = URL(fileURLWithPath: "/path/to/report.docx")
let bytes = try Data(contentsOf: url)
let markdown = try await AnyDocConverter().markdown(from: bytes)
print(markdown)
```

Omitting `format` asks anydoc to detect it from the content. Signature-less CSV
needs an explicit format. To select a parser using a filename instead, see
<doc:FormatsAndPDFs>.

The library returns complete results. It does not provide streaming output or
progress callbacks. See <doc:LimitsAndErrors> for size limits and cancellation,
and <doc:StructuredDocuments> when you need blocks, tables, notes, or assets.
