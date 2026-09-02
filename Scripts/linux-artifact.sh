#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$root/Rust/anydoc-swift-bridge"
framework_name="AnyDocSwiftBridge"
artifact_version="${ANYDOC_SWIFT_ARTIFACT_VERSION:-0.2.0}"
if [[ ! "$artifact_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "artifact version must be MAJOR.MINOR.PATCH without a leading v" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    detected_target="x86_64-unknown-linux-gnu"
    expected_llvm_arch="x86_64"
    expected_llvm_format="elf64-x86-64"
    ;;
  aarch64 | arm64)
    detected_target="aarch64-unknown-linux-gnu"
    expected_llvm_arch="aarch64"
    expected_llvm_format="elf64-littleaarch64"
    ;;
  *)
    echo "unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

target="${ANYDOC_SWIFT_LINUX_TARGET:-$detected_target}"
if [[ "$target" != "$detected_target" ]]; then
  echo "native cross-compilation is unsupported: host is $detected_target, requested $target" >&2
  exit 1
fi

build_root="$root/.build/linux/$target"
cargo_target="$root/.build/artifact/cargo-$target"
raw_library="$cargo_target/$target/release/libanydoc_swift_bridge.a"
bundle_parent="$root/.build/artifact/linux-$target"
bundle="$bundle_parent/$framework_name.artifactbundle"
variant="$bundle/$target"
archive="$root/.build/artifacts/$framework_name-$target.artifactbundle.zip"
verify_root="$root/.build/artifact/verified"
verified_bundle="$verify_root/$framework_name.artifactbundle"
verified_variant="$verified_bundle/$target"
verified_library="$verified_variant/lib$framework_name.a"
verified_native_libs="$verified_variant/share/$framework_name/native-static-libs.txt"
public_symbols="$root/Native/linux/exported_symbols.txt"
native_libs_expected="$root/Native/linux/native-static-libs.txt"
native_libs_log="$build_root/native-static-libs.log"
native_libs_actual="$build_root/native-static-libs.txt"
symbol_map="$build_root/symbol-redefinitions.txt"
raw_symbols="$build_root/raw-defined-symbols.txt"
defined_symbols="$build_root/defined-symbols.txt"
undefined_symbols="$build_root/undefined-symbols.txt"
combined_object="$build_root/$framework_name.o"
namespaced_object="$build_root/$framework_name-namespaced.o"
linker_libraries_expected="$build_root/expected-swiftpm-linker-libraries.txt"
linker_libraries_actual="$build_root/actual-swiftpm-linker-libraries.txt"
project_license="$root/LICENSE"
third_party_notices="$root/THIRD_PARTY_NOTICES.txt"
modulemap="$root/Native/linux/module.modulemap"
header="$root/Native/include/anydoc_swift_bridge.h"
consumer_path="/usr/local/swift/usr/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command is unavailable: $1" >&2
    exit 1
  fi
}

configure_llvm_tools() {
  local llvm_tools
  llvm_tools="$(rustc --print sysroot)/lib/rustlib/$target/bin"
  export PATH="$llvm_tools:$PATH"
  require_command llvm-nm
  require_command llvm-objcopy
  require_command llvm-readobj
  require_command llvm-ar
  require_command rust-lld
}

assert_environment() {
  [[ "$(uname -s)" == "Linux" ]] || {
    echo "Linux artifact commands must run natively on GNU/Linux" >&2
    exit 1
  }
  [[ "$(getconf GNU_LIBC_VERSION)" == "glibc 2.26" ]] || {
    echo "Linux artifacts must be built on the glibc 2.26 baseline" >&2
    exit 1
  }
  swift --version | grep -F "Swift version 6.2.4"
  [[ "$(rustc --version)" == rustc\ 1.94.1\ * ]] || {
    echo "Rust 1.94.1 is required" >&2
    exit 1
  }
  [[ "$(rustc -vV | sed -n 's/^host: //p')" == "$target" ]] || {
    echo "the Rust host must exactly match $target" >&2
    exit 1
  }
  require_command cargo
  require_command clang
  require_command file
  require_command sha256sum
  require_command swift
  require_command unzip
  require_command zip
  configure_llvm_tools
}

write_info_json() {
  local output="$1"
  printf '%s\n' \
    '{' \
    '  "schemaVersion": "1.0",' \
    '  "artifacts": {' \
    "    \"$framework_name\": {" \
    '      "type": "staticLibrary",' \
    "      \"version\": \"$artifact_version\"," \
    '      "variants": [' \
    '        {' \
    "          \"path\": \"$target/lib$framework_name.a\"," \
    "          \"supportedTriples\": [\"$target\"]," \
    '          "staticLibraryMetadata": {' \
    "            \"headerPaths\": [\"$target/include\"]," \
    "            \"moduleMapPath\": \"$target/include/module.modulemap\"" \
    '          }' \
    '        }' \
    '      ]' \
    '    }' \
    '  }' \
    '}' > "$output"
}

list_defined_symbols() {
  local library="$1"
  local output="$2"
  llvm-nm --defined-only --extern-only --format=just-symbols "$library" 2>/dev/null \
    | sed '/:$/d; /^[[:space:]]*$/d' \
    | LC_ALL=C sort -u > "$output"
  [[ -s "$output" ]]
}

list_undefined_symbols() {
  local library="$1"
  local output="$2"
  llvm-nm --undefined-only --extern-only --format=just-symbols "$library" 2>/dev/null \
    | sed '/:$/d; /^[[:space:]]*$/d' \
    | LC_ALL=C sort -u > "$output"
}

namespace_library() {
  rust-lld -flavor gnu -r --whole-archive "$raw_library" \
    --no-whole-archive -o "$combined_object"
  list_defined_symbols "$combined_object" "$raw_symbols"
  awk '
    NR == FNR { public_symbols[$0] = 1; next }
    !($0 in public_symbols) {
      print $0 " anydoc_swift_bridge_internal_" $0
    }
  ' "$public_symbols" "$raw_symbols" > "$symbol_map"
  [[ -s "$symbol_map" ]]

  cp "$combined_object" "$namespaced_object"
  llvm-objcopy --redefine-syms="$symbol_map" "$namespaced_object"
  llvm-ar rcsD "$variant/lib$framework_name.a" "$namespaced_object"
}

verify_symbols() {
  local library="$1"
  local work="$2"
  local expected="$work/expected-public-symbols.txt"
  local actual="$work/actual-public-symbols.txt"
  local original_internal_names="$work/original-internal-symbols.txt"
  local expected_internal_names="$work/expected-internal-symbols.txt"
  local actual_internal_names="$work/actual-internal-symbols.txt"
  local leaked_references="$work/leaked-internal-references.txt"
  local packaged_symbol_map="$verified_variant/share/$framework_name/symbol-redefinitions.txt"

  mkdir -p "$work"
  list_defined_symbols "$library" "$defined_symbols"
  LC_ALL=C sort "$public_symbols" > "$expected"
  grep -v '^anydoc_swift_bridge_internal_' "$defined_symbols" > "$actual"
  cmp "$expected" "$actual"
  [[ "$(wc -l < "$actual" | tr -d ' ')" == "12" ]]
  grep -Fx 'anydoc_swift_bridge_internal_rust_eh_personality' "$defined_symbols"

  LC_ALL=C sort -c "$packaged_symbol_map"
  rm -f "$original_internal_names" "$expected_internal_names" \
    "$actual_internal_names" "$leaked_references"
  awk '
    NF != 2 || seen_original[$1]++ || seen_expected[$2]++ { exit 1 }
    $2 != "anydoc_swift_bridge_internal_" $1 { exit 1 }
    { print $1 > original; print $2 > expected }
    END { if (NR == 0) exit 1 }
  ' original="$original_internal_names" expected="$expected_internal_names" \
    "$packaged_symbol_map"
  LC_ALL=C sort -o "$original_internal_names" "$original_internal_names"
  LC_ALL=C sort -o "$expected_internal_names" "$expected_internal_names"
  grep '^anydoc_swift_bridge_internal_' "$defined_symbols" \
    > "$actual_internal_names"
  cmp "$expected_internal_names" "$actual_internal_names"
  list_undefined_symbols "$library" "$undefined_symbols"
  comm -12 "$original_internal_names" "$undefined_symbols" > "$leaked_references"
  [[ ! -s "$leaked_references" ]]
}

capture_native_libraries() {
  local flags
  local -a libraries
  flags="$(sed -n 's/^note: native-static-libs: //p' "$native_libs_log" | tail -n 1)"
  [[ -n "$flags" ]]
  read -r -a libraries <<< "$flags"
  printf '%s\n' "${libraries[@]}" > "$native_libs_actual"
  cmp "$native_libs_expected" "$native_libs_actual"
}

verify_manifest_linker_settings() {
  awk '
    /^-l(c|dl|gcc_s|m|pthread)$/ { next }
    sub(/^-l/, "") && !seen[$0]++ { print }
  ' "$native_libs_expected" > "$linker_libraries_expected"
  sed -n 's/^[[:space:]]*\.linkedLibrary("\([^"]*\)",.*/\1/p' \
    "$root/Package.swift" > "$linker_libraries_actual"
  cmp "$linker_libraries_expected" "$linker_libraries_actual"
}

build_artifact() {
  assert_environment
  mkdir -p "$build_root" "$bundle_parent" "$(dirname "$archive")"
  rm -rf "$bundle" "$archive" "$native_libs_log" "$native_libs_actual" \
    "$symbol_map" "$raw_symbols" "$defined_symbols" "$undefined_symbols" \
    "$combined_object" "$namespaced_object" "$linker_libraries_expected" \
    "$linker_libraries_actual"
  mkdir -p "$variant/include" "$variant/share/$framework_name"

  (
    cd "$crate"
    CARGO_TARGET_DIR="$cargo_target" cargo rustc --release --locked --target "$target" \
      -- --print=native-static-libs 2>&1 | tee "$native_libs_log"
  )
  [[ -f "$raw_library" ]]
  capture_native_libraries
  verify_manifest_linker_settings
  namespace_library

  cp "$header" "$variant/include/anydoc_swift_bridge.h"
  cp "$modulemap" "$variant/include/module.modulemap"
  cp "$project_license" "$variant/share/$framework_name/LICENSE.txt"
  cp "$third_party_notices" "$variant/share/$framework_name/ThirdPartyNotices.txt"
  cp "$native_libs_actual" "$variant/share/$framework_name/native-static-libs.txt"
  cp "$symbol_map" "$variant/share/$framework_name/symbol-redefinitions.txt"
  write_info_json "$bundle/info.json"

  (
    cd "$bundle_parent"
    zip -X -q -r "$archive" "$framework_name.artifactbundle"
  )
  sha256sum "$archive"
}

unpack_archive() {
  local source_archive="$1"
  local -a top_level_entries
  [[ -f "$source_archive" ]]
  rm -rf "$verify_root"
  mkdir -p "$verify_root"
  unzip -q "$source_archive" -d "$verify_root"
  mapfile -t top_level_entries < <(
    find "$verify_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort
  )
  [[ "${#top_level_entries[@]}" == "1" ]]
  [[ "${top_level_entries[0]}" == "$verified_bundle" ]]
  [[ -d "$verified_bundle" ]]
}

verify_metadata_and_contents() {
  local source_archive="$1"
  local expected_info="$build_root/expected-info.json"
  local expected_contents="$build_root/expected-bundle-contents.txt"
  local actual_contents="$build_root/actual-bundle-contents.txt"
  local resources="$verified_variant/share/$framework_name"
  local architectures
  local formats

  printf '%s\n' \
    'info.json' \
    "$target" \
    "$target/include" \
    "$target/include/anydoc_swift_bridge.h" \
    "$target/include/module.modulemap" \
    "$target/lib$framework_name.a" \
    "$target/share" \
    "$target/share/$framework_name" \
    "$target/share/$framework_name/LICENSE.txt" \
    "$target/share/$framework_name/ThirdPartyNotices.txt" \
    "$target/share/$framework_name/native-static-libs.txt" \
    "$target/share/$framework_name/symbol-redefinitions.txt" \
    | LC_ALL=C sort > "$expected_contents"
  find "$verified_bundle" -mindepth 1 -print \
    | sed "s|^$verified_bundle/||" \
    | LC_ALL=C sort > "$actual_contents"
  cmp "$expected_contents" "$actual_contents"
  write_info_json "$expected_info"
  cmp "$expected_info" "$verified_bundle/info.json"
  cmp "$header" "$verified_variant/include/anydoc_swift_bridge.h"
  cmp "$modulemap" "$verified_variant/include/module.modulemap"
  cmp "$project_license" "$resources/LICENSE.txt"
  cmp "$third_party_notices" "$resources/ThirdPartyNotices.txt"
  cmp "$native_libs_expected" "$verified_native_libs"
  verify_manifest_linker_settings
  [[ -s "$resources/symbol-redefinitions.txt" ]]

  file "$verified_library" | grep -F 'current ar archive'
  architectures="$(llvm-readobj --file-headers "$verified_library" \
    | sed -n 's/^Arch: //p' \
    | LC_ALL=C sort -u)"
  formats="$(llvm-readobj --file-headers "$verified_library" \
    | sed -n 's/^Format: //p' \
    | LC_ALL=C sort -u)"
  [[ "$architectures" == "$expected_llvm_arch" ]]
  [[ "$formats" == "$expected_llvm_format" ]]
  verify_symbols "$verified_library" "$build_root/verified-symbols"
  sha256sum "$source_archive"
}

audit_artifact() {
  local source_archive="$1"
  local audit_clang="/usr/bin/clang"

  if [[ "$target" == "x86_64-unknown-linux-gnu" ]]; then
    local audit_tools="$build_root/audit-tools"
    local audit_libraries="$build_root/audit-libraries"
    local escaped_audit_libraries

    # SwiftPM 6.2.4 selects the first `libm.a` from Clang's search paths and
    # passes it directly to llvm-objdump. In the pinned x86_64 Amazon Linux 2
    # image that path is a GNU ld script, while the referenced glibc archive is
    # an ELF archive. Give only the auditor an earlier, inspectable candidate.
    grep -Fq 'GNU ld script' /usr/lib64/libm.a
    [[ -f /usr/lib64/libm-2.26.a ]]
    rm -rf "$audit_tools" "$audit_libraries"
    mkdir -p "$audit_tools" "$audit_libraries"
    ln -s /usr/lib64/libm-2.26.a "$audit_libraries/libm.a"
    printf -v escaped_audit_libraries '%q' "$audit_libraries"
    printf '#!/usr/bin/env bash\nexec /usr/bin/clang -L%s "$@"\n' \
      "$escaped_audit_libraries" > "$audit_tools/clang"
    chmod +x "$audit_tools/clang"
    audit_clang="$audit_tools/clang"
  fi

  CC="$audit_clang" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
    swift package experimental-audit-binary-artifact "$source_archive"
}

smoke_artifact() {
  local -a link_flags
  local -a swift_link_flags=()
  if PATH="$consumer_path" command -v cargo >/dev/null 2>&1; then
    echo "Cargo must be unavailable during artifact smoke verification" >&2
    exit 1
  fi
  [[ -s "$verified_native_libs" ]] || {
    echo "artifact native-library report is missing or empty" >&2
    exit 1
  }
  if grep -Ev '^-l[A-Za-z0-9_+.-]+$' "$verified_native_libs" >/dev/null; then
    echo "artifact native-library report contains an unsupported linker argument" >&2
    exit 1
  fi
  mapfile -t link_flags < "$verified_native_libs"
  for flag in "${link_flags[@]}"; do
    swift_link_flags+=("-Xlinker" "$flag")
  done

  env PATH="$consumer_path" clang "$root/Tests/ArtifactSmoke/main-linux.c" \
    -I "$verified_variant/include" "$verified_library" "${link_flags[@]}" \
    -o "$build_root/c-smoke"
  env PATH="$consumer_path" "$build_root/c-smoke"

  env PATH="$consumer_path" swiftc "$root/Tests/ArtifactSmoke/main.swift" \
    -module-cache-path "$build_root/module-cache" \
    -I "$verified_variant/include" \
    -Xcc "-fmodule-map-file=$verified_variant/include/module.modulemap" \
    "$verified_library" "${swift_link_flags[@]}" \
    -o "$build_root/swift-smoke"
  env PATH="$consumer_path" "$build_root/swift-smoke"
}

verify_archive() {
  local source_archive="$1"
  assert_environment
  unpack_archive "$source_archive"
  verify_metadata_and_contents "$source_archive"
  audit_artifact "$source_archive"
  smoke_artifact
}

audit_archive() {
  local source_archive="$1"
  assert_environment
  unpack_archive "$source_archive"
  audit_artifact "$source_archive"
}

smoke_archive() {
  local source_archive="$1"
  assert_environment
  unpack_archive "$source_archive"
  smoke_artifact
}

lint_swift() {
  swift format lint --strict --recursive \
    "$root/Package.swift" "$root/Sources" "$root/Tests"
}

build_swift() {
  (
    if PATH="$consumer_path" command -v cargo >/dev/null 2>&1; then
      echo "Cargo must be unavailable during consumer verification" >&2
      exit 1
    fi
    cd "$root"
    env PATH="$consumer_path" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 swift build \
      --scratch-path "$root/.build/swift-$target"
    env PATH="$consumer_path" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 swift build -c release \
      --scratch-path "$root/.build/swift-$target"
  )
}

test_swift() {
  (
    if PATH="$consumer_path" command -v cargo >/dev/null 2>&1; then
      echo "Cargo must be unavailable during consumer verification" >&2
      exit 1
    fi
    cd "$root"
    env PATH="$consumer_path" ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 swift test \
      --scratch-path "$root/.build/swift-$target"
  )
}

test_rust() {
  (
    cd "$crate"
    cargo fmt --check
    cargo clippy --locked --all-targets -- -D warnings
    cargo test --locked
  )
}

composition_smoke() {
  local composition="$build_root/composition"
  local companion_bundle="$composition/Consumer/Artifacts/RustUnwindCompanion.artifactbundle"
  local companion_variant="$companion_bundle/$target"
  local companion_library="$companion_variant/libRustUnwindCompanion.a"
  local companion_symbols="$composition/companion-defined-symbols.txt"

  rm -rf "$composition"
  mkdir -p "$composition/Consumer/Sources/CompositionConsumer" \
    "$companion_variant/include"
  rustc --edition 2024 --crate-name anydoc_unwind_companion \
    --crate-type staticlib -C panic=unwind -C lto=fat -C codegen-units=1 \
    "$root/Tests/LinuxRustComposition/companion.rs" \
    -o "$companion_library"
  list_defined_symbols "$companion_library" "$companion_symbols"
  grep -Fx 'rust_eh_personality' "$companion_symbols"
  cp "$root/Tests/LinuxRustComposition/companion.h" "$companion_variant/include/companion.h"
  cp "$root/Tests/LinuxRustComposition/module.modulemap" \
    "$companion_variant/include/module.modulemap"
  cp "$root/Tests/LinuxRustComposition/Package.swift.template" \
    "$composition/Consumer/Package.swift"
  cp "$root/Tests/LinuxRustComposition/main.swift" \
    "$composition/Consumer/Sources/CompositionConsumer/main.swift"
  printf '%s\n' \
    '{' \
    '  "schemaVersion": "1.0",' \
    '  "artifacts": {' \
    '    "RustUnwindCompanion": {' \
    '      "type": "staticLibrary",' \
    '      "version": "1.0.0",' \
    '      "variants": [' \
    '        {' \
    "          \"path\": \"$target/libRustUnwindCompanion.a\"," \
    "          \"supportedTriples\": [\"$target\"]," \
    '          "staticLibraryMetadata": {' \
    "            \"headerPaths\": [\"$target/include\"]," \
    "            \"moduleMapPath\": \"$target/include/module.modulemap\"" \
    '          }' \
    '        }' \
    '      ]' \
    '    }' \
    '  }' \
    '}' > "$companion_bundle/info.json"

  (
    if PATH="$consumer_path" command -v cargo >/dev/null 2>&1; then
      echo "Cargo must be unavailable during consumer verification" >&2
      exit 1
    fi
    env PATH="$consumer_path" ANYDOC_SWIFT_PACKAGE_ROOT="$root" \
      ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
      swift run -c release \
      --package-path "$composition/Consumer" \
      --scratch-path "$composition/scratch" \
      AnyDocSwiftLinuxComposition \
      "$root/Tests/Fixtures/rtf/handmade-blockstyle.rtf"
  )
}

memory_probe() {
  if PATH="$consumer_path" command -v cargo >/dev/null 2>&1; then
    echo "Cargo must be unavailable during consumer verification" >&2
    exit 1
  fi
  env PATH="$consumer_path" ANYDOC_SWIFT_PACKAGE_ROOT="$root" \
    ANYDOC_SWIFT_USE_LOCAL_BRIDGE=1 \
    "$root/Scripts/memory-probe.sh"
}

artifact() {
  build_artifact
  verify_archive "$archive"
}

ci() {
  test_rust
  ci_swift
}

ci_swift() {
  lint_swift
  artifact
  build_swift
  "$root/Scripts/check-public-interface.sh"
  test_swift
  composition_smoke
}

usage() {
  cat >&2 <<'EOF'
usage: Scripts/linux-artifact.sh COMMAND [ARCHIVE]

commands:
  build                 build and package the native artifact
  package               build and package the native artifact
  audit [ARCHIVE]       run SwiftPM's audit on an artifact archive
  smoke [ARCHIVE]       run C and Swift artifact smoke consumers
  verify [ARCHIVE]      verify, audit, and smoke-test an archive
  artifact              build and verify the native artifact
  build-swift           build Swift debug and release with Cargo unavailable
  test-swift            run the complete Swift test suite with Cargo unavailable
  composition           run the two-Rust-static-library consumer smoke test
  memory-probe          run the non-default Release peak-RSS qualification
  ci-swift              run Swift, artifact, and composition checks
  ci                     run Rust, Swift, artifact, and composition checks
EOF
  exit 2
}

command_name="${1:-}"
case "$command_name" in
  build)
    build_artifact
    ;;
  package)
    build_artifact
    ;;
  audit)
    audit_archive "${2:-$archive}"
    ;;
  smoke)
    smoke_archive "${2:-$archive}"
    ;;
  verify)
    verify_archive "${2:-$archive}"
    ;;
  artifact)
    artifact
    ;;
  build-swift)
    assert_environment
    build_swift
    ;;
  test-swift)
    assert_environment
    test_swift
    ;;
  composition)
    assert_environment
    composition_smoke
    ;;
  memory-probe)
    assert_environment
    memory_probe
    ;;
  ci-swift)
    assert_environment
    ci_swift
    ;;
  ci)
    assert_environment
    ci
    ;;
  *)
    usage
    ;;
esac
