# ``AnyDocSwift``

Convert document bytes to Markdown or a structured document in Swift applications.

## Overview

AnyDocSwift wraps the anydoc engine and runs conversion locally by default.
Pass complete document data to ``AnyDocConverter`` and choose Markdown for
display or export, or an ``AnyDocDocument`` for inspecting the document's
structure and embedded assets. SwiftPM downloads the native engine automatically;
applications do not need Rust or Cargo.

The package supports macOS on Apple Silicon, iOS and iPadOS on arm64 devices
and Apple-Silicon simulators, and GNU/Linux on x86_64 and arm64. See the
[README](https://github.com/ngutech21/anydoc-swift#requirements) for current
minimum versions and platform requirements.

PDF conversion produces Markdown only. Local OCR is unavailable; a PDF that
requires OCR fails unless the application explicitly permits hosted fallback
using ``OCRPolicy``. See <doc:HostedOCR> before enabling uploads.

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:FormatsAndPDFs>

### Working with results

- <doc:StructuredDocuments>
- <doc:LimitsAndErrors>
- <doc:HostedOCR>

### Converting documents

- ``AnyDocConverter``
- ``AnyDocFormat``

### Reading structured documents

- ``AnyDocDocument``

### Controlling limits and failures

- ``AnyDocConverter/Limits``
- ``AnyDocConversionError``
- ``OCRPolicy``
