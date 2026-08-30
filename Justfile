set shell := ["bash", "-euo", "pipefail", "-c"]

root := justfile_directory()
crate := root + "/Rust/anydoc-swift-bridge"
artifact_archive := root + "/.build/artifacts/AnyDocSwiftBridge.xcframework.zip"
swift_scratch := root + "/.build/swift"
cargo_about_version := "0.9.1"
license_config := crate + "/about.toml"
license_template := crate + "/third-party-notices.hbs"
license_build_root := root + "/.build/licenses"
generated_notices := license_build_root + "/THIRD_PARTY_NOTICES.txt"
license_metadata := license_build_root + "/licenses.json"
third_party_notices := root + "/THIRD_PARTY_NOTICES.txt"

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

# Generate the canonical third-party notices from the locked three-target release graph.
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

# Run every Rust check used by continuous integration.
ci-rust: lint-rust build-rust test-rust check-licenses

# Check Swift formatting without modifying sources.
lint-swift:
    xcrun swift format lint --strict --recursive Package.swift Sources Tests

# Build the macOS, iOS-device, and iOS-simulator XCFramework archive.
build-artifact: check-licenses
    bash "{{ root }}/Scripts/build-artifact.sh"

# Verify every XCFramework slice and final-link bridge consumers without Cargo on PATH.
verify-artifact archive=artifact_archive:
    bash "{{ root }}/Scripts/verify-artifact.sh" "{{ archive }}"

# Build the Swift package in debug and release configurations against the local bridge.
build-swift: build-artifact verify-artifact
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}" -c release

# Run the complete Swift test target on macOS against the local bridge.
test-swift: build-artifact verify-artifact
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift test --scratch-path "{{ swift_scratch }}"

# Process matching macOS and iOS-device slices through Xcode and final-link the public consumer.
verify-xcode-package: build-artifact verify-artifact
    bash "{{ root }}/Scripts/verify-xcode-package.sh"

# Run all public behavior tests on a temporary arm64 iPhone Simulator.
test-ios-simulator: build-artifact verify-artifact
    bash "{{ root }}/Scripts/test-ios-simulator.sh"

# Fail when an iOS binary imports an API on Apple's current required-reason list.
audit-required-reason-apis: build-artifact verify-artifact
    bash "{{ root }}/Scripts/audit-required-reason-apis.sh"

# Apply the complete processing, simulator, and privacy gates to any archive.
verify-release-artifact archive=artifact_archive:
    bash "{{ root }}/Scripts/verify-artifact.sh" "{{ archive }}"
    bash "{{ root }}/Scripts/verify-xcode-package.sh"
    bash "{{ root }}/Scripts/test-ios-simulator.sh"
    bash "{{ root }}/Scripts/audit-required-reason-apis.sh"

# Build, package, process, execute, and audit the native release artifact.
artifact: build-artifact verify-artifact verify-xcode-package test-ios-simulator audit-required-reason-apis

# Verify the checksum-pinned remote binary with Cargo unavailable.
verify-published-package:
    bash "{{ root }}/Scripts/verify-published-package.sh"

# Run every Swift check used by continuous integration.
ci-swift: lint-swift build-swift test-swift verify-xcode-package test-ios-simulator audit-required-reason-apis

# Run all continuous-integration checks locally.
ci: ci-rust ci-swift

# Run every local validation gate before submitting a change.
final-check:
    actionlint
    just ci
