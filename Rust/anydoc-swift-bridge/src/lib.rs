//! Handwritten C ABI bridge for `AnyDocSwift`.

#![cfg_attr(
    not(test),
    deny(clippy::expect_used, clippy::panic, clippy::unwrap_used)
)]

mod engine;

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::{ptr, slice, str};

const ABI_VERSION: u32 = 1;
const ENGINE_VERSION: &[u8] =
    b"AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); AnyDocSwift bridge ABI 1";

const INVALID_INPUT_CODE: &str = "wrapper.invalidInput";
const INPUT_LIMIT_CODE: &str = "wrapper.inputLimit";
const OUTPUT_LIMIT_CODE: &str = "wrapper.outputLimit";
const PANIC_CODE: &str = "bridge.panic";
const PANIC_MESSAGE: &str = "native conversion panicked";

/// Opaque owner for one conversion result and all buffers borrowed from it.
///
/// C callers see only the forward-declared `anydoc_swift_result_t` handle.
#[repr(C)]
pub struct AnydocSwiftResult {
    payload: ResultPayload,
}

enum ResultPayload {
    Success { markdown: Box<[u8]> },
    Failure { code: Box<[u8]>, message: Box<[u8]> },
}

impl AnydocSwiftResult {
    fn success(markdown: String) -> Self {
        Self {
            payload: ResultPayload::Success {
                markdown: markdown.into_bytes().into_boxed_slice(),
            },
        }
    }

    fn failure(failure: BridgeFailure) -> Self {
        Self {
            payload: ResultPayload::Failure {
                code: failure.code.into_bytes().into_boxed_slice(),
                message: failure.message.into_bytes().into_boxed_slice(),
            },
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
struct BridgeFailure {
    code: String,
    message: String,
}

impl BridgeFailure {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
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

unsafe fn convert_raw(
    bytes: *const u8,
    bytes_length: usize,
    extension_utf8: *const u8,
    extension_length: usize,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> Result<String, BridgeFailure> {
    validate_buffer(bytes, bytes_length, "bytes")?;
    validate_buffer(extension_utf8, extension_length, "extension_utf8")?;

    let bytes = if bytes_length == 0 {
        &[]
    } else {
        // SAFETY: `validate_buffer` rejected null and oversized buffers. The
        // exported interface requires the caller to provide readable storage
        // for the complete length while this synchronous call is active. The
        // resulting borrow remains local to this call.
        unsafe { slice::from_raw_parts(bytes, bytes_length) }
    };
    let extension_bytes = if extension_length == 0 {
        &[]
    } else {
        // SAFETY: `validate_buffer` rejected null and oversized buffers. The
        // exported interface requires the caller to provide readable storage
        // for the complete length while this synchronous call is active. The
        // resulting borrow remains local to this call.
        unsafe { slice::from_raw_parts(extension_utf8, extension_length) }
    };
    let extension = if extension_bytes.is_empty() {
        None
    } else {
        Some(str::from_utf8(extension_bytes).map_err(|_| {
            BridgeFailure::new(INVALID_INPUT_CODE, "extension_utf8 is not valid UTF-8")
        })?)
    };

    engine::convert_markdown(bytes, extension, maximum_input_bytes, maximum_output_bytes)
}

fn run_conversion<F>(operation: F) -> *mut AnydocSwiftResult
where
    F: FnOnce() -> Result<String, BridgeFailure>,
{
    match catch_unwind(AssertUnwindSafe(|| {
        let result = match operation() {
            Ok(markdown) => AnydocSwiftResult::success(markdown),
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
        ResultPayload::Success { markdown } => Some(markdown),
        ResultPayload::Failure { .. } => None,
    }
}

fn error_code_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Success { .. } => None,
        ResultPayload::Failure { code, .. } => Some(code),
    }
}

fn error_message_buffer(payload: &ResultPayload) -> Option<&[u8]> {
    match payload {
        ResultPayload::Success { .. } => None,
        ResultPayload::Failure { message, .. } => Some(message),
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
    extension_utf8: *const u8,
    extension_length: usize,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> *mut AnydocSwiftResult {
    run_conversion(|| {
        // SAFETY: This export forwards its documented caller obligations to
        // the concentrated raw-buffer implementation.
        unsafe {
            convert_raw(
                bytes,
                bytes_length,
                extension_utf8,
                extension_length,
                maximum_input_bytes,
                maximum_output_bytes,
            )
        }
    })
}

/// Reports whether a result contains Markdown.
///
/// # Safety
///
/// `result` must be null or a live handle returned by
/// [`anydoc_swift_convert_markdown`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anydoc_swift_result_is_success(result: *const AnydocSwiftResult) -> i32 {
    // SAFETY: Required by this function's interface. `as_ref` handles null.
    match unsafe { result.as_ref() } {
        Some(AnydocSwiftResult {
            payload: ResultPayload::Success { .. },
        }) => 1,
        Some(AnydocSwiftResult {
            payload: ResultPayload::Failure { .. },
        })
        | None => 0,
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

/// Releases a result handle and all buffers owned by it.
///
/// # Safety
///
/// `result` must be null or a live handle returned by
/// [`anydoc_swift_convert_markdown`] that has not previously been freed. After
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

    type Accessor = unsafe extern "C" fn(*const AnydocSwiftResult, *mut usize) -> *const u8;

    struct OwnedResult(*mut AnydocSwiftResult);

    impl OwnedResult {
        fn convert(
            bytes: Option<&[u8]>,
            extension: Option<&[u8]>,
            maximum_input_bytes: u64,
            maximum_output_bytes: u64,
        ) -> Self {
            let (bytes_pointer, bytes_length) = match bytes {
                Some(bytes) => (bytes.as_ptr(), bytes.len()),
                None => (ptr::null(), 0),
            };
            let (extension_pointer, extension_length) = match extension {
                Some(extension) => (extension.as_ptr(), extension.len()),
                None => (ptr::null(), 0),
            };

            // SAFETY: The borrowed slices remain alive for this synchronous
            // call, and every non-zero length has a readable pointer.
            let result = unsafe {
                anydoc_swift_convert_markdown(
                    bytes_pointer,
                    bytes_length,
                    extension_pointer,
                    extension_length,
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
            let result = run_conversion(operation);
            assert!(!result.is_null());
            Self(result)
        }

        fn is_success(&self) -> bool {
            // SAFETY: `OwnedResult` keeps a live bridge-owned handle.
            unsafe { anydoc_swift_result_is_success(self.0) == 1 }
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

        fn error_code(&self) -> Option<String> {
            self.text(anydoc_swift_result_error_code)
        }

        fn error_message(&self) -> Option<String> {
            self.text(anydoc_swift_result_error_message)
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
    }

    #[test]
    fn converts_real_rtf_bytes_to_markdown() {
        let markdown = engine::convert_markdown(RTF_FIXTURE, None, u64::MAX, u64::MAX)
            .expect("RTF fixture should convert");
        assert_eq!(markdown, RTF_MARKDOWN);
    }

    #[test]
    fn reports_embedded_abi_and_engine_versions() {
        assert_eq!(anydoc_swift_abi_version(), 1);

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

        // SAFETY: Same deliberate invariant violation for the extension.
        let null_extension = unsafe {
            anydoc_swift_convert_markdown(
                RTF_FIXTURE.as_ptr(),
                RTF_FIXTURE.len(),
                ptr::null(),
                1,
                u64::MAX,
                u64::MAX,
            )
        };
        let null_extension = OwnedResult(null_extension);
        assert_failure(&null_extension, INVALID_INPUT_CODE);

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
    fn rejects_invalid_utf8_extension() {
        let result = OwnedResult::convert(Some(RTF_FIXTURE), Some(&[0xff]), u64::MAX, u64::MAX);
        assert_failure(&result, INVALID_INPUT_CODE);
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
    fn content_detection_precedes_the_extension_hint() {
        let result = OwnedResult::convert(Some(RTF_FIXTURE), Some(b"csv"), u64::MAX, u64::MAX);
        assert_eq!(result.markdown().as_deref(), Some(RTF_MARKDOWN));
    }

    #[test]
    fn csv_uses_extension_fallback() {
        let without_extension = OwnedResult::convert(Some(CSV_FIXTURE), None, u64::MAX, u64::MAX);
        assert_failure(&without_extension, "unsupported");

        let with_extension =
            OwnedResult::convert(Some(CSV_FIXTURE), Some(b"csv"), u64::MAX, u64::MAX);
        assert_eq!(with_extension.markdown().as_deref(), Some(CSV_MARKDOWN));
    }

    #[test]
    fn pdfs_needing_ocr_fail_without_markdown() {
        for fixture in [MIXED_PDF_FIXTURE, SCANNED_PDF_FIXTURE] {
            let result = OwnedResult::convert(Some(fixture), None, u64::MAX, u64::MAX);
            assert_failure(&result, "needsOcr");
            assert_eq!(result.markdown(), None);
        }
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
        assert_eq!(unsafe { anydoc_swift_result_is_success(ptr::null()) }, 0);

        for accessor in [
            anydoc_swift_result_markdown as Accessor,
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

        let result = OwnedResult::convert(Some(RTF_FIXTURE), None, u64::MAX, u64::MAX);
        for accessor in [
            anydoc_swift_result_markdown as Accessor,
            anydoc_swift_result_error_code as Accessor,
            anydoc_swift_result_error_message as Accessor,
        ] {
            // SAFETY: A null output-length pointer is explicitly supported.
            assert!(unsafe { accessor(result.0, ptr::null_mut()) }.is_null());
        }

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
