#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge_mode="${ANYDOC_SWIFT_BRIDGE_MODE:-local}"
derived_data="$root/.build/xcode-ios-simulator-tests-$bridge_mode"
result_bundle="$derived_data/TestResults.xcresult"
framework_name="AnyDocSwiftBridge"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
tool_path="/usr/bin:/bin:/usr/sbin:/sbin"
udid=""
bridge_environment=()

case "$bridge_mode" in
  local)
    bridge_environment+=("ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1")
    ;;
  published)
    ;;
  *)
    echo "ANYDOC_SWIFT_BRIDGE_MODE must be local or published" >&2
    exit 64
    ;;
esac

cleanup() {
  if [[ -n "$udid" ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"
  fi
}
trap cleanup EXIT

runtime="$({
  xcrun simctl list runtimes available -j
} | jq -er '
  [
    .runtimes[]
    | select(.isAvailable == true)
    | select(.identifier | startswith("com.apple.CoreSimulator.SimRuntime.iOS-"))
  ]
  | sort_by(.version | split(".") | map(tonumber))
  | last
  | .identifier
')"

xcrun simctl list devicetypes -j | jq -e \
  --arg identifier "$device_type" \
  'any(.devicetypes[]; .identifier == $identifier)' >/dev/null

device_name="AnyDocSwift-iOS-CI-$$"
udid="$(xcrun simctl create "$device_name" "$device_type" "$runtime")"
test -n "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b

rm -rf "$derived_data"
test -z "$(env PATH="$tool_path" command -v cargo || true)"
env \
  PATH="$tool_path" \
  "${bridge_environment[@]}" \
  xcodebuild \
    -quiet \
    -scheme AnyDocSwift \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    test

xcrun xcresulttool get test-results summary --path "$result_bundle" | jq -e '
  .result == "Passed" and
  .totalTestCount > 0 and
  .passedTests == .totalTestCount and
  .failedTests == 0 and
  .skippedTests == 0
' >/dev/null

processed_framework="$derived_data/Build/Products/Debug-iphonesimulator/$framework_name.framework"
processed_binary="$processed_framework/$framework_name"
test -d "$processed_framework"
test "$(xcrun lipo -archs "$processed_binary")" = "arm64"
xcrun vtool -show-build "$processed_binary" | grep -F 'platform IOSSIMULATOR'
cmp "$root/LICENSE" "$processed_framework/LICENSE.txt"
cmp "$root/THIRD_PARTY_NOTICES.txt" "$processed_framework/ThirdPartyNotices.txt"
codesign --verify --deep --strict --verbose=2 "$processed_framework"
