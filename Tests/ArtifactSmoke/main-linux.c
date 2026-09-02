#include "anydoc_swift_bridge.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

int main(void) {
  static const char expected_version[] =
      "AnyDoc 0.2.4 (42bf1c5ecdde9eb0d96d6bd75a9e6698cf93b14c); "
      "AnyDocSwift bridge ABI 2";

  size_t length = 0;
  const uint8_t *version = anydoc_swift_engine_version(&length);
  if (anydoc_swift_abi_version() != 2 || version == NULL ||
      length != sizeof(expected_version) - 1 ||
      memcmp(version, expected_version, length) != 0) {
    return 1;
  }

  anydoc_swift_result_t *result = anydoc_swift_convert_markdown(
      NULL, 0, NULL, 0, 1024, 1024);
  if (result == NULL) {
    return 2;
  }

  (void)anydoc_swift_result_is_success(result);
  (void)anydoc_swift_result_markdown(result, &length);
  (void)anydoc_swift_result_error_code(result, &length);
  (void)anydoc_swift_result_error_message(result, &length);
  uint32_t page_count = UINT32_MAX;
  const uint32_t *ocr_pages =
      anydoc_swift_result_needs_ocr_pages(result, &length, &page_count);
  if (ocr_pages != NULL || length != 0 || page_count != 0) {
    anydoc_swift_result_free(result);
    return 3;
  }
  anydoc_swift_result_free(result);
  return 0;
}
