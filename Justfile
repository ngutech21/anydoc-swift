set shell := ["bash", "-euo", "pipefail", "-c"]

root := justfile_directory()
crate := root + "/Rust/anydoc-swift-bridge"
target := "aarch64-apple-darwin"
deployment_target := "13.0"
framework_name := "AnyDocSwiftBridge"
framework_bundle_identifier := "com.ngutech21.AnyDocSwiftBridge"
framework_version_directory := "A"
framework_link_version := "1.0.0"
framework_install_name := "@rpath/AnyDocSwiftBridge.framework/Versions/A/AnyDocSwiftBridge"
cargo_target := root + "/.build/artifact/cargo"
framework := root + "/.build/artifact/AnyDocSwiftBridge.framework"
framework_version_root := framework + "/Versions/" + framework_version_directory
framework_binary := framework_version_root + "/" + framework_name
xcframework := root + "/.build/artifact/" + framework_name + ".xcframework"
artifact_archive := root + "/.build/artifacts/AnyDocSwiftBridge.xcframework.zip"
artifact_library := cargo_target + "/" + target + "/release/libanydoc_swift_bridge.a"
native_static_libs_log := root + "/.build/artifact/native-static-libs.log"
framework_info_plist := root + "/Native/framework/Info.plist"
framework_modulemap := root + "/Native/framework/module.modulemap"
framework_exports := root + "/Native/framework/exported_symbols.txt"
verify_root := root + "/.build/artifact/verified"
verified_xcframework := verify_root + "/AnyDocSwiftBridge.xcframework"
verified_slice := verified_xcframework + "/macos-arm64"
verified_framework := verified_slice + "/" + framework_name + ".framework"
verified_framework_version_root := verified_framework + "/Versions/" + framework_version_directory
verified_framework_binary := verified_framework_version_root + "/" + framework_name
verified_headers := verified_framework_version_root + "/Headers"
verified_modules := verified_framework_version_root + "/Modules"
verified_resources := verified_framework_version_root + "/Resources"
composition_probe_library := verify_root + "/librust_staticlib_probe.a"
swift_scratch := root + "/.build/swift"
xcode_scratch := root + "/.build/xcode-package-smoke"

default:
    @just --list

# Check Rust formatting and lints with the pinned dependency graph.
lint-rust:
    cd "{{ crate }}" && cargo fmt --check
    rustfmt --check "{{ root }}/Tests/ArtifactSmoke/rust_staticlib_probe.rs"
    cd "{{ crate }}" && cargo clippy --locked --all-targets -- -D warnings

# Build the Rust bridge package on the host platform.
build-rust:
    cd "{{ crate }}" && cargo build --locked --all-targets

# Run the Rust bridge package tests.
test-rust:
    cd "{{ crate }}" && cargo test --locked

# Run every Rust check used by continuous integration.
ci-rust: lint-rust build-rust test-rust

# Check Swift formatting without modifying sources.
lint-swift:
    xcrun swift format lint --strict --recursive Package.swift Sources Tests

# Build and package the release XCFramework with the standard Cargo and Xcode tools.
build-artifact:
    test "$(uname -m)" = "arm64"
    rustc --version | grep -F "rustc 1.88.0 "
    mkdir -p "{{ cargo_target }}" "$(dirname "{{ artifact_archive }}")"
    rm -rf "{{ framework }}" "{{ xcframework }}" "{{ artifact_archive }}" "{{ native_static_libs_log }}"
    cd "{{ crate }}" && MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} CARGO_TARGET_DIR="{{ cargo_target }}" cargo build --release --locked --target {{ target }}
    cd "{{ crate }}" && MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} CARGO_TARGET_DIR="{{ cargo_target }}" cargo rustc --release --locked --target {{ target }} -- --print=native-static-libs 2>&1 | tee "{{ native_static_libs_log }}"
    test -f "{{ artifact_library }}"
    test -f "{{ framework_info_plist }}" && test -f "{{ framework_modulemap }}" && test -f "{{ framework_exports }}"
    mkdir -p "{{ framework_version_root }}/Headers" "{{ framework_version_root }}/Modules" "{{ framework_version_root }}/Resources"
    cp "{{ root }}/Native/include/anydoc_swift_bridge.h" "{{ framework_version_root }}/Headers/anydoc_swift_bridge.h"
    cp "{{ framework_modulemap }}" "{{ framework_version_root }}/Modules/module.modulemap"
    cp "{{ framework_info_plist }}" "{{ framework_version_root }}/Resources/Info.plist"
    native_link_flags="$(sed -n 's/^note: native-static-libs: //p' "{{ native_static_libs_log }}" | tail -n 1)"; test -n "$native_link_flags"; read -r -a native_link_arguments <<< "$native_link_flags"; xcrun clang -dynamiclib -arch arm64 -mmacosx-version-min={{ deployment_target }} -Wl,-force_load,"{{ artifact_library }}" -Wl,-exported_symbols_list,"{{ framework_exports }}" -Wl,-install_name,"{{ framework_install_name }}" -Wl,-compatibility_version,"{{ framework_link_version }}" -Wl,-current_version,"{{ framework_link_version }}" "${native_link_arguments[@]}" -o "{{ framework_binary }}"
    ln -s "{{ framework_version_directory }}" "{{ framework }}/Versions/Current"
    ln -s "Versions/Current/{{ framework_name }}" "{{ framework }}/{{ framework_name }}"
    ln -s "Versions/Current/Headers" "{{ framework }}/Headers"
    ln -s "Versions/Current/Modules" "{{ framework }}/Modules"
    ln -s "Versions/Current/Resources" "{{ framework }}/Resources"
    codesign --force --sign - --timestamp=none --identifier "{{ framework_bundle_identifier }}" "{{ framework }}"
    xcrun xcodebuild -create-xcframework -framework "{{ framework }}" -output "{{ xcframework }}"
    COPYFILE_DISABLE=1 ditto -c -k --keepParent "{{ xcframework }}" "{{ artifact_archive }}"
    swift package compute-checksum "{{ artifact_archive }}"

# Verify an XCFramework archive and smoke-test it without Cargo on PATH.
verify-artifact archive=artifact_archive:
    rm -rf "{{ verify_root }}"
    mkdir -p "{{ verify_root }}"
    ditto -x -k "{{ archive }}" "{{ verify_root }}"
    test -f "{{ verified_xcframework }}/Info.plist"
    test "$(/usr/bin/plutil -extract AvailableLibraries raw -expect array "{{ verified_xcframework }}/Info.plist")" = "1"
    test "$(/usr/bin/plutil -extract AvailableLibraries.0.SupportedArchitectures raw -expect array "{{ verified_xcframework }}/Info.plist")" = "1"
    test "$(/usr/bin/plutil -extract AvailableLibraries.0.SupportedArchitectures.0 raw -expect string "{{ verified_xcframework }}/Info.plist")" = "arm64"
    shopt -s nullglob dotglob; slice_directories=("{{ verified_xcframework }}"/*/); test "${#slice_directories[@]}" -eq 1; test "${slice_directories[0]%/}" = "{{ verified_slice }}"
    test "$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryIdentifier' "{{ verified_xcframework }}/Info.plist")" = "macos-arm64"
    test "$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryPath' "{{ verified_xcframework }}/Info.plist")" = "{{ framework_name }}.framework"
    test "$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:SupportedPlatform' "{{ verified_xcframework }}/Info.plist")" = "macos"
    if /usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:HeadersPath' "{{ verified_xcframework }}/Info.plist" >/dev/null 2>&1; then exit 1; fi
    test -d "{{ verified_framework }}" && test -f "{{ verified_framework_binary }}"
    test -L "{{ verified_framework }}/{{ framework_name }}" && test "$(readlink "{{ verified_framework }}/{{ framework_name }}")" = "Versions/Current/{{ framework_name }}"
    test -L "{{ verified_framework }}/Headers" && test "$(readlink "{{ verified_framework }}/Headers")" = "Versions/Current/Headers"
    test -L "{{ verified_framework }}/Modules" && test "$(readlink "{{ verified_framework }}/Modules")" = "Versions/Current/Modules"
    test -L "{{ verified_framework }}/Resources" && test "$(readlink "{{ verified_framework }}/Resources")" = "Versions/Current/Resources"
    test -L "{{ verified_framework }}/Versions/Current" && test "$(readlink "{{ verified_framework }}/Versions/Current")" = "{{ framework_version_directory }}"
    test "$(xcrun lipo -archs "{{ verified_framework_binary }}")" = "arm64"
    xcrun otool -hv "{{ verified_framework_binary }}" | awk '$1 == "MH_MAGIC_64" { found = 1; if ($5 != "DYLIB") exit 1 } END { exit found ? 0 : 1 }'
    xcrun vtool -show-build "{{ verified_framework_binary }}" | awk '$1 == "platform" { found = 1; if ($2 != "MACOS") exit 1 } END { exit found ? 0 : 1 }'
    xcrun vtool -show-build "{{ verified_framework_binary }}" | awk '$1 == "minos" { found = 1; if ($2 != "{{ deployment_target }}") exit 1 } END { exit found ? 0 : 1 }'
    test "$(xcrun otool -D "{{ verified_framework_binary }}" | tail -n 1)" = "{{ framework_install_name }}"
    test "$(xcrun otool -L "{{ verified_framework_binary }}" | tail -n +2 | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "4"
    xcrun otool -L "{{ verified_framework_binary }}" | grep -F "{{ framework_install_name }} (compatibility version {{ framework_link_version }}, current version {{ framework_link_version }})"
    xcrun otool -L "{{ verified_framework_binary }}" | grep -F '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation'
    xcrun otool -L "{{ verified_framework_binary }}" | grep -F '/usr/lib/libiconv.2.dylib'
    xcrun otool -L "{{ verified_framework_binary }}" | grep -F '/usr/lib/libSystem.B.dylib'
    ! xcrun otool -l "{{ verified_framework_binary }}" | grep -F 'com.apple.macho.mergeable'
    cmp "{{ root }}/Native/include/anydoc_swift_bridge.h" "{{ verified_headers }}/anydoc_swift_bridge.h"
    cmp "{{ framework_modulemap }}" "{{ verified_modules }}/module.modulemap"
    cmp "{{ framework_info_plist }}" "{{ verified_resources }}/Info.plist"
    /usr/bin/plutil -lint "{{ verified_resources }}/Info.plist"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "{{ verified_resources }}/Info.plist")" = "{{ framework_name }}"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "{{ verified_resources }}/Info.plist")" = "{{ framework_bundle_identifier }}"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "{{ verified_resources }}/Info.plist")" = "FMWK"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "{{ verified_resources }}/Info.plist")" = "{{ framework_link_version }}"
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "{{ verified_resources }}/Info.plist")" = "{{ deployment_target }}"
    xcrun nm -gU "{{ verified_framework_binary }}" | awk '{ print $NF }' | LC_ALL=C sort > "{{ verify_root }}/actual-exported-symbols.txt"
    LC_ALL=C sort "{{ framework_exports }}" > "{{ verify_root }}/expected-exported-symbols.txt"
    cmp "{{ verify_root }}/expected-exported-symbols.txt" "{{ verify_root }}/actual-exported-symbols.txt"
    codesign --verify --deep --strict --verbose=2 "{{ verified_framework }}"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun clang "{{ root }}/Tests/ArtifactSmoke/main.c" -mmacosx-version-min={{ deployment_target }} -F "{{ verified_slice }}" -framework "{{ framework_name }}" -Wl,-rpath,"{{ verified_slice }}" -o "{{ verify_root }}/c-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/c-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swiftc "{{ root }}/Tests/ArtifactSmoke/main.swift" -module-cache-path "{{ verify_root }}/module-cache" -F "{{ verified_slice }}" -framework "{{ framework_name }}" -Xlinker -rpath -Xlinker "{{ verified_slice }}" -target arm64-apple-macosx{{ deployment_target }} -o "{{ verify_root }}/swift-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/swift-smoke"
    swift package compute-checksum "{{ archive }}"

# Prove that the dynamic bridge coexists with a second Rust static library.
verify-rust-composition: verify-artifact
    MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} rustc "{{ root }}/Tests/ArtifactSmoke/rust_staticlib_probe.rs" --crate-name rust_staticlib_probe --crate-type staticlib --edition 2024 --target {{ target }} -C panic=unwind -C opt-level=3 -o "{{ composition_probe_library }}"
    xcrun nm -gU "{{ composition_probe_library }}" 2>/dev/null | awk '$NF == "_rust_eh_personality" { found = 1 } END { exit found ? 0 : 1 }'
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun clang "{{ root }}/Tests/ArtifactSmoke/composition.c" "{{ composition_probe_library }}" -mmacosx-version-min={{ deployment_target }} -F "{{ verified_slice }}" -framework "{{ framework_name }}" -Wl,-rpath,"{{ verified_slice }}" -o "{{ verify_root }}/rust-composition-smoke"
    xcrun nm -gU "{{ verify_root }}/rust-composition-smoke" | awk '$NF == "_rust_eh_personality" { found = 1 } END { exit found ? 0 : 1 }'
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/rust-composition-smoke"

# Build the Swift package in debug and release configurations against the verified local bridge.
build-swift: artifact
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}" -c release

# Test the Swift package against the verified local bridge.
test-swift: artifact
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift test --scratch-path "{{ swift_scratch }}"

# Process the dynamic XCFramework through Xcode's Swift-package build graph.
verify-xcode-package: verify-artifact
    rm -rf "{{ xcode_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcodebuild -quiet -scheme AnyDocSwift -destination 'generic/platform=macOS' -derivedDataPath "{{ xcode_scratch }}" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
    test -d "{{ xcode_scratch }}/Build/Products/Debug/{{ framework_name }}.framework"
    test ! -e "{{ xcode_scratch }}/Build/Products/Debug/include/module.modulemap"
    codesign --verify --deep --strict --verbose=2 "{{ xcode_scratch }}/Build/Products/Debug/{{ framework_name }}.framework"

# Build, package, and verify the native release artifact.
artifact: build-artifact verify-artifact verify-rust-composition verify-xcode-package

# Run every Swift check used by continuous integration.
ci-swift: lint-swift build-swift test-swift

# Run all continuous-integration checks locally.
ci: ci-rust ci-swift
