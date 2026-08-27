set shell := ["bash", "-euo", "pipefail", "-c"]

root := justfile_directory()
crate := root + "/Rust/anydoc-swift-bridge"
target := "aarch64-apple-darwin"
deployment_target := "13.0"
cargo_target := root + "/.build/artifact/cargo"
xcframework := root + "/.build/artifact/AnyDocSwiftBridge.xcframework"
artifact_archive := root + "/.build/artifacts/AnyDocSwiftBridge.xcframework.zip"
artifact_library := cargo_target + "/" + target + "/release/libanydoc_swift_bridge.a"
verify_root := root + "/.build/artifact/verified"
verified_xcframework := verify_root + "/AnyDocSwiftBridge.xcframework"
verified_slice := verified_xcframework + "/macos-arm64"
verified_library := verified_slice + "/libanydoc_swift_bridge.a"
verified_headers := verified_slice + "/Headers"
swift_scratch := root + "/.build/swift"

default:
    @just --list

# Check Rust formatting and lints with the pinned dependency graph.
lint-rust:
    cd "{{ crate }}" && cargo fmt --check
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
    rm -rf "{{ xcframework }}" "{{ artifact_archive }}"
    cd "{{ crate }}" && MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} CARGO_TARGET_DIR="{{ cargo_target }}" cargo build --release --locked --target {{ target }}
    cd "{{ crate }}" && MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} CARGO_TARGET_DIR="{{ cargo_target }}" cargo rustc --release --locked --target {{ target }} -- --print=native-static-libs
    test -f "{{ artifact_library }}"
    xcrun xcodebuild -create-xcframework -library "{{ artifact_library }}" -headers "{{ root }}/Native/include" -output "{{ xcframework }}"
    COPYFILE_DISABLE=1 ditto -c -k --keepParent "{{ xcframework }}" "{{ artifact_archive }}"
    swift package compute-checksum "{{ artifact_archive }}"

# Verify an XCFramework archive and smoke-test it without Cargo on PATH.
verify-artifact archive=artifact_archive:
    rm -rf "{{ verify_root }}"
    mkdir -p "{{ verify_root }}"
    ditto -x -k "{{ archive }}" "{{ verify_root }}"
    test -f "{{ verified_xcframework }}/Info.plist"
    test -f "{{ verified_library }}"
    test "$(xcrun lipo -archs "{{ verified_library }}")" = "arm64"
    test "$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryIdentifier' "{{ verified_xcframework }}/Info.plist")" = "macos-arm64"
    test "$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:SupportedPlatform' "{{ verified_xcframework }}/Info.plist")" = "macos"
    cmp "{{ root }}/Native/include/anydoc_swift_bridge.h" "{{ verified_headers }}/anydoc_swift_bridge.h"
    cmp "{{ root }}/Native/include/module.modulemap" "{{ verified_headers }}/module.modulemap"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun clang "{{ root }}/Tests/ArtifactSmoke/main.c" -mmacosx-version-min={{ deployment_target }} -I "{{ verified_headers }}" "{{ verified_library }}" -framework CoreFoundation -liconv -o "{{ verify_root }}/c-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/c-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swiftc "{{ root }}/Tests/ArtifactSmoke/main.swift" -module-cache-path "{{ verify_root }}/module-cache" -I "{{ verified_headers }}" "{{ verified_library }}" -framework CoreFoundation -liconv -target arm64-apple-macosx{{ deployment_target }} -o "{{ verify_root }}/swift-smoke"
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/swift-smoke"
    swift package compute-checksum "{{ archive }}"

# Build, package, and verify the native release artifact.
artifact: build-artifact verify-artifact

# Build the Swift package in debug and release configurations against the verified local bridge.
build-swift: artifact
    xcrun swift build --scratch-path "{{ swift_scratch }}" -Xswiftc -I -Xswiftc "{{ verified_headers }}" -Xlinker "{{ verified_library }}" -Xlinker -framework -Xlinker CoreFoundation -Xlinker -liconv
    xcrun swift build --scratch-path "{{ swift_scratch }}" -c release -Xswiftc -I -Xswiftc "{{ verified_headers }}" -Xlinker "{{ verified_library }}" -Xlinker -framework -Xlinker CoreFoundation -Xlinker -liconv

# Test the Swift package against the verified local bridge.
test-swift: artifact
    xcrun swift test --scratch-path "{{ swift_scratch }}" -Xswiftc -I -Xswiftc "{{ verified_headers }}" -Xlinker "{{ verified_library }}" -Xlinker -framework -Xlinker CoreFoundation -Xlinker -liconv

# Run every Swift check used by continuous integration.
ci-swift: lint-swift build-swift test-swift

# Run all continuous-integration checks locally.
ci: ci-rust ci-swift
