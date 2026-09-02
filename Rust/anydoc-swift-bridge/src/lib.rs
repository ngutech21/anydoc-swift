//! Handwritten C ABI bridge for `AnyDocSwift`.

#![cfg_attr(
    not(test),
    deny(clippy::expect_used, clippy::panic, clippy::unwrap_used)
)]

mod engine;
mod transport;

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::{ptr, slice, str};

const ABI_VERSION: u32 = 3;
const ENGINE_VERSION: &[u8] =
    b"AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 3";

const INVALID_INPUT_CODE: &str = "wrapper.invalidInput";
const INPUT_LIMIT_CODE: &str = "wrapper.inputLimit";
const OUTPUT_LIMIT_CODE: &str = "wrapper.outputLimit";
const DOCUMENT_LIMIT_CODE: &str = "wrapper.documentLimit";
const TRANSPORT_CODE: &str = "bridge.transport";
const TRANSPORT_MESSAGE: &str = "native document transport failed";
const PANIC_CODE: &str = "bridge.panic";
const PANIC_MESSAGE: &str = "native conversion panicked";

const RESULT_KIND_INVALID: i32 = -1;
const RESULT_KIND_FAILURE: i32 = 0;
const RESULT_KIND_MARKDOWN: i32 = 1;
const RESULT_KIND_DOCUMENT: i32 = 2;

/// Opaque owner for one conversion result and all buffers borrowed from it.
///
/// C callers see only the forward-declared `anydoc_swift_result_t` handle.
#[repr(C)]
pub struct AnydocSwiftResult {
    payload: ResultPayload,
}

enum ResultPayload {
    Markdown {
        markdown: Box<[u8]>,
    },
    Document(transport::DocumentPayload),
    Failure {
        code: Box<[u8]>,
        message: Box<[u8]>,
        needs_ocr: Option<NeedsOcrMetadata>,
    },
}

impl AnydocSwiftResult {
    fn success(success: ConversionSuccess) -> Self {
        let payload = match success {
            ConversionSuccess::Markdown(markdown) => ResultPayload::Markdown {
                markdown: markdown.into_bytes().into_boxed_slice(),
            },
            ConversionSuccess::Document(document) => ResultPayload::Document(document),
        };
        Self { payload }
    }

    fn failure(failure: BridgeFailure) -> Self {
        Self {
            payload: ResultPayload::Failure {
                code: failure.code.into_bytes().into_boxed_slice(),
                message: failure.message.into_bytes().into_boxed_slice(),
                needs_ocr: failure.needs_ocr,
            },
        }
    }
}

enum ConversionSuccess {
    Markdown(String),
    Document(transport::DocumentPayload),
}

#[derive(Debug, Eq, PartialEq)]
struct NeedsOcrMetadata {
    pages: Box<[u32]>,
    page_count: u32,
}

#[derive(Debug, Eq, PartialEq)]
struct BridgeFailure {
    code: String,
    message: String,
    needs_ocr: Option<NeedsOcrMetadata>,
}

impl BridgeFailure {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            needs_ocr: None,
        }
    }

    fn needs_ocr(pages: Vec<u32>, page_count: u32, message: impl Into<String>) -> Self {
        Self {
            code: "needsOcr".to_owned(),
            message: message.into(),
            needs_ocr: Some(NeedsOcrMetadata {
                pages: pages.into_boxed_slice(),
                page_count,
            }),
        }
    }
}

fn validate_buffer(pointer: *const u8, length: usize, name: &str) -> Result<(), BridgeFailure> {
    if pointer.is_null() && length != 0 {
        return Err(BridgeFailure::new(
            INVALID_INPUT_CODE,
            format!("{name} is null while its length is non-zero"),
        ));
    }

    if length > isize::MAX as usize {
        return Err(BridgeFailure::new(
            INVALID_INPUT_CODE,
            format!("{name} length exceeds the addressable slice range"),
        ));
    }

    Ok(())
}

unsafe fn decode_raw_input<'a>(
    bytes: *const u8,
    bytes_length: usize,
    format_utf8: *const u8,
    format_length: usize,
) -> Result<(&'a [u8], Option<&'a str>), BridgeFailure> {
    validate_buffer(bytes, bytes_length, "bytes")?;
    validate_buffer(format_utf8, format_length, "format_utf8")?;

    let bytes = if bytes_length == 0 {
        &[]
    } else {
        // SAFETY: `validate_buffer` rejected null and oversized buffers. The
        // exported interface requires the caller to provide readable storage
        // for the complete length while this synchronous call is active. The
        // resulting borrow remains local to this call.
        unsafe { slice::from_raw_parts(bytes, bytes_length) }
    };
    let format_bytes = if format_length == 0 {
        &[]
    } else {
        // SAFETY: `validate_buffer` rejected null and oversized buffers. The
        // exported interface requires the caller to provide readable storage
        // for the complete length while this synchronous call is active. The
        // resulting borrow remains local to this call.
        unsafe { slice::from_raw_parts(format_utf8, format_length) }
    };
    let format = if format_bytes.is_empty() {
        None
    } else {
        Some(str::from_utf8(format_bytes).map_err(|_| {
            BridgeFailure::new(INVALID_INPUT_CODE, "format_utf8 is not valid UTF-8")
        })?)
    };

    Ok((bytes, format))
}

unsafe fn convert_markdown_raw(
    bytes: *const u8,
    bytes_length: usize,
    format_utf8: *const u8,
    format_length: usize,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> Result<ConversionSuccess, BridgeFailure> {
    // SAFETY: The raw export forwards its complete pointer obligations.
    let (bytes, format) =
        unsafe { decode_raw_input(bytes, bytes_length, format_utf8, format_length) }?;
    engine::convert_markdown(bytes, format, maximum_input_bytes, maximum_output_bytes)
        .map(ConversionSuccess::Markdown)
}

unsafe fn convert_document_raw(
    bytes: *const u8,
    bytes_length: usize,
    format_utf8: *const u8,
    format_length: usize,
    maximum_input_bytes: u64,
    maximum_document_bytes: u64,
) -> Result<ConversionSuccess, BridgeFailure> {
    // SAFETY: The raw export forwards its complete pointer obligations.
    let (bytes, format) =
        unsafe { decode_raw_input(bytes, bytes_length, format_utf8, format_length) }?;
    engine::convert_document(bytes, format, maximum_input_bytes, maximum_document_bytes)
        .map(ConversionSuccess::Document)
}

fn run_conversion<F>(operation: F) -> *mut AnydocSwiftResult
where
    F: FnOnce() -> Result<ConversionSuccess, BridgeFailure>,
{
    match catch_unwind(AssertUnwindSafe(|| {
        let result = match operation() {
            Ok(success) => AnydocSwiftResult::success(success),
            Err(failure) => AnydocSwiftResult::failure(failure),
        };
        Box::into_raw(Box::new(result))
    })) {
        Ok(result) => result,
        Err(_) => Box::into_raw(Box::new(AnydocSwiftResult::failure(BridgeFailure::new(
            PANIC_CODE,
            PANIC_MESSAGE,
        )))),
    }
}

unsafe fn result_buffer(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
    select: fn(&ResultPayload) -> Option<&[u8]>,
) -> *const u8 {
    if out_length.is_null() {
        return ptr::null();
    }

    // SAFETY: The caller promises that a non-null output pointer is writable.
    unsafe { out_length.write(0) };

    // SAFETY: The exported accessors require a non-null result pointer to be a
    // live handle returned by this module. `as_ref` handles null explicitly.
    let Some(result) = (unsafe { result.as_ref() }) else {
        return ptr::null();
    };
    let Some(bytes) = select(&result.payload) else {
        return ptr::null();
    };

    // SAFETY: The caller promises that `out_length` is writable.
    unsafe { out_length.write(bytes.len()) };
    if bytes.is_empty() {
        ptr::null()
    } else {
        bytes.as_ptr()
    }
}

fn markdown_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Markdown { markdown } => Some(markdown),
        ResultPayload::Document(_) | ResultPayload::Failure { .. } => None,
    }
}

fn document_manifest_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Document(document) => Some(&document.manifest),
        ResultPayload::Markdown { .. } | ResultPayload::Failure { .. } => None,
    }
}

fn error_code_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Markdown { .. } | ResultPayload::Document(_) => None,
        ResultPayload::Failure { code, .. } => Some(code),
    }
}

fn error_message_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Markdown { .. } | ResultPayload::Document(_) => None,
        ResultPayload::Failure { message, .. } => Some(message),
    }
}

fn needs_ocr_metadata(payload: &ResultPayload) -> Option<&NeedsOcrMetadata> {
    match payload {
        ResultPayload::Markdown { .. } | ResultPayload::Document(_) => None,
        ResultPayload::Failure { needs_ocr, .. } => needs_ocr.as_ref(),
    }
}

/// Returns the C interface version implemented by this bridge.
#[unsafe(no_mangle)]
pub extern "C" fn anydoc_swift_abi_version() -> u32 {
    ABI_VERSION
}

/// Borrows the static UTF-8 engine version string.
///
/// # Safety
///
/// `out_length` must be null or point to writable `size_t` storage. A null
/// pointer returns null because the buffer cannot be consumed safely without
/// its length. The returned bytes are static and must never be freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_engine_version(out_length: *mut usize) -> *const u8 {
    if out_length.is_null() {
        return ptr::null();
    }

    // SAFETY: Required by this function's interface and checked for null.
    unsafe { out_length.write(ENGINE_VERSION.len()) };
    ENGINE_VERSION.as_ptr()
}

/// Converts document bytes to Markdown and returns a Rust-owned result handle.
///
/// # Safety
///
/// A pointer with a non-zero length must reference readable storage for the
/// complete length and remain valid for this synchronous call. Null pointers
/// are allowed only for zero-length buffers. The returned non-null handle must
/// be released exactly once with [`anydoc_swift_result_free`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_convert_markdown(
    bytes: *const u8,
    bytes_length: usize,
    format_utf8: *const u8,
    format_length: usize,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> *mut AnydocSwiftResult {
    run_conversion(|| {
        // SAFETY: This export forwards its documented caller obligations to
        // the concentrated raw-buffer implementation.
        unsafe {
            convert_markdown_raw(
                bytes,
                bytes_length,
                format_utf8,
                format_length,
                maximum_input_bytes,
                maximum_output_bytes,
            )
        }
    })
}

/// Converts document bytes to the structured model transport.
///
/// # Safety
///
/// The pointer and ownership rules are identical to
/// [`anydoc_swift_convert_markdown`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_convert_document(
    bytes: *const u8,
    bytes_length: usize,
    format_utf8: *const u8,
    format_length: usize,
    maximum_input_bytes: u64,
    maximum_document_bytes: u64,
) -> *mut AnydocSwiftResult {
    run_conversion(|| {
        // SAFETY: This export forwards its documented caller obligations to
        // the concentrated raw-buffer implementation.
        unsafe {
            convert_document_raw(
                bytes,
                bytes_length,
                format_utf8,
                format_length,
                maximum_input_bytes,
                maximum_document_bytes,
            )
        }
    })
}

/// Reports the payload kind: failure (0), Markdown (1), or document (2).
///
/// A null handle reports -1.
///
/// # Safety
///
/// `result` must be null or a live handle returned by a bridge conversion.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_kind(result: *const AnydocSwiftResult) -> i32 {
    // SAFETY: Required by this function's interface. `as_ref` handles null.
    match unsafe { result.as_ref() } {
        Some(AnydocSwiftResult {
            payload: ResultPayload::Failure { .. },
        }) => RESULT_KIND_FAILURE,
        Some(AnydocSwiftResult {
            payload: ResultPayload::Markdown { .. },
        }) => RESULT_KIND_MARKDOWN,
        Some(AnydocSwiftResult {
            payload: ResultPayload::Document(_),
        }) => RESULT_KIND_DOCUMENT,
        None => RESULT_KIND_INVALID,
    }
}

/// Borrows the Markdown bytes from a successful result.
///
/// # Safety
///
/// `result` must be null or a live result handle. `out_length` must be null or
/// point to writable `size_t` storage. Returned bytes remain valid only until
/// the result handle is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_markdown(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
) -> *const u8 {
    // SAFETY: The caller obligations are identical to `result_buffer`'s.
    unsafe { result_buffer(result, out_length, markdown_buffer) }
}

/// Borrows the JSON manifest from a structured-document result.
///
/// # Safety
///
/// `result` must be null or a live result handle. `out_length` must be null or
/// point to writable `size_t` storage. Returned bytes remain valid only until
/// the result handle is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_document_manifest(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
) -> *const u8 {
    // SAFETY: The caller obligations are identical to `result_buffer`'s.
    unsafe { result_buffer(result, out_length, document_manifest_buffer) }
}

/// Borrows one asset from a structured-document result by its manifest index.
///
/// Returns 1 for a valid asset, including an empty one; otherwise returns 0.
/// Both outputs are reset before validation and borrowed bytes remain valid
/// only until the owning result is freed.
///
/// # Safety
///
/// `result` must be null or a live result handle. Both output pointers must be
/// null or point to writable storage; both are required for a successful read.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_document_asset(
    result: *const AnydocSwiftResult,
    index: usize,
    out_bytes: *mut *const u8,
    out_length: *mut usize,
) -> i32 {
    if !out_bytes.is_null() {
        // SAFETY: The caller promises that a non-null output pointer is writable.
        unsafe { out_bytes.write(ptr::null()) };
    }
    if !out_length.is_null() {
        // SAFETY: The caller promises that a non-null output pointer is writable.
        unsafe { out_length.write(0) };
    }
    if out_bytes.is_null() || out_length.is_null() {
        return 0;
    }

    // SAFETY: The exported accessor requires a non-null result pointer to be a
    // live handle returned by this module. `as_ref` handles null explicitly.
    let Some(AnydocSwiftResult {
        payload: ResultPayload::Document(document),
    }) = (unsafe { result.as_ref() })
    else {
        return 0;
    };
    let Some(asset) = document.assets.get(index) else {
        return 0;
    };

    // SAFETY: Both output pointers were checked and the caller promises they
    // point to writable storage.
    unsafe { out_length.write(asset.len()) };
    if !asset.is_empty() {
        // SAFETY: `out_bytes` was checked and the asset remains owned by the
        // live result for the complete borrowed lifetime.
        unsafe { out_bytes.write(asset.as_ptr()) };
    }
    1
}

/// Borrows the stable error-code bytes from a failed result.
///
/// # Safety
///
/// `result` must be null or a live result handle. `out_length` must be null or
/// point to writable `size_t` storage. Returned bytes remain valid only until
/// the result handle is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_error_code(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
) -> *const u8 {
    // SAFETY: The caller obligations are identical to `result_buffer`'s.
    unsafe { result_buffer(result, out_length, error_code_buffer) }
}

/// Borrows the human-readable error-message bytes from a failed result.
///
/// # Safety
///
/// `result` must be null or a live result handle. `out_length` must be null or
/// point to writable `size_t` storage. Returned bytes remain valid only until
/// the result handle is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_error_message(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
) -> *const u8 {
    // SAFETY: The caller obligations are identical to `result_buffer`'s.
    unsafe { result_buffer(result, out_length, error_message_buffer) }
}

/// Borrows the one-based page numbers and total page count for `needsOcr`.
///
/// # Safety
///
/// `result` must be null or a live result handle. Both output pointers must
/// point to writable storage; if either is null, the accessor returns null.
/// Returned page numbers remain valid only until the result handle is freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_needs_ocr_pages(
    result: *const AnydocSwiftResult,
    out_length: *mut usize,
    out_page_count: *mut u32,
) -> *const u32 {
    if !out_length.is_null() {
        // SAFETY: The caller promises that a non-null output pointer is writable.
        unsafe { out_length.write(0) };
    }
    if !out_page_count.is_null() {
        // SAFETY: The caller promises that a non-null output pointer is writable.
        unsafe { out_page_count.write(0) };
    }
    if out_length.is_null() || out_page_count.is_null() {
        return ptr::null();
    }

    // SAFETY: The exported accessor requires a non-null result pointer to be a
    // live handle returned by this module. `as_ref` handles null explicitly.
    let Some(result) = (unsafe { result.as_ref() }) else {
        return ptr::null();
    };
    let Some(metadata) = needs_ocr_metadata(&result.payload) else {
        return ptr::null();
    };

    // SAFETY: The caller promises that `out_length` is writable.
    unsafe { out_length.write(metadata.pages.len()) };
    // SAFETY: The caller promises that `out_page_count` is writable.
    unsafe { out_page_count.write(metadata.page_count) };
    if metadata.pages.is_empty() {
        ptr::null()
    } else {
        metadata.pages.as_ptr()
    }
}

/// Releases a result handle and all buffers owned by it.
///
/// # Safety
///
/// `result` must be null or a live handle returned by
/// a bridge conversion that has not previously been freed. After
/// this call, the handle and every buffer borrowed from it are invalid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_free(result: *mut AnydocSwiftResult) {
    if !result.is_null() {
        // SAFETY: Required by this function's interface and checked for null.
        drop(unsafe { Box::from_raw(result) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RTF_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/rtf/handmade-blockstyle.rtf"
    ));
    const CSV_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/csv/handmade-quoted.csv"
    ));
    const MIXED_PDF_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/pdf/handmade-mixed.pdf"
    ));
    const SCANNED_PDF_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/pdf/handmade-scanned.pdf"
    ));
    const TEXT_PDF_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/pdf/text.pdf"
    ));
    const MANY_REFERENCES_FIXTURE: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../Tests/Fixtures/docx/handmade-manyrefs.docx"
    ));
    const RTF_MARKDOWN: &str = concat!(
        "Body before.\n\n",
        "```\n",
        "fn main() {\n",
        "    println!(\"ok\");\n",
        "}\n",
        "```\n\n",
        "Body between.\n\n",
        "> A quotation.\n",
        ">\n",
        "> Its second paragraph.\n\n",
        "Body after.\n"
    );
    const CSV_MARKDOWN: &str = concat!(
        "| name | desc | qty |\n",
        "| --- | --- | --- |\n",
        "| padded | comma, inside | 3 |\n",
        "| plain | multi line | 4 |\n"
    );
    const TEXT_PDF_MARKDOWN: &str = r"# Fixture Document

Plain paragraph with **bold**, *italic*, and <s>struck</s> runs. **Style-bold paragraph with a** NotBold-styled span **inside.**

## Lists

1.First numbered
2.Second numbered
a)Alpha sub one
b)Alpha sub two
i.Roman sub sub
3.Third numbered Interrupting paragraph between lists.
4.Fourth, continuing the count IV.Roman starting at four
V.Roman five •Bullet one •Bullet two ◦Nested bullet
## Table

Wide head End Tall B2 C2 B3 C3

## Notes and special text

Music clef 𝄞 appears before this footnote¹ reference. i An endnote follows here. Persian with ZWNJ: میخواهم. Family emoji: 👨👩👧. Markdown specials: *stars* _under_ [bracket] `tick` #hash 1. dotted | pipe.

## Links and anchors

External link to example. Relative link to <u>a sibling file</u>. This plain paragraph carries a bookmark. Jump to <u>the bookmarked paragraph</u>.

## Objects

Inline image: done.

### Inside the text box.

Text box: after the box.

## Quote and code

Value below one millionth: 0.0000004 should survive.

1 Footnote after an astral character.

i Endnote body text.
";

    type Accessor = unsafe extern "C" fn(*const AnydocSwiftResult, *mut usize) -> *const u8;

    struct OwnedResult(*mut AnydocSwiftResult);

    impl OwnedResult {
        fn convert(
            bytes: Option<&[u8]>,
            format: Option<&[u8]>,
            maximum_input_bytes: u64,
            maximum_output_bytes: u64,
        ) -> Self {
            let (bytes_pointer, bytes_length) = match bytes {
                Some(bytes) => (bytes.as_ptr(), bytes.len()),
                None => (ptr::null(), 0),
            };
            let (format_pointer, format_length) = match format {
                Some(format) => (format.as_ptr(), format.len()),
                None => (ptr::null(), 0),
            };

            // SAFETY: The borrowed slices remain alive for this synchronous
            // call, and every non-zero length has a readable pointer.
            let result = unsafe {
                anydoc_swift_convert_markdown(
                    bytes_pointer,
                    bytes_length,
                    format_pointer,
                    format_length,
                    maximum_input_bytes,
                    maximum_output_bytes,
                )
            };
            assert!(!result.is_null());
            Self(result)
        }

        fn from_operation<F>(operation: F) -> Self
        where
            F: FnOnce() -> Result<String, BridgeFailure>,
        {
            let result = run_conversion(|| operation().map(ConversionSuccess::Markdown));
            assert!(!result.is_null());
            Self(result)
        }

        fn from_document_payload(payload: transport::DocumentPayload) -> Self {
            let result = run_conversion(|| Ok(ConversionSuccess::Document(payload)));
            assert!(!result.is_null());
            Self(result)
        }

        fn document(
            bytes: &[u8],
            format: Option<&[u8]>,
            maximum_input_bytes: u64,
            maximum_document_bytes: u64,
        ) -> Self {
            let (format_pointer, format_length) = match format {
                Some(format) => (format.as_ptr(), format.len()),
                None => (ptr::null(), 0),
            };
            // SAFETY: The borrowed slices remain alive for this synchronous
            // call, and every non-zero length has a readable pointer.
            let result = unsafe {
                anydoc_swift_convert_document(
                    bytes.as_ptr(),
                    bytes.len(),
                    format_pointer,
                    format_length,
                    maximum_input_bytes,
                    maximum_document_bytes,
                )
            };
            assert!(!result.is_null());
            Self(result)
        }

        fn is_success(&self) -> bool {
            self.kind() > RESULT_KIND_FAILURE
        }

        fn kind(&self) -> i32 {
            // SAFETY: `OwnedResult` keeps a live bridge-owned handle.
            unsafe { anydoc_swift_result_kind(self.0) }
        }

        fn bytes(&self, accessor: Accessor) -> Option<Vec<u8>> {
            let mut length = usize::MAX;
            // SAFETY: `OwnedResult` keeps a live handle and `length` is
            // writable for the duration of the accessor call.
            let pointer = unsafe { accessor(self.0, &raw mut length) };
            if pointer.is_null() {
                assert_eq!(length, 0);
                return None;
            }

            // SAFETY: The accessor returned a buffer readable for `length`
            // bytes while this result remains alive. Copy it immediately.
            Some(unsafe { slice::from_raw_parts(pointer, length) }.to_vec())
        }

        fn text(&self, accessor: Accessor) -> Option<String> {
            self.bytes(accessor)
                .map(|bytes| String::from_utf8(bytes).expect("bridge buffers must be UTF-8"))
        }

        fn markdown(&self) -> Option<String> {
            self.text(anydoc_swift_result_markdown)
        }

        fn manifest(&self) -> Option<String> {
            self.text(anydoc_swift_result_document_manifest)
        }

        fn asset(&self, index: usize) -> Option<Vec<u8>> {
            let mut pointer = ptr::NonNull::<u8>::dangling().as_ptr().cast_const();
            let mut length = usize::MAX;
            // SAFETY: `OwnedResult` keeps a live result and both outputs are
            // writable for the complete accessor call.
            let success = unsafe {
                anydoc_swift_result_document_asset(self.0, index, &raw mut pointer, &raw mut length)
            };
            if success == 0 {
                assert!(pointer.is_null());
                assert_eq!(length, 0);
                return None;
            }
            assert_eq!(success, 1);
            if length == 0 {
                assert!(pointer.is_null());
                return Some(Vec::new());
            }
            assert!(!pointer.is_null());
            // SAFETY: A successful accessor returns `length` readable bytes
            // owned by this live result. Copy them immediately.
            Some(unsafe { slice::from_raw_parts(pointer, length) }.to_vec())
        }

        fn error_code(&self) -> Option<String> {
            self.text(anydoc_swift_result_error_code)
        }

        fn error_message(&self) -> Option<String> {
            self.text(anydoc_swift_result_error_message)
        }

        fn needs_ocr(&self) -> Option<(Vec<u32>, u32)> {
            let mut length = usize::MAX;
            let mut page_count = u32::MAX;
            // SAFETY: `OwnedResult` keeps a live handle and both output values
            // are writable for the duration of the accessor call.
            let pointer = unsafe {
                anydoc_swift_result_needs_ocr_pages(self.0, &raw mut length, &raw mut page_count)
            };
            if pointer.is_null() {
                assert_eq!(length, 0);
                assert_eq!(page_count, 0);
                return None;
            }

            // SAFETY: The accessor returned `length` readable `u32` values
            // owned by this live result. Copy them before the handle is freed.
            let pages = unsafe { slice::from_raw_parts(pointer, length) }.to_vec();
            Some((pages, page_count))
        }
    }

    impl Drop for OwnedResult {
        fn drop(&mut self) {
            // SAFETY: `OwnedResult` exclusively owns this live handle and
            // invokes the Rust free function exactly once.
            unsafe { anydoc_swift_result_free(self.0) };
        }
    }

    fn assert_failure(result: &OwnedResult, expected_code: &str) {
        assert!(!result.is_success());
        assert_eq!(result.markdown(), None);
        assert_eq!(result.error_code().as_deref(), Some(expected_code));
        assert!(
            result
                .error_message()
                .is_some_and(|message| !message.is_empty())
        );
        assert_eq!(result.needs_ocr(), None);
    }

    #[test]
    fn converts_real_rtf_bytes_to_markdown() {
        let markdown = engine::convert_markdown(RTF_FIXTURE, None, u64::MAX, u64::MAX)
            .expect("RTF fixture should convert");
        assert_eq!(markdown, RTF_MARKDOWN);
    }

    #[test]
    fn document_conversion_has_a_distinct_kind_and_manifest() {
        let result = OwnedResult::document(RTF_FIXTURE, None, u64::MAX, u64::MAX);
        assert_eq!(result.kind(), 2);
        assert!(
            result
                .manifest()
                .is_some_and(|manifest| manifest.starts_with("{\"schemaVersion\":1,"))
        );
        assert_eq!(result.markdown(), None);
    }

    #[test]
    fn document_conversion_respects_format_pdf_and_wire_limits() {
        let automatic = OwnedResult::document(RTF_FIXTURE, None, u64::MAX, u64::MAX);
        let explicit_csv = OwnedResult::document(RTF_FIXTURE, Some(b"csv"), u64::MAX, u64::MAX);
        assert_eq!(automatic.kind(), RESULT_KIND_DOCUMENT);
        assert_eq!(explicit_csv.kind(), RESULT_KIND_DOCUMENT);
        assert_ne!(automatic.manifest(), explicit_csv.manifest());

        let csv_without_format = OwnedResult::document(CSV_FIXTURE, None, u64::MAX, u64::MAX);
        assert_failure(&csv_without_format, "unsupported");
        let csv_with_format = OwnedResult::document(CSV_FIXTURE, Some(b"csv"), u64::MAX, u64::MAX);
        assert_eq!(csv_with_format.kind(), RESULT_KIND_DOCUMENT);

        let pdf = OwnedResult::document(TEXT_PDF_FIXTURE, None, u64::MAX, u64::MAX);
        assert_failure(&pdf, "unsupported");

        let manifest_length = u64::try_from(
            automatic
                .manifest()
                .expect("automatic document has a manifest")
                .len(),
        )
        .expect("manifest length fits UInt64");
        let exact = OwnedResult::document(RTF_FIXTURE, None, u64::MAX, manifest_length);
        assert_eq!(exact.kind(), RESULT_KIND_DOCUMENT);
        let over = OwnedResult::document(
            RTF_FIXTURE,
            None,
            u64::MAX,
            manifest_length.saturating_sub(1),
        );
        assert_failure(&over, DOCUMENT_LIMIT_CODE);
    }

    #[test]
    fn result_kind_and_accessors_distinguish_empty_payloads_from_mismatches() {
        let markdown = OwnedResult::from_operation(|| Ok(String::new()));
        assert_eq!(markdown.kind(), RESULT_KIND_MARKDOWN);
        assert_eq!(markdown.markdown(), None);
        assert_eq!(markdown.manifest(), None);
        assert_eq!(markdown.asset(0), None);

        let document = OwnedResult::from_document_payload(transport::DocumentPayload {
            manifest: br#"{"schemaVersion":1,"blocks":[],"notes":[],"assets":[]}"#
                .to_vec()
                .into_boxed_slice(),
            assets: vec![Vec::new().into_boxed_slice(), vec![7].into_boxed_slice()],
        });
        assert_eq!(document.kind(), RESULT_KIND_DOCUMENT);
        assert_eq!(document.markdown(), None);
        assert!(document.manifest().is_some());
        assert_eq!(document.asset(0), Some(vec![]));
        assert_eq!(document.asset(1), Some(vec![7]));
        assert_eq!(document.asset(2), None);

        let failure = OwnedResult::convert(None, None, u64::MAX, u64::MAX);
        assert_eq!(failure.kind(), RESULT_KIND_FAILURE);
        assert_eq!(failure.manifest(), None);
        assert_eq!(failure.asset(0), None);
    }

    #[test]
    fn repeated_references_reuse_one_stable_asset() {
        let result =
            OwnedResult::document(MANY_REFERENCES_FIXTURE, Some(b"docx"), u64::MAX, u64::MAX);
        let manifest = result.manifest().expect("document has a manifest");
        assert_eq!(
            manifest.matches("\"kind\":\"asset\",\"value\":0").count(),
            70
        );
        let first = result.asset(0).expect("shared asset is present");
        assert_eq!(first.len(), 65_544);
        assert_eq!(result.asset(0), Some(first));
        assert_eq!(result.asset(1), None);
    }

    #[test]
    fn reports_embedded_abi_and_engine_versions() {
        assert_eq!(anydoc_swift_abi_version(), 3);

        let mut length = 0;
        // SAFETY: `length` is writable for the accessor call.
        let pointer = unsafe { anydoc_swift_engine_version(&raw mut length) };
        assert!(!pointer.is_null());
        // SAFETY: The engine version accessor returns a static buffer of the
        // reported length.
        let version = unsafe { slice::from_raw_parts(pointer, length) };
        assert_eq!(version, ENGINE_VERSION);

        // SAFETY: A null output-length pointer is explicitly supported.
        assert!(unsafe { anydoc_swift_engine_version(ptr::null_mut()) }.is_null());
    }

    #[test]
    fn rejects_invalid_pointer_and_length_pairs() {
        // SAFETY: This deliberately violates only the documented null/length
        // invariant; the implementation must reject it before dereferencing.
        let null_bytes = unsafe {
            anydoc_swift_convert_markdown(ptr::null(), 1, ptr::null(), 0, u64::MAX, u64::MAX)
        };
        let null_bytes = OwnedResult(null_bytes);
        assert_failure(&null_bytes, INVALID_INPUT_CODE);

        // SAFETY: Same deliberate invariant violation for the canonical format.
        let null_format = unsafe {
            anydoc_swift_convert_markdown(
                RTF_FIXTURE.as_ptr(),
                RTF_FIXTURE.len(),
                ptr::null(),
                1,
                u64::MAX,
                u64::MAX,
            )
        };
        let null_format = OwnedResult(null_format);
        assert_failure(&null_format, INVALID_INPUT_CODE);

        let oversized_length = (isize::MAX as usize).saturating_add(1);
        // SAFETY: The oversized length must be rejected before the non-null
        // dangling pointer is ever converted into a slice.
        let oversized = unsafe {
            anydoc_swift_convert_markdown(
                ptr::NonNull::<u8>::dangling().as_ptr(),
                oversized_length,
                ptr::null(),
                0,
                u64::MAX,
                u64::MAX,
            )
        };
        let oversized = OwnedResult(oversized);
        assert_failure(&oversized, INVALID_INPUT_CODE);
    }

    #[test]
    fn empty_input_preserves_the_upstream_error_code() {
        let result = OwnedResult::convert(None, None, u64::MAX, u64::MAX);
        assert_failure(&result, "unsupported");
    }

    #[test]
    fn rejects_invalid_utf8_and_noncanonical_formats() {
        let result = OwnedResult::convert(Some(RTF_FIXTURE), Some(&[0xff]), u64::MAX, u64::MAX);
        assert_failure(&result, INVALID_INPUT_CODE);
        for format in [b"RTF".as_slice(), b"docm".as_slice(), b"unknown".as_slice()] {
            let result = OwnedResult::convert(Some(RTF_FIXTURE), Some(format), u64::MAX, u64::MAX);
            assert_failure(&result, INVALID_INPUT_CODE);
        }
    }

    #[test]
    fn enforces_input_and_output_limits() {
        let input_limited = OwnedResult::convert(
            Some(RTF_FIXTURE),
            None,
            u64::try_from(RTF_FIXTURE.len() - 1).unwrap(),
            u64::MAX,
        );
        assert_failure(&input_limited, INPUT_LIMIT_CODE);

        let output_limited = OwnedResult::convert(
            Some(RTF_FIXTURE),
            None,
            u64::MAX,
            u64::try_from(RTF_MARKDOWN.len() - 1).unwrap(),
        );
        assert_failure(&output_limited, OUTPUT_LIMIT_CODE);

        let exact_output_limit = OwnedResult::convert(
            Some(RTF_FIXTURE),
            None,
            u64::MAX,
            u64::try_from(RTF_MARKDOWN.len()).unwrap(),
        );
        assert_eq!(exact_output_limit.markdown().as_deref(), Some(RTF_MARKDOWN));
    }

    #[test]
    fn explicit_format_authoritatively_selects_its_parser() {
        let result = OwnedResult::convert(Some(RTF_FIXTURE), Some(b"csv"), u64::MAX, u64::MAX);
        assert_ne!(result.markdown().as_deref(), Some(RTF_MARKDOWN));
    }

    #[test]
    fn csv_requires_an_explicit_format() {
        let without_format = OwnedResult::convert(Some(CSV_FIXTURE), None, u64::MAX, u64::MAX);
        assert_failure(&without_format, "unsupported");

        let with_format = OwnedResult::convert(Some(CSV_FIXTURE), Some(b"csv"), u64::MAX, u64::MAX);
        assert_eq!(with_format.markdown().as_deref(), Some(CSV_MARKDOWN));
    }

    #[test]
    fn pdfs_needing_ocr_fail_without_markdown() {
        let cases: [(&[u8], &[u32], u32); 2] = [
            (MIXED_PDF_FIXTURE, &[2], 2),
            (SCANNED_PDF_FIXTURE, &[1, 2], 2),
        ];

        for (fixture, expected_pages, expected_page_count) in cases {
            let result = OwnedResult::convert(Some(fixture), None, u64::MAX, u64::MAX);
            assert!(!result.is_success());
            assert_eq!(result.markdown(), None);
            assert_eq!(result.error_code().as_deref(), Some("needsOcr"));
            assert!(
                result
                    .error_message()
                    .is_some_and(|message| !message.is_empty())
            );
            assert_eq!(
                result.needs_ocr(),
                Some((expected_pages.to_vec(), expected_page_count))
            );
        }
    }

    #[test]
    fn text_pdf_converts_to_markdown() {
        let result = OwnedResult::convert(Some(TEXT_PDF_FIXTURE), None, u64::MAX, u64::MAX);
        assert_eq!(result.markdown().as_deref(), Some(TEXT_PDF_MARKDOWN));
    }

    #[test]
    fn preserves_known_and_future_error_codes() {
        for code in [
            "unsupported",
            "malformed",
            "encrypted",
            "resourceLimit",
            "missingPart",
            "io",
            "future.upstreamCode",
        ] {
            let result = OwnedResult::from_operation(|| {
                Err(BridgeFailure::new(code, "synthetic upstream failure"))
            });
            assert_failure(&result, code);
        }
    }

    #[test]
    fn contains_panics_through_the_private_execution_seam() {
        let result = OwnedResult::from_operation(|| -> Result<String, BridgeFailure> {
            panic!("test panic payload must not cross the C interface")
        });

        assert_failure(&result, PANIC_CODE);
        assert_eq!(result.error_message().as_deref(), Some(PANIC_MESSAGE));
    }

    #[test]
    fn success_and_failure_buffers_obey_result_invariants() {
        let success = OwnedResult::convert(Some(RTF_FIXTURE), None, u64::MAX, u64::MAX);
        assert!(success.is_success());
        assert_eq!(success.error_code(), None);
        assert_eq!(success.error_message(), None);
        assert_eq!(success.needs_ocr(), None);

        let mut first_length = 0;
        let mut second_length = 0;
        // SAFETY: `success` owns a live result and both lengths are writable.
        let first = unsafe { anydoc_swift_result_markdown(success.0, &raw mut first_length) };
        // SAFETY: Same live result and writable output storage.
        let second = unsafe { anydoc_swift_result_markdown(success.0, &raw mut second_length) };
        assert_eq!(first, second);
        assert_eq!(first_length, second_length);
        assert_eq!(first_length, RTF_MARKDOWN.len());

        let failure = OwnedResult::convert(None, None, u64::MAX, u64::MAX);
        assert_failure(&failure, "unsupported");

        for accessor in [
            anydoc_swift_result_error_code as Accessor,
            anydoc_swift_result_error_message as Accessor,
        ] {
            let mut first_length = 0;
            let mut second_length = 0;
            // SAFETY: `failure` owns a live result and both lengths are
            // writable for the duration of these calls.
            let first = unsafe { accessor(failure.0, &raw mut first_length) };
            // SAFETY: Same live result and writable output storage.
            let second = unsafe { accessor(failure.0, &raw mut second_length) };
            assert!(!first.is_null());
            assert_eq!(first, second);
            assert_eq!(first_length, second_length);
            assert_ne!(first_length, 0);
        }
    }

    #[test]
    fn null_accessors_and_free_are_safe() {
        // SAFETY: Null result handles are explicitly supported.
        let null_kind = unsafe { anydoc_swift_result_kind(ptr::null()) };
        assert_eq!(null_kind, RESULT_KIND_INVALID);

        for accessor in [
            anydoc_swift_result_markdown as Accessor,
            anydoc_swift_result_document_manifest as Accessor,
            anydoc_swift_result_error_code as Accessor,
            anydoc_swift_result_error_message as Accessor,
        ] {
            let mut length = usize::MAX;
            // SAFETY: Null result handles are supported and `length` is
            // writable, so it must be reset to zero.
            let pointer = unsafe { accessor(ptr::null(), &raw mut length) };
            assert!(pointer.is_null());
            assert_eq!(length, 0);
        }

        let mut length = usize::MAX;
        let mut page_count = u32::MAX;
        // SAFETY: Null result handles are supported and both outputs are
        // writable, so they must be reset to zero.
        let pages = unsafe {
            anydoc_swift_result_needs_ocr_pages(ptr::null(), &raw mut length, &raw mut page_count)
        };
        assert!(pages.is_null());
        assert_eq!(length, 0);
        assert_eq!(page_count, 0);

        let mut asset_pointer = ptr::NonNull::<u8>::dangling().as_ptr().cast_const();
        let mut asset_length = usize::MAX;
        // SAFETY: Null result handles are supported and both outputs are writable.
        let asset_status = unsafe {
            anydoc_swift_result_document_asset(
                ptr::null(),
                0,
                &raw mut asset_pointer,
                &raw mut asset_length,
            )
        };
        assert_eq!(asset_status, 0);
        assert!(asset_pointer.is_null());
        assert_eq!(asset_length, 0);

        let result = OwnedResult::convert(Some(RTF_FIXTURE), None, u64::MAX, u64::MAX);
        for accessor in [
            anydoc_swift_result_markdown as Accessor,
            anydoc_swift_result_document_manifest as Accessor,
            anydoc_swift_result_error_code as Accessor,
            anydoc_swift_result_error_message as Accessor,
        ] {
            // SAFETY: A null output-length pointer is explicitly supported.
            assert!(unsafe { accessor(result.0, ptr::null_mut()) }.is_null());
        }

        let mut length = usize::MAX;
        let mut page_count = u32::MAX;
        // SAFETY: A null page-count pointer is explicitly supported and the
        // non-null length must still be reset.
        let pages = unsafe {
            anydoc_swift_result_needs_ocr_pages(result.0, &raw mut length, ptr::null_mut())
        };
        assert!(pages.is_null());
        assert_eq!(length, 0);

        // SAFETY: A null length pointer is explicitly supported and the
        // non-null page count must still be reset.
        let pages = unsafe {
            anydoc_swift_result_needs_ocr_pages(result.0, ptr::null_mut(), &raw mut page_count)
        };
        assert!(pages.is_null());
        assert_eq!(page_count, 0);

        let mut asset_length = usize::MAX;
        // SAFETY: A null byte-pointer output is supported and the non-null
        // length must still be reset.
        let asset_status = unsafe {
            anydoc_swift_result_document_asset(result.0, 0, ptr::null_mut(), &raw mut asset_length)
        };
        assert_eq!(asset_status, 0);
        assert_eq!(asset_length, 0);

        // SAFETY: Freeing a null handle is explicitly a no-op.
        unsafe { anydoc_swift_result_free(ptr::null_mut()) };
    }

    #[test]
    #[allow(
        clippy::mem_forget,
        reason = "the test transfers ownership to a raw handle and frees it through the C ABI"
    )]
    fn rust_free_releases_a_live_result() {
        let result = OwnedResult::convert(Some(RTF_FIXTURE), None, u64::MAX, u64::MAX);
        let raw = result.0;
        std::mem::forget(result);

        // SAFETY: `raw` is a live, exclusively owned handle and is freed once.
        unsafe { anydoc_swift_result_free(raw) };
    }
}
