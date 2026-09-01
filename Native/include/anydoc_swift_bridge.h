#ifndef ANYDOC_SWIFT_BRIDGE_H
#define ANYDOC_SWIFT_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct anydoc_swift_result anydoc_swift_result_t;

uint32_t anydoc_swift_abi_version(void);

const uint8_t *anydoc_swift_engine_version(
    size_t *out_length
);

anydoc_swift_result_t *anydoc_swift_convert_markdown(
    const uint8_t *bytes,
    size_t bytes_length,
    const uint8_t *extension_utf8,
    size_t extension_length,
    uint64_t maximum_input_bytes,
    uint64_t maximum_output_bytes
);

int32_t anydoc_swift_result_is_success(
    const anydoc_swift_result_t *result
);

const uint8_t *anydoc_swift_result_markdown(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

const uint8_t *anydoc_swift_result_error_code(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

const uint8_t *anydoc_swift_result_error_message(
    const anydoc_swift_result_t *result,
    size_t *out_length
);

/*
 * Borrows the sorted, unique, one-based pages for a needsOcr failure and
 * reports the document's total page count. Both output pointers are required.
 * The returned array remains valid only until the result is freed. Non-OCR
 * results return NULL and set both outputs to zero.
 */
const uint32_t *anydoc_swift_result_needs_ocr_pages(
    const anydoc_swift_result_t *result,
    size_t *out_length,
    uint32_t *out_page_count
);

void anydoc_swift_result_free(
    anydoc_swift_result_t *result
);

#ifdef __cplusplus
}
#endif

#endif
