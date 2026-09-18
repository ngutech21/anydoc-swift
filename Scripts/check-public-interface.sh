#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$root/.build/public-interface"
module_cache="$output/module-cache"
symbol_graphs="$output/symbol-graphs"

case "$(uname -s)" in
  Darwin)
    target="arm64-apple-macosx13.0"
    scratch="$root/.build/swift"
    swift_command=(xcrun swift)
    bridge_directory="$root/.build/artifact/verified/AnyDocSwiftBridge.xcframework/macos-arm64"
    sdk_arguments=(-sdk "$(xcrun --show-sdk-path)")
    bridge_arguments=(-F "$bridge_directory")
    extractor=(xcrun swift-symbolgraph-extract)
    ;;
  Linux)
    detected_target="$(
      swift -print-target-info \
        | sed -n 's/.*"unversionedTriple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    )"
    target="${ANYDOC_SWIFT_LINUX_TARGET:-$detected_target}"
    scratch="$root/.build/swift-$target"
    swift_command=(swift)
    bridge_directory="$root/.build/artifact/verified/AnyDocSwiftBridge.artifactbundle/$target/include"
    sdk_arguments=()
    bridge_arguments=(
      -I "$bridge_directory"
      -Xcc "-fmodule-map-file=$bridge_directory/module.modulemap"
    )
    extractor=(swift-symbolgraph-extract)
    ;;
  *)
    echo "unsupported host for interface extraction: $(uname -s)" >&2
    exit 1
    ;;
esac

[[ -d "$bridge_directory" ]] || {
  echo "verified AnyDocSwiftBridge artifact is missing" >&2
  exit 1
}

binary_directory="$(
  env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 "${swift_command[@]}" build \
    --package-path "$root" --scratch-path "$scratch" --show-bin-path
)"
# Swift 6.4's Swift Build puts modules beside products; the older native build
# system uses a Modules subdirectory. Query the active toolchain so stale output
# from a different build system is never selected.
module_directory="$binary_directory"
if [[ -e "$binary_directory/Modules/AnyDocSwift.swiftmodule" ]]; then
  module_directory="$binary_directory/Modules"
fi
[[ -e "$module_directory/AnyDocSwift.swiftmodule" ]] || {
  echo "build AnyDocSwift in debug configuration before checking its interface" >&2
  exit 1
}

rm -rf "$output"
mkdir -p "$module_cache" "$symbol_graphs"
"${extractor[@]}" \
  -module-name AnyDocSwift \
  -target "$target" \
  ${sdk_arguments[@]+"${sdk_arguments[@]}"} \
  -module-cache-path "$module_cache" \
  -I "$module_directory" \
  "${bridge_arguments[@]}" \
  -minimum-access-level public \
  -output-dir "$symbol_graphs"

graph="$symbol_graphs/AnyDocSwift.symbols.json"
[[ -s "$graph" ]]
if grep -E 'AnyDocSwiftBridge|anydoc_swift_' "$graph"; then
  echo "the public Swift interface leaks bridge implementation details" >&2
  exit 1
fi
