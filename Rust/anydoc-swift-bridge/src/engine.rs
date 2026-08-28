//! Safe document conversion and limit enforcement.

#![forbid(unsafe_code)]

use super::{BridgeFailure, INPUT_LIMIT_CODE, OUTPUT_LIMIT_CODE};

impl From<anydoc::ConvertError> for BridgeFailure {
    fn from(error: anydoc::ConvertError) -> Self {
        let code = error.code().to_owned();
        let message = error.to_string();
        Self { code, message }
    }
}

/// Converts validated document bytes to Markdown within the configured limits.
pub(super) fn convert_markdown(
    bytes: &[u8],
    extension: Option<&str>,
    maximum_input_bytes: u64,
    maximum_output_bytes: u64,
) -> Result<String, BridgeFailure> {
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

    let format = anydoc::Format::from_bytes(bytes)
        .or_else(|| extension.and_then(anydoc::Format::from_extension));
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
