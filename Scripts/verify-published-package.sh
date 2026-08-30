#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$root/.build/published-swift"
tool_path="/usr/bin:/bin:/usr/sbin:/sbin"

cd "$root"
test -z "$(env PATH="$tool_path" command -v cargo || true)"
env PATH="$tool_path" xcrun swift package reset
env PATH="$tool_path" xcrun swift build --scratch-path "$scratch"
env PATH="$tool_path" xcrun swift build --scratch-path "$scratch" -c release
env PATH="$tool_path" xcrun swift test --scratch-path "$scratch"

env ANYDOC_SWIFT_BRIDGE_MODE=published bash "$root/Scripts/verify-xcode-package.sh"
env ANYDOC_SWIFT_BRIDGE_MODE=published bash "$root/Scripts/test-ios-simulator.sh"
