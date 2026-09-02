#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$root/Tests/MemoryProbe"
scratch="$root/.build/memory-probe"
module_cache="$scratch/module-cache"
maximum_rss_bytes=$((512 * 1024 * 1024))
work="$(mktemp -d "${TMPDIR:-/tmp}/anydoc-swift-memory.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required for the memory probe" >&2
  exit 1
}

fixtures="$work/fixtures"
repeated_fixtures="$work/repeated-fixtures"
python3 "$package/generate_fixtures.py" "$fixtures"
python3 "$package/generate_fixtures.py" "$repeated_fixtures"
cmp "$fixtures/asset-heavy.docx" "$repeated_fixtures/asset-heavy.docx"
cmp "$fixtures/manifest-heavy.docx" "$repeated_fixtures/manifest-heavy.docx"
mkdir -p "$module_cache"

case "$(uname -s)" in
  Darwin)
    swift_command=(xcrun swift)
    ;;
  Linux)
    swift_command=(swift)
    ;;
  *)
    echo "unsupported host for memory probe: $(uname -s)" >&2
    exit 1
    ;;
esac

build_arguments=(
  build
  -c release
  --package-path "$package"
  --scratch-path "$scratch"
)
env ANYDOC_SWIFT_PACKAGE_ROOT="$root" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
  CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  "${swift_command[@]}" "${build_arguments[@]}"
binary_directory="$(
  env ANYDOC_SWIFT_PACKAGE_ROOT="$root" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
    CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    "${swift_command[@]}" "${build_arguments[@]}" --show-bin-path
)"
probe="$binary_directory/AnyDocSwiftMemoryProbe"
[[ -x "$probe" ]]

for profile in asset manifest; do
  fixture="$fixtures/$profile-heavy.docx"
  "$probe" "$fixture" "$profile" >/dev/null
  for run in 1 2 3; do
    echo "$profile-heavy run $run"
    python3 "$package/check_peak_rss.py" \
      "$maximum_rss_bytes" "$probe" "$fixture" "$profile"
  done
done
