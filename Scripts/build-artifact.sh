#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$root/Rust/anydoc-swift-bridge"
build_root="$root/.build/artifact"
cargo_target="$build_root/cargo"
frameworks_root="$build_root/frameworks"
xcframework="$build_root/AnyDocSwiftBridge.xcframework"
archive="$root/.build/artifacts/AnyDocSwiftBridge.xcframework.zip"

framework_name="AnyDocSwiftBridge"
bundle_identifier="com.ngutech21.AnyDocSwiftBridge"
link_version="1.0.0"
flat_install_name="@rpath/AnyDocSwiftBridge.framework/AnyDocSwiftBridge"
macos_install_name="@rpath/AnyDocSwiftBridge.framework/Versions/A/AnyDocSwiftBridge"

header="$root/Native/include/anydoc_swift_bridge.h"
modulemap="$root/Native/framework/module.modulemap"
exports="$root/Native/framework/exported_symbols.txt"
license="$root/LICENSE"
notices="$root/THIRD_PARTY_NOTICES.txt"

macos_framework="$frameworks_root/macos/$framework_name.framework"
ios_framework="$frameworks_root/ios-device/$framework_name.framework"
simulator_framework="$frameworks_root/ios-simulator/$framework_name.framework"

test "$(uname -m)" = "arm64"
test -f "$header"
test -f "$modulemap"
test -f "$exports"
test -f "$license"
test -f "$notices"

rm -rf "$frameworks_root" "$xcframework" "$archive"
mkdir -p "$cargo_target" "$frameworks_root" "$(dirname "$archive")"

build_static_library() {
  local target="$1"
  local sdk="$2"
  local deployment_variable="$3"
  local minimum_version="$4"
  local log="$build_root/native-static-libs-$target.log"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  (
    cd "$crate"
    env \
      "$deployment_variable=$minimum_version" \
      SDKROOT="$sdk_path" \
      CARGO_TARGET_DIR="$cargo_target" \
      cargo rustc --release --offline --locked --target "$target" -- \
        --print=native-static-libs
  ) 2>&1 | tee "$log"

  test -f "$cargo_target/$target/release/libanydoc_swift_bridge.a"
  test -n "$(sed -n 's/^note: native-static-libs: //p' "$log" | tail -n 1)"
}

link_framework_binary() {
  local target="$1"
  local sdk="$2"
  local clang_target="$3"
  local install_name="$4"
  local output="$5"
  local library="$cargo_target/$target/release/libanydoc_swift_bridge.a"
  local log="$build_root/native-static-libs-$target.log"
  local native_link_flags
  local sdk_path
  local -a native_link_arguments

  native_link_flags="$(sed -n 's/^note: native-static-libs: //p' "$log" | tail -n 1)"
  test -n "$native_link_flags"
  read -r -a native_link_arguments <<<"$native_link_flags"
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  xcrun --sdk "$sdk" clang \
    -dynamiclib \
    -target "$clang_target" \
    -isysroot "$sdk_path" \
    -Wl,-force_load,"$library" \
    -Wl,-exported_symbols_list,"$exports" \
    -Wl,-install_name,"$install_name" \
    -Wl,-compatibility_version,"$link_version" \
    -Wl,-current_version,"$link_version" \
    "${native_link_arguments[@]}" \
    -o "$output"
}

create_macos_framework() {
  local version_root="$macos_framework/Versions/A"
  mkdir -p "$version_root/Headers" "$version_root/Modules" "$version_root/Resources"
  cp "$header" "$version_root/Headers/anydoc_swift_bridge.h"
  cp "$modulemap" "$version_root/Modules/module.modulemap"
  cp "$root/Native/framework/Info.plist" "$version_root/Resources/Info.plist"
  cp "$license" "$version_root/Resources/LICENSE.txt"
  cp "$notices" "$version_root/Resources/ThirdPartyNotices.txt"

  link_framework_binary \
    "aarch64-apple-darwin" \
    "macosx" \
    "arm64-apple-macos13.0" \
    "$macos_install_name" \
    "$version_root/$framework_name"

  ln -s A "$macos_framework/Versions/Current"
  ln -s "Versions/Current/$framework_name" "$macos_framework/$framework_name"
  ln -s Versions/Current/Headers "$macos_framework/Headers"
  ln -s Versions/Current/Modules "$macos_framework/Modules"
  ln -s Versions/Current/Resources "$macos_framework/Resources"
  codesign --force --sign - --timestamp=none --identifier "$bundle_identifier" "$macos_framework"
}

create_ios_framework() {
  local framework="$1"
  local target="$2"
  local sdk="$3"
  local clang_target="$4"
  local info_plist="$5"

  mkdir -p "$framework/Headers" "$framework/Modules"
  cp "$header" "$framework/Headers/anydoc_swift_bridge.h"
  cp "$modulemap" "$framework/Modules/module.modulemap"
  cp "$info_plist" "$framework/Info.plist"
  cp "$license" "$framework/LICENSE.txt"
  cp "$notices" "$framework/ThirdPartyNotices.txt"

  link_framework_binary "$target" "$sdk" "$clang_target" "$flat_install_name" \
    "$framework/$framework_name"
  codesign --force --sign - --timestamp=none --identifier "$bundle_identifier" "$framework"
}

build_static_library "aarch64-apple-darwin" "macosx" "MACOSX_DEPLOYMENT_TARGET" "13.0"
build_static_library "aarch64-apple-ios" "iphoneos" "IPHONEOS_DEPLOYMENT_TARGET" "15.0"
build_static_library \
  "aarch64-apple-ios-sim" "iphonesimulator" "IPHONEOS_DEPLOYMENT_TARGET" "15.0"

create_macos_framework
create_ios_framework \
  "$ios_framework" \
  "aarch64-apple-ios" \
  "iphoneos" \
  "arm64-apple-ios15.0" \
  "$root/Native/framework/Info-iOS.plist"
create_ios_framework \
  "$simulator_framework" \
  "aarch64-apple-ios-sim" \
  "iphonesimulator" \
  "arm64-apple-ios15.0-simulator" \
  "$root/Native/framework/Info-iOSSimulator.plist"

xcrun xcodebuild -create-xcframework \
  -framework "$macos_framework" \
  -framework "$ios_framework" \
  -framework "$simulator_framework" \
  -output "$xcframework"

COPYFILE_DISABLE=1 ditto -c -k --keepParent "$xcframework" "$archive"
swift package compute-checksum "$archive"
