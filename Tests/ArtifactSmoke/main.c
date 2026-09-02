#include <AnyDocSwiftBridge/anydoc_swift_bridge.h>

#include <stddef.h>
#include <stdint.h>

int main(void) {
  size_t length = 0;
  const uint8_t *version = anydoc_swift_engine_version(&length);
  if (anydoc_swift_abi_version() != 3 || version == NULL || length == 0) {
    return 1;
  }

  anydoc_swift_result_t *result = anydoc_swift_convert_markdown(
      NULL, 0, NULL, 0, 1024, 1024);
  if (result == NULL) {
    return 2;
  }

  if (anydoc_swift_result_kind(result) != 0) {
    anydoc_swift_result_free(result);
    return 3;
  }
  (void)anydoc_swift_result_markdown(result, &length);
  (void)anydoc_swift_result_document_manifest(result, &length);
  const uint8_t *asset_bytes = (const uint8_t *)(uintptr_t)1;
  length = SIZE_MAX;
  if (anydoc_swift_result_document_asset(result, 0, &asset_bytes, &length) != 0 ||
      asset_bytes != NULL || length != 0) {
    anydoc_swift_result_free(result);
    return 4;
  }
  (void)anydoc_swift_result_error_code(result, &length);
  (void)anydoc_swift_result_error_message(result, &length);
  uint32_t page_count = UINT32_MAX;
  const uint32_t *ocr_pages =
      anydoc_swift_result_needs_ocr_pages(result, &length, &page_count);
  if (ocr_pages != NULL || length != 0 || page_count != 0) {
    anydoc_swift_result_free(result);
    return 5;
  }
  anydoc_swift_result_free(result);

  result = anydoc_swift_convert_document(NULL, 0, NULL, 0, 1024, 1024);
  if (result == NULL || anydoc_swift_result_kind(result) != 0) {
    anydoc_swift_result_free(result);
    return 6;
  }
  anydoc_swift_result_free(result);
  return 0;
}
