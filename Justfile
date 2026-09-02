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
project_license := root + "/LICENSE"
third_party_notices := root + "/THIRD_PARTY_NOTICES.txt"
cargo_about_version := "0.9.1"
license_config := crate + "/about.toml"
license_template := crate + "/third-party-notices.hbs"
license_build_root := root + "/.build/licenses"
generated_notices := license_build_root + "/THIRD_PARTY_NOTICES.txt"
license_metadata := license_build_root + "/licenses.json"
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
xcode_product_framework := xcode_scratch + "/Build/Products/Debug/" + framework_name + ".framework"
linux_artifact_script := root + "/Scripts/linux-artifact.sh"
public_interface_script := root + "/Scripts/check-public-interface.sh"
memory_probe_script := root + "/Scripts/memory-probe.sh"
linux_build_image := "anydoc-swift-linux:local"

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

# Generate the canonical third-party notices from the locked release graph.
update-licenses:
    mkdir -p "{{ license_build_root }}"
    just _generate-licenses "{{ third_party_notices }}" "{{ license_metadata }}"

# Verify that the committed third-party notices match the locked release graph.
check-licenses:
    mkdir -p "{{ license_build_root }}"
    rm -f "{{ generated_notices }}" "{{ license_metadata }}"
    just _generate-licenses "{{ generated_notices }}" "{{ license_metadata }}"
    cmp "{{ third_party_notices }}" "{{ generated_notices }}"

[private]
_generate-licenses output metadata:
    test "$(cargo about --version)" = "cargo-about {{ cargo_about_version }}"
    cd "{{ crate }}" && cargo about generate --config "{{ license_config }}" --manifest-path Cargo.toml --locked --fail --format json --output-file "{{ metadata }}"
    test -s "{{ metadata }}"
    upstream_notices="$(jq -r '.crates[].package.manifest_path' "{{ metadata }}" | while IFS= read -r manifest; do find "$(dirname "$manifest")" -maxdepth 1 -iname 'NOTICE*' -print; done | LC_ALL=C sort -u)"; if [[ -n "$upstream_notices" ]]; then printf 'Unhandled upstream NOTICE files:\n%s\n' "$upstream_notices" >&2; exit 1; fi
    cd "{{ crate }}" && cargo about generate --config "{{ license_config }}" --manifest-path Cargo.toml --locked --fail --output-file "{{ output }}" "{{ license_template }}"
    test -s "{{ output }}"

# Check the Linux artifact implementation without executing it.
lint-shell:
    bash -n "{{ linux_artifact_script }}"
    shellcheck "{{ linux_artifact_script }}"
    bash -n "{{ public_interface_script }}"
    shellcheck "{{ public_interface_script }}"
    bash -n "{{ memory_probe_script }}"
    shellcheck "{{ memory_probe_script }}"

# Run every Rust and native-tooling check used by continuous integration.
ci-rust: lint-rust lint-shell build-rust test-rust check-licenses

# Check Swift formatting without modifying sources.
lint-swift:
    if [[ "$(uname -s)" = "Darwin" ]]; then xcrun swift format lint --strict --recursive Package.swift Sources Tests; else swift format lint --strict --recursive Package.swift Sources Tests; fi

# Build and package the release XCFramework with the standard Cargo and Xcode tools.
build-artifact-macos: check-licenses
    test "$(uname -m)" = "arm64"
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
    cp "{{ project_license }}" "{{ framework_version_root }}/Resources/LICENSE.txt"
    cp "{{ third_party_notices }}" "{{ framework_version_root }}/Resources/ThirdPartyNotices.txt"
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
verify-artifact-macos archive=artifact_archive:
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
    cmp "{{ project_license }}" "{{ verified_resources }}/LICENSE.txt"
    cmp "{{ third_party_notices }}" "{{ verified_resources }}/ThirdPartyNotices.txt"
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
    MACOSX_DEPLOYMENT_TARGET={{ deployment_target }} rustc "{{ root }}/Tests/ArtifactSmoke/rust_staticlib_probe.rs" --crate-name rust_staticlib_probe --crate-type staticlib --edition 2024 --target {{ target }} -C panic=unwind -C opt-level=3 -o "{{ composition_probe_library }}"
    llvm_nm="$(rustc --print sysroot)/lib/rustlib/{{ target }}/bin/llvm-nm"; test -x "$llvm_nm"; "$llvm_nm" --defined-only --extern-only --format=just-symbols "{{ composition_probe_library }}" 2>/dev/null | grep -Fx '_rust_eh_personality'
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun clang "{{ root }}/Tests/ArtifactSmoke/composition.c" "{{ composition_probe_library }}" -mmacosx-version-min={{ deployment_target }} -F "{{ verified_slice }}" -framework "{{ framework_name }}" -Wl,-rpath,"{{ verified_slice }}" -o "{{ verify_root }}/rust-composition-smoke"
    xcrun nm -gU "{{ verify_root }}/rust-composition-smoke" | awk '$NF == "_rust_eh_personality" { found = 1 } END { exit found ? 0 : 1 }'
    env PATH=/usr/bin:/bin:/usr/sbin:/sbin "{{ verify_root }}/rust-composition-smoke"
    swift package compute-checksum "{{ archive }}"

# Build the Swift package in debug and release configurations against the verified local bridge.
build-swift-macos: artifact-macos
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}" -c release

# Test the Swift package against the verified local bridge.
test-swift-macos: artifact-macos
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift test --scratch-path "{{ swift_scratch }}"

# Prove the generated public Swift symbol graph contains no private bridge API.
check-public-interface-macos: build-swift-macos
    "{{ public_interface_script }}"

# Run the non-default Release memory budget used to qualify native releases.
memory-probe-macos: artifact-macos
    "{{ memory_probe_script }}"

# Process the dynamic XCFramework through Xcode's Swift-package build graph.
verify-xcode-package: verify-artifact-macos
    rm -rf "{{ xcode_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcodebuild -quiet -scheme AnyDocSwift -destination 'generic/platform=macOS' -derivedDataPath "{{ xcode_scratch }}" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
    test -d "{{ xcode_product_framework }}"
    test ! -e "{{ xcode_scratch }}/Build/Products/Debug/include/module.modulemap"
    cmp "{{ project_license }}" "{{ xcode_product_framework }}/Versions/{{ framework_version_directory }}/Resources/LICENSE.txt"
    cmp "{{ third_party_notices }}" "{{ xcode_product_framework }}/Versions/{{ framework_version_directory }}/Resources/ThirdPartyNotices.txt"
    codesign --verify --deep --strict --verbose=2 "{{ xcode_product_framework }}"

# Build, package, and verify the macOS native release artifact.
artifact-macos: build-artifact-macos verify-artifact-macos verify-xcode-package

# Build the native Linux artifact for the current GNU host architecture.
build-artifact-linux:
    "{{ linux_artifact_script }}" build

# Package the native Linux bridge for the current GNU host architecture.
package-artifact-linux:
    "{{ linux_artifact_script }}" package

# Run SwiftPM's binary-artifact audit on a Linux archive.
audit-artifact-linux archive="":
    if [[ -n "{{ archive }}" ]]; then "{{ linux_artifact_script }}" audit "{{ archive }}"; else "{{ linux_artifact_script }}" audit; fi

# Run the Cargo-free C and Swift smoke consumers against a Linux archive.
smoke-artifact-linux archive="":
    if [[ -n "{{ archive }}" ]]; then "{{ linux_artifact_script }}" smoke "{{ archive }}"; else "{{ linux_artifact_script }}" smoke; fi

# Verify a Linux artifact archive, including its audit and native smoke tests.
verify-artifact-linux archive="":
    if [[ -n "{{ archive }}" ]]; then "{{ linux_artifact_script }}" verify "{{ archive }}"; else "{{ linux_artifact_script }}" verify; fi

# Build, package, audit, and verify the native Linux release artifact.
artifact-linux:
    "{{ linux_artifact_script }}" artifact

# Build Swift in debug and release modes against the packaged Linux bridge.
build-swift-linux: artifact-linux
    "{{ linux_artifact_script }}" build-swift

# Run the complete Swift test suite against the packaged Linux bridge.
test-swift-linux: artifact-linux
    "{{ linux_artifact_script }}" test-swift

# Run the non-default Release memory budget used to qualify native releases.
memory-probe-linux: artifact-linux
    "{{ linux_artifact_script }}" memory-probe

# Prove coexistence with a second unwind-enabled Rust static library.
verify-linux-coexistence: artifact-linux
    "{{ linux_artifact_script }}" composition

# Run every Linux Swift and native-artifact check used by continuous integration.
ci-swift-linux: lint-swift artifact-linux
    "{{ linux_artifact_script }}" build-swift
    "{{ linux_artifact_script }}" test-swift
    "{{ linux_artifact_script }}" composition

# Build the digest-pinned native Linux toolchain image for the current architecture.
build-linux-environment:
    test "$(uname -s)" = "Linux"; case "$(uname -m)" in x86_64) docker_arch=amd64 ;; aarch64 | arm64) docker_arch=arm64 ;; *) echo "unsupported Linux architecture: $(uname -m)" >&2; exit 1 ;; esac; docker build --platform "linux/$docker_arch" --build-arg "TARGETARCH=$docker_arch" --file "{{ root }}/Native/linux/Dockerfile" --tag "{{ linux_build_image }}" "{{ root }}"

# Build and verify Linux artifacts in the pinned glibc 2.26 environment.
artifact-linux-container: build-linux-environment
    case "$(uname -m)" in x86_64) docker_arch=amd64 ;; aarch64 | arm64) docker_arch=arm64 ;; *) exit 1 ;; esac; docker run --rm --platform "linux/$docker_arch" --env ANYDOC_SWIFT_ARTIFACT_VERSION --volume "{{ root }}:/workspace" --workdir /workspace "{{ linux_build_image }}" Scripts/linux-artifact.sh artifact

# Run Linux Swift and artifact CI in the pinned glibc 2.26 environment.
ci-swift-linux-container: build-linux-environment
    case "$(uname -m)" in x86_64) docker_arch=amd64 ;; aarch64 | arm64) docker_arch=arm64 ;; *) exit 1 ;; esac; docker run --rm --platform "linux/$docker_arch" --env ANYDOC_SWIFT_ARTIFACT_VERSION --volume "{{ root }}:/workspace" --workdir /workspace "{{ linux_build_image }}" Scripts/linux-artifact.sh ci-swift

# Select the native artifact recipe for the current host.
artifact:
    if [[ "$(uname -s)" = "Darwin" ]]; then just artifact-macos; elif [[ "$(uname -s)" = "Linux" ]]; then just artifact-linux-container; else echo "unsupported artifact host: $(uname -s)" >&2; exit 1; fi

# Select the artifact verifier for the current host.
verify-artifact archive="":
    if [[ "$(uname -s)" = "Darwin" ]]; then if [[ -n "{{ archive }}" ]]; then just verify-artifact-macos "{{ archive }}"; else just verify-artifact-macos; fi; elif [[ "$(uname -s)" = "Linux" ]]; then if [[ -n "{{ archive }}" ]]; then just verify-artifact-linux "{{ archive }}"; else just verify-artifact-linux; fi; else echo "unsupported artifact host: $(uname -s)" >&2; exit 1; fi

# Build Swift for the current host against its packaged local bridge.
build-swift:
    if [[ "$(uname -s)" = "Darwin" ]]; then just build-swift-macos; elif [[ "$(uname -s)" = "Linux" ]]; then just build-swift-linux; else echo "unsupported Swift host: $(uname -s)" >&2; exit 1; fi

# Test Swift for the current host against its packaged local bridge.
test-swift:
    if [[ "$(uname -s)" = "Darwin" ]]; then just test-swift-macos; elif [[ "$(uname -s)" = "Linux" ]]; then just test-swift-linux; else echo "unsupported Swift host: $(uname -s)" >&2; exit 1; fi

# Run the native Release memory budget for the current host.
memory-probe:
    if [[ "$(uname -s)" = "Darwin" ]]; then just memory-probe-macos; elif [[ "$(uname -s)" = "Linux" ]]; then just memory-probe-linux; else echo "unsupported memory-probe host: $(uname -s)" >&2; exit 1; fi

# Run every Swift check used by continuous integration on the current host.
ci-swift:
    if [[ "$(uname -s)" = "Darwin" ]]; then just ci-swift-macos; elif [[ "$(uname -s)" = "Linux" ]]; then just ci-swift-linux-container; else echo "unsupported Swift host: $(uname -s)" >&2; exit 1; fi

# Run every macOS Swift check used by continuous integration.
ci-swift-macos: lint-swift build-swift-macos test-swift-macos check-public-interface-macos

# Run all continuous-integration checks locally.
ci:
    just ci-rust
    just ci-swift

# Run every local validation gate before submitting a change.
final-check:
    actionlint
    git diff --check
    just ci

# Convert the rich DOCX fixture with the command-line example.
run-example:
    swift run --package-path Examples/AnyDocSwiftExample AnyDocSwiftExample Tests/Fixtures/docx/handmade-rich.docx
