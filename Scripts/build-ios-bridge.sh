#!/usr/bin/env bash

# Native producer only: keep unwinding, but exclude filesystem-backed backtraces
# and the optional external CMap directory. Consumers use the packaged binary.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <aarch64-apple-ios|aarch64-apple-ios-sim>" >&2
  exit 64
fi
target="$1"
case "$target" in
  aarch64-apple-ios|aarch64-apple-ios-sim) ;;
  *) echo "unsupported iOS target: $target" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$root/Rust/anydoc-swift-bridge"
source_root="$root/.build/artifact/ios-source"
sysroot="$(rustc --print sysroot)"
std_lock="$sysroot/lib/rustlib/src/rust/library/Cargo.lock"

# build-std is experimental. Pin both compiler and its independent std graph;
# a toolchain upgrade must intentionally requalify this producer configuration.
rustc --version | grep -E '^rustc 1\.94\.1 '
test "$(shasum -a 256 "$std_lock" | awk '{ print $1 }')" = \
  "f14fb9ee9032ecb2610578650e071d106c7c34fe990878522914d30a15abbf79"

cd "$crate"
lock_before="$(shasum -a 256 Cargo.lock | awk '{ print $1 }')"
pdf_manifest="$(cargo metadata --locked --offline --format-version 1 | jq -er '
  [.packages[] | select(.name == "pdf-inspector" and .version == "1.24.0"
    and .source == "registry+https://github.com/rust-lang/crates.io-index")]
  | if length == 1 then .[0].manifest_path else error("expected registry pdf-inspector 1.24.0") end
')"
config="$(python3 "$root/Scripts/prepare-ios-pdf-inspector.py" "$pdf_manifest" "$source_root")"

# fetch includes the std graph, which ordinary cargo fetch/license generation
# does not populate. Compilation and all runtime tests remain offline.
env RUSTC_BOOTSTRAP=1 cargo fetch --locked --target "$target" \
  --config "$config" -Zbuild-std=std,panic_unwind \
  -Zbuild-std-features=panic-unwind

# Cargo injects unused std extern crates under build-std. Relax only this lint
# for this producer invocation; normal ci-rust still denies unused dependencies.
env RUSTC_BOOTSTRAP=1 cargo rustc --release --offline --locked --target "$target" \
  --config "$config" -Zbuild-std=std,panic_unwind \
  -Zbuild-std-features=panic-unwind -- \
  -A unused-crate-dependencies --print=native-static-libs

test "$(shasum -a 256 Cargo.lock | awk '{ print $1 }')" = "$lock_before"
