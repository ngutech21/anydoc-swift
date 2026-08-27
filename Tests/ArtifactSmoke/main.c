#include "anydoc_swift_bridge.h"

#include <stddef.h>
#include <stdint.h>

int main(void) {
  size_t length = 0;
  const uint8_t *version = anydoc_swift_engine_version(&length);
  if (anydoc_swift_abi_version() != 1 || version == NULL || length == 0) {
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
  anydoc_swift_result_free(result);
  return 0;
}
