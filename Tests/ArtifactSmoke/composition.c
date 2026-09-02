#include <AnyDocSwiftBridge/anydoc_swift_bridge.h>

#include <stdint.h>

int32_t rust_staticlib_probe(int32_t value);

int main(void) {
  if (anydoc_swift_abi_version() != 2) {
    return 1;
  }
  if (rust_staticlib_probe(7) != 8) {
    return 2;
  }
  return 0;
}
