#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <AnyDocSwiftBridge.xcframework.zip>" >&2
  exit 64
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$1"
verify_root="$root/.build/artifact/verified"
xcframework="$verify_root/AnyDocSwiftBridge.xcframework"
xcframework_info="$xcframework/Info.plist"
framework_name="AnyDocSwiftBridge"
link_version="1.0.0"
flat_install_name="@rpath/AnyDocSwiftBridge.framework/AnyDocSwiftBridge"
macos_install_name="@rpath/AnyDocSwiftBridge.framework/Versions/A/AnyDocSwiftBridge"

header="$root/Native/include/anydoc_swift_bridge.h"
modulemap="$root/Native/framework/module.modulemap"
exports="$root/Native/framework/exported_symbols.txt"
license="$root/LICENSE"
notices="$root/THIRD_PARTY_NOTICES.txt"

test -f "$archive"
rm -rf "$verify_root"
mkdir -p "$verify_root"
ditto -x -k "$archive" "$verify_root"

test -f "$xcframework_info"
test ! -e "$xcframework/_CodeSignature"

/usr/bin/plutil -convert json -o "$verify_root/xcframework.json" "$xcframework_info"
jq -e '
  .AvailableLibraries as $libraries |
  ($libraries | length) == 3 and
  ([$libraries[].LibraryIdentifier] | sort) ==
    ["ios-arm64", "ios-arm64-simulator", "macos-arm64"] and
  ([$libraries[] | select(.LibraryPath != "AnyDocSwiftBridge.framework")] | length) == 0 and
  ([$libraries[] | select(has("HeadersPath"))] | length) == 0
' "$verify_root/xcframework.json" >/dev/null

verify_library_entry() {
  local identifier="$1"
  local platform="$2"
  local variant="$3"

  jq -e \
    --arg identifier "$identifier" \
    --arg platform "$platform" \
    --arg variant "$variant" '
      .AvailableLibraries as $libraries |
      ([$libraries[] | select(.LibraryIdentifier == $identifier)] | length) == 1 and
      ($libraries[] | select(.LibraryIdentifier == $identifier) |
        .LibraryPath == "AnyDocSwiftBridge.framework" and
        .SupportedArchitectures == ["arm64"] and
        .SupportedPlatform == $platform and
        (if $variant == "" then has("SupportedPlatformVariant") | not
         else .SupportedPlatformVariant == $variant end))
    ' "$verify_root/xcframework.json" >/dev/null
}

verify_library_entry "macos-arm64" "macos" ""
verify_library_entry "ios-arm64" "ios" ""
verify_library_entry "ios-arm64-simulator" "ios" "simulator"

shopt -s nullglob dotglob
slice_directories=("$xcframework"/*/)
test "${#slice_directories[@]}" -eq 3

verify_binary() {
  local binary="$1"
  local platform="$2"
  local minimum_version="$3"
  local install_name="$4"
  local core_foundation_path="$5"
  local symbol_suffix="$6"

  test "$(xcrun lipo -archs "$binary")" = "arm64"
  xcrun otool -hv "$binary" | awk '
    $1 == "MH_MAGIC_64" { found = 1; if ($5 != "DYLIB") exit 1 }
    END { exit found ? 0 : 1 }
  '
  xcrun vtool -show-build "$binary" | awk -v expected="$platform" '
    $1 == "platform" { found = 1; if ($2 != expected) exit 1 }
    END { exit found ? 0 : 1 }
  '
  xcrun vtool -show-build "$binary" | awk -v expected="$minimum_version" '
    $1 == "minos" { found = 1; if ($2 != expected) exit 1 }
    END { exit found ? 0 : 1 }
  '
  test "$(xcrun otool -D "$binary" | tail -n 1)" = "$install_name"
  test "$(xcrun otool -L "$binary" | tail -n +2 | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "4"
  xcrun otool -L "$binary" | grep -F \
    "$install_name (compatibility version $link_version, current version $link_version)"
  xcrun otool -L "$binary" | grep -F "$core_foundation_path"
  xcrun otool -L "$binary" | grep -F '/usr/lib/libiconv.2.dylib'
  xcrun otool -L "$binary" | grep -F '/usr/lib/libSystem.B.dylib'
  if xcrun otool -l "$binary" | grep -F 'com.apple.macho.mergeable'; then
    echo "mergeable-library metadata is not allowed in $binary" >&2
    return 1
  fi

  xcrun nm -gU "$binary" | awk '{ print $NF }' | LC_ALL=C sort \
    >"$verify_root/actual-exported-symbols-$symbol_suffix.txt"
  LC_ALL=C sort "$exports" >"$verify_root/expected-exported-symbols-$symbol_suffix.txt"
  cmp \
    "$verify_root/expected-exported-symbols-$symbol_suffix.txt" \
    "$verify_root/actual-exported-symbols-$symbol_suffix.txt"
}

verify_signature() {
  local framework="$1"
  codesign --verify --deep --strict --verbose=2 "$framework"
  codesign -d --verbose=4 "$framework" 2>&1 | grep -F 'Signature=adhoc'
}

macos_slice="$xcframework/macos-arm64"
macos_framework="$macos_slice/$framework_name.framework"
macos_version_root="$macos_framework/Versions/A"
macos_binary="$macos_version_root/$framework_name"

test -L "$macos_framework/$framework_name"
test "$(readlink "$macos_framework/$framework_name")" = "Versions/Current/$framework_name"
test -L "$macos_framework/Headers"
test "$(readlink "$macos_framework/Headers")" = "Versions/Current/Headers"
test -L "$macos_framework/Modules"
test "$(readlink "$macos_framework/Modules")" = "Versions/Current/Modules"
test -L "$macos_framework/Resources"
test "$(readlink "$macos_framework/Resources")" = "Versions/Current/Resources"
test -L "$macos_framework/Versions/Current"
test "$(readlink "$macos_framework/Versions/Current")" = "A"

verify_binary \
  "$macos_binary" \
  "MACOS" \
  "13.0" \
  "$macos_install_name" \
  '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation' \
  "macos"
cmp "$header" "$macos_version_root/Headers/anydoc_swift_bridge.h"
cmp "$modulemap" "$macos_version_root/Modules/module.modulemap"
cmp "$root/Native/framework/Info.plist" "$macos_version_root/Resources/Info.plist"
cmp "$license" "$macos_version_root/Resources/LICENSE.txt"
cmp "$notices" "$macos_version_root/Resources/ThirdPartyNotices.txt"
/usr/bin/plutil -lint "$macos_version_root/Resources/Info.plist"
verify_signature "$macos_framework"

verify_flat_framework() {
  local identifier="$1"
  local platform="$2"
  local info_plist="$3"
  local supported_platform="$4"
  local symbol_suffix="$5"
  local slice="$xcframework/$identifier"
  local framework="$slice/$framework_name.framework"
  local binary="$framework/$framework_name"

  test -d "$framework"
  test -f "$binary"
  test ! -e "$framework/Versions"
  test ! -L "$framework/$framework_name"
  verify_binary \
    "$binary" \
    "$platform" \
    "15.0" \
    "$flat_install_name" \
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' \
    "$symbol_suffix"
  cmp "$header" "$framework/Headers/anydoc_swift_bridge.h"
  cmp "$modulemap" "$framework/Modules/module.modulemap"
  cmp "$info_plist" "$framework/Info.plist"
  cmp "$license" "$framework/LICENSE.txt"
  cmp "$notices" "$framework/ThirdPartyNotices.txt"
  /usr/bin/plutil -lint "$framework/Info.plist"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")" \
    = "$framework_name"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$framework/Info.plist")" \
    = "com.ngutech21.AnyDocSwiftBridge"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$framework/Info.plist")" \
    = "FMWK"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$framework/Info.plist")" \
    = "$link_version"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$framework/Info.plist")" \
    = "$supported_platform"
  test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$framework/Info.plist")" \
    = "15.0"
  verify_signature "$framework"
}

verify_flat_framework \
  "ios-arm64" \
  "IOS" \
  "$root/Native/framework/Info-iOS.plist" \
  "iPhoneOS" \
  "ios-device"
verify_flat_framework \
  "ios-arm64-simulator" \
  "IOSSIMULATOR" \
  "$root/Native/framework/Info-iOSSimulator.plist" \
  "iPhoneSimulator" \
  "ios-simulator"

cmp \
  "$xcframework/ios-arm64/$framework_name.framework/Headers/anydoc_swift_bridge.h" \
  "$xcframework/ios-arm64-simulator/$framework_name.framework/Headers/anydoc_swift_bridge.h"
cmp \
  "$xcframework/ios-arm64/$framework_name.framework/Modules/module.modulemap" \
  "$xcframework/ios-arm64-simulator/$framework_name.framework/Modules/module.modulemap"

tool_path="/usr/bin:/bin:/usr/sbin:/sbin"

env PATH="$tool_path" xcrun --sdk macosx clang \
  "$root/Tests/ArtifactSmoke/main.c" \
  -target arm64-apple-macos13.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -F "$macos_slice" \
  -framework "$framework_name" \
  -Wl,-rpath,"$macos_slice" \
  -o "$verify_root/c-smoke-macos"
env PATH="$tool_path" "$verify_root/c-smoke-macos"

env PATH="$tool_path" xcrun --sdk macosx swiftc \
  "$root/Tests/ArtifactSmoke/main.swift" \
  -module-cache-path "$verify_root/module-cache-macos" \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -F "$macos_slice" \
  -framework "$framework_name" \
  -Xlinker -rpath \
  -Xlinker "$macos_slice" \
  -o "$verify_root/swift-smoke-macos"
env PATH="$tool_path" "$verify_root/swift-smoke-macos"

compile_bridge_consumers() {
  local sdk="$1"
  local target="$2"
  local identifier="$3"
  local suffix="$4"
  local slice="$xcframework/$identifier"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  env PATH="$tool_path" xcrun --sdk "$sdk" clang \
    "$root/Tests/ArtifactSmoke/main.c" \
    -target "$target" \
    -isysroot "$sdk_path" \
    -F "$slice" \
    -framework "$framework_name" \
    -Wl,-rpath,@executable_path/Frameworks \
    -o "$verify_root/c-smoke-$suffix"

  env PATH="$tool_path" xcrun --sdk "$sdk" swiftc \
    "$root/Tests/ArtifactSmoke/main.swift" \
    -module-cache-path "$verify_root/module-cache-$suffix" \
    -target "$target" \
    -sdk "$sdk_path" \
    -F "$slice" \
    -framework "$framework_name" \
    -Xlinker -rpath \
    -Xlinker @executable_path/Frameworks \
    -o "$verify_root/swift-smoke-$suffix"
}

compile_bridge_consumers "iphoneos" "arm64-apple-ios15.0" "ios-arm64" "ios-device"
compile_bridge_consumers \
  "iphonesimulator" \
  "arm64-apple-ios15.0-simulator" \
  "ios-arm64-simulator" \
  "ios-simulator"

swift package compute-checksum "$archive"
