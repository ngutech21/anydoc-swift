#!/usr/bin/env bash

# Exercise the real bridge tests with the iOS producer's unwinding-only std.
# The tests run on macOS; the packaged iOS binaries have separate import gates.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$root/Rust/anydoc-swift-bridge"
target="aarch64-apple-darwin"
test_root="$root/.build/artifact/runtime-tests"
std_arguments=("-Zbuild-std=std,panic_unwind,test" "-Zbuild-std-features=panic-unwind")

test "$(uname -s)" = "Darwin"
test "$(uname -m)" = "arm64"
cd "$crate"

# Keep this qualification on the exact std source used by build-ios-bridge.sh.
rustc --version | grep -E '^rustc 1\.94\.1 '
sysroot="$(rustc --print sysroot)"
std_lock="$sysroot/lib/rustlib/src/rust/library/Cargo.lock"
test "$(shasum -a 256 "$std_lock" | awk '{ print $1 }')" = \
  "f14fb9ee9032ecb2610578650e071d106c7c34fe990878522914d30a15abbf79"
lock_before="$(shasum -a 256 Cargo.lock | awk '{ print $1 }')"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$test_root"

# Populate the toolchain's independent std graph before compiling offline.
env RUSTC_BOOTSTRAP=1 cargo fetch --locked --target "$target" "${std_arguments[@]}"

run_tests() {
  # build-std injects unused extern crates. Relax only this invocation's lint;
  # ordinary ci-rust checks continue to deny unused crate dependencies.
  env \
    RUSTC_BOOTSTRAP=1 \
    CARGO_TARGET_DIR="$test_root" \
    CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-Aunused-crate-dependencies" \
    MACOSX_DEPLOYMENT_TARGET=13.0 \
    SDKROOT="$sdk_path" \
    RUST_BACKTRACE=full \
    cargo test --release --offline --locked --target "$target" \
      "${std_arguments[@]}" "$@"
}

# A renamed or removed panic test must not silently turn this into a green gate.
run_tests -- --list > "$test_root/test-list.txt"
grep -Fx 'tests::contains_panics_through_the_private_execution_seam: test' \
  "$test_root/test-list.txt"

# Include ignored tests so the required panic test cannot silently be skipped.
run_tests -- --include-ignored
test "$(shasum -a 256 Cargo.lock | awk '{ print $1 }')" = "$lock_before"
