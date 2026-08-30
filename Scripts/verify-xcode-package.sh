#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge_mode="${ANYDOC_SWIFT_BRIDGE_MODE:-local}"
scratch_root="$root/.build/xcode-package-smoke-$bridge_mode"
framework_name="AnyDocSwiftBridge"
license="$root/LICENSE"
notices="$root/THIRD_PARTY_NOTICES.txt"
tool_path="/usr/bin:/bin:/usr/sbin:/sbin"
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

rm -rf "$scratch_root"
mkdir -p "$scratch_root"
test -z "$(env PATH="$tool_path" command -v cargo || true)"

build_package() {
  local destination="$1"
  local derived_data="$2"

  env \
    PATH="$tool_path" \
    "${bridge_environment[@]}" \
    xcodebuild \
      -quiet \
      -scheme AnyDocSwift \
      -destination "$destination" \
      -derivedDataPath "$derived_data" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      build
}

build_package "generic/platform=macOS" "$scratch_root/macos"
build_package "generic/platform=iOS" "$scratch_root/ios-device"
build_package "generic/platform=iOS Simulator" "$scratch_root/ios-simulator"

macos_product="$scratch_root/macos/Build/Products/Debug"
device_product="$scratch_root/ios-device/Build/Products/Debug-iphoneos"
simulator_product="$scratch_root/ios-simulator/Build/Products/Debug-iphonesimulator"

macos_framework="$macos_product/$framework_name.framework"
device_framework="$device_product/$framework_name.framework"
simulator_framework="$simulator_product/$framework_name.framework"

test -d "$macos_framework"
test -d "$device_framework"
test -d "$simulator_framework"
test ! -e "$macos_product/include/module.modulemap"
test ! -e "$device_product/include/module.modulemap"
test ! -e "$simulator_product/include/module.modulemap"

cmp "$license" "$macos_framework/Versions/A/Resources/LICENSE.txt"
cmp "$notices" "$macos_framework/Versions/A/Resources/ThirdPartyNotices.txt"
cmp "$license" "$device_framework/LICENSE.txt"
cmp "$notices" "$device_framework/ThirdPartyNotices.txt"
cmp "$license" "$simulator_framework/LICENSE.txt"
cmp "$notices" "$simulator_framework/ThirdPartyNotices.txt"

test "$(xcrun lipo -archs "$macos_framework/Versions/A/$framework_name")" = "arm64"
test "$(xcrun lipo -archs "$device_framework/$framework_name")" = "arm64"
test "$(xcrun lipo -archs "$simulator_framework/$framework_name")" = "arm64"
verify_platform() {
  local binary="$1"
  local platform="$2"
  xcrun vtool -show-build "$binary" | awk -v expected="$platform" '
    $1 == "platform" { found = 1; if ($2 != expected) exit 1 }
    END { exit found ? 0 : 1 }
  '
}

verify_platform "$macos_framework/Versions/A/$framework_name" "MACOS"
verify_platform "$device_framework/$framework_name" "IOS"
verify_platform "$simulator_framework/$framework_name" "IOSSIMULATOR"

codesign --verify --deep --strict --verbose=2 "$macos_framework"
codesign --verify --deep --strict --verbose=2 "$device_framework"
codesign --verify --deep --strict --verbose=2 "$simulator_framework"

test -f "$device_product/AnyDocSwift.o"
test -d "$device_product/AnyDocSwift.swiftmodule"

env PATH="$tool_path" xcrun --sdk iphoneos swiftc \
  "$root/Tests/PublicConsumerSmoke/main.swift" \
  "$device_product/AnyDocSwift.o" \
  -parse-as-library \
  -profile-generate \
  -module-cache-path "$scratch_root/public-consumer-module-cache" \
  -target arm64-apple-ios15.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -I "$device_product" \
  -F "$device_product" \
  -framework "$framework_name" \
  -Xlinker -rpath \
  -Xlinker @executable_path/Frameworks \
  -o "$scratch_root/public-consumer-ios-device"

test "$(xcrun lipo -archs "$scratch_root/public-consumer-ios-device")" = "arm64"
verify_platform "$scratch_root/public-consumer-ios-device" "IOS"
xcrun vtool -show-build "$scratch_root/public-consumer-ios-device" | awk '
  $1 == "minos" { found = 1; if ($2 != "15.0") exit 1 }
  END { exit found ? 0 : 1 }
'
xcrun otool -L "$scratch_root/public-consumer-ios-device" | grep -F \
  '@rpath/AnyDocSwiftBridge.framework/AnyDocSwiftBridge'
