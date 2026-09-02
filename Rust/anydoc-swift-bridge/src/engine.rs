//! Safe document conversion and limit enforcement.

#![forbid(unsafe_code)]

use super::transport::{self, DocumentPayload};
use super::{BridgeFailure, INPUT_LIMIT_CODE, OUTPUT_LIMIT_CODE};

impl From<anydoc::ConvertError> for BridgeFailure {
    fn from(error: anydoc::ConvertError) -> Self {
        let message = error.to_string();
        match error {
            anydoc::ConvertError::NeedsOcr { pages, page_count } => {
                Self::needs_ocr(pages, page_count, message)
            }
            error => Self::new(error.code(), message),
        }
    }
}

/// Converts validated document bytes to Markdown within the configured limits.
pub(super) fn convert_markdown(
    bytes: &[u8],
    format: Option<&str>,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> Result<String, BridgeFailure> {
    validate_input(bytes, maximum_input_bytes)?;

    let format = format.map(parse_canonical_format).transpose()?;
    let markdown = anydoc::to_markdown_bytes(bytes, format).map_err(BridgeFailure::from)?;
    let output_length = u64::try_from(markdown.len()).map_err(|_| {
        BridgeFailure::new(
            OUTPUT_LIMIT_CODE,
            "Markdown length cannot be represented as UInt64",
        )
    })?;
    if output_length > maximum_output_bytes {
        return Err(BridgeFailure::new(
            OUTPUT_LIMIT_CODE,
            format!(
                "Markdown is {output_length} bytes, exceeding the {maximum_output_bytes}-byte limit"
            ),
        ));
    }

    Ok(markdown)
}

/// Converts validated document bytes to the versioned structured transport.
pub(super) fn convert_document(
    bytes: &[u8],
    format: Option<&str>,
    maximum_input_bytes: u64,
    maximum_document_bytes: u64,
) -> Result<DocumentPayload, BridgeFailure> {
    validate_input(bytes, maximum_input_bytes)?;
    let format = format.map(parse_canonical_format).transpose()?;
    let document = anydoc::to_document(bytes, format).map_err(BridgeFailure::from)?;
    transport::encode_document(document, maximum_document_bytes)
}

fn validate_input(bytes: &[u8], maximum_input_bytes: u64) -> Result<(), BridgeFailure> {
    let input_length = u64::try_from(bytes.len()).map_err(|_| {
        BridgeFailure::new(
            INPUT_LIMIT_CODE,
            "input length cannot be represented as UInt64",
        )
    })?;
    if input_length > maximum_input_bytes {
        return Err(BridgeFailure::new(
            INPUT_LIMIT_CODE,
            format!(
                "input is {input_length} bytes, exceeding the {maximum_input_bytes}-byte limit"
            ),
        ));
    }
    Ok(())
}

fn parse_canonical_format(format: &str) -> Result<anydoc::Format, BridgeFailure> {
    match format {
        "doc" => Ok(anydoc::Format::Doc),
        "docx" => Ok(anydoc::Format::Docx),
        "odt" => Ok(anydoc::Format::Odt),
        "pdf" => Ok(anydoc::Format::Pdf),
        "ppt" => Ok(anydoc::Format::Ppt),
        "pptx" => Ok(anydoc::Format::Pptx),
        "rtf" => Ok(anydoc::Format::Rtf),
        "epub" => Ok(anydoc::Format::Epub),
        "xlsx" => Ok(anydoc::Format::Excel),
        "ods" => Ok(anydoc::Format::Ods),
        "odp" => Ok(anydoc::Format::Odp),
        "csv" => Ok(anydoc::Format::Csv),
        _ => Err(BridgeFailure::new(
            super::INVALID_INPUT_CODE,
            "format_utf8 must name a canonical AnyDoc format",
        )),
    }
}
