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
    cd "{{ root }}/Native/licenses" && if [[ "$(uname -s)" = "Darwin" ]]; then shasum -a 256 -c SHA256SUMS; else sha256sum -c SHA256SUMS; fi
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
    if LC_ALL=C grep -Ein 'copyright.*<(year|owner|copyright holders)>' "{{ output }}"; then echo "Unresolved copyright placeholders; clarify the pinned upstream licenses in {{ license_config }}" >&2; exit 1; fi

# Check the Linux artifact implementation without executing it.
lint-shell:
    bash -n "{{ root }}/Scripts/build-ios-bridge.sh"
    shellcheck "{{ root }}/Scripts/build-ios-bridge.sh"
    bash -n "{{ root }}/Scripts/test-ios-rust-runtime.sh"
    shellcheck "{{ root }}/Scripts/test-ios-rust-runtime.sh"
    bash -n "{{ root }}/Scripts/verify-artifact.sh" "{{ root }}/Scripts/verify-xcode-package.sh" "{{ root }}/Scripts/test-ios-simulator.sh"
    shellcheck "{{ root }}/Scripts/verify-artifact.sh" "{{ root }}/Scripts/verify-xcode-package.sh" "{{ root }}/Scripts/test-ios-simulator.sh"
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

# Build the macOS, iOS-device, and iOS-simulator XCFramework on an Apple host.
build-artifact-macos: check-licenses
    bash "{{ root }}/Scripts/build-artifact.sh"

# Verify every XCFramework slice and Cargo-free consumers, including Rust coexistence.
verify-artifact-macos archive=artifact_archive:
    bash "{{ root }}/Scripts/verify-artifact.sh" "{{ archive }}"

# Build the Swift package in debug and release configurations against the verified local bridge.
build-swift-macos: build-artifact-macos verify-artifact-macos
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}"
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift build --scratch-path "{{ swift_scratch }}" -c release

# Test the Swift package against the verified local bridge.
test-swift-macos: build-artifact-macos verify-artifact-macos
    env ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 xcrun swift test --scratch-path "{{ swift_scratch }}"

# Prove the generated public Swift symbol graph contains no private bridge API.
check-public-interface-macos: build-swift-macos
    "{{ public_interface_script }}"

# Run the non-default Release memory budget used to qualify native releases.
memory-probe-macos: artifact-macos
    "{{ memory_probe_script }}"

# Process matching Apple slices through Xcode and final-link the public iOS consumer.
verify-xcode-package: build-artifact-macos verify-artifact-macos
    bash "{{ root }}/Scripts/verify-xcode-package.sh"

# Run all public behavior tests on a temporary arm64 iPhone Simulator.
test-ios-simulator: build-artifact-macos verify-artifact-macos
    bash "{{ root }}/Scripts/test-ios-simulator.sh"

# Execute panic containment and bridge regressions with the iOS std features.
test-ios-rust-runtime:
    bash "{{ root }}/Scripts/test-ios-rust-runtime.sh"

# Fail when an iOS binary imports an API on the checked required-reason list.
audit-required-reason-apis: build-artifact-macos verify-artifact-macos
    bash "{{ root }}/Scripts/audit-required-reason-apis.sh"

# Apply the complete Apple processing, simulator, and privacy gates to any archive.
verify-release-artifact archive=artifact_archive:
    bash "{{ root }}/Scripts/verify-artifact.sh" "{{ archive }}"
    bash "{{ root }}/Scripts/verify-xcode-package.sh"
    bash "{{ root }}/Scripts/test-ios-simulator.sh"
    bash "{{ root }}/Scripts/audit-required-reason-apis.sh"

# Build, package, process, execute, and audit the Apple native release artifact.
artifact-macos: build-artifact-macos verify-artifact-macos test-ios-rust-runtime verify-xcode-package test-ios-simulator audit-required-reason-apis

# Verify the checksum-pinned remote Apple binary with Cargo unavailable.
verify-published-package:
    bash "{{ root }}/Scripts/verify-published-package.sh"

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
ci-swift-macos: lint-swift build-swift-macos test-swift-macos test-ios-rust-runtime check-public-interface-macos verify-xcode-package test-ios-simulator audit-required-reason-apis

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
