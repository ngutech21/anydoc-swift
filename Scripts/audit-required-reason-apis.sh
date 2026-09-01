#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcframework="$root/.build/artifact/verified/AnyDocSwiftBridge.xcframework"
framework_name="AnyDocSwiftBridge"
policy="$root/Native/privacy/required-reason-imports.txt"
report="$root/.build/artifact/verified/required-reason-imports.txt"

device_binary="$xcframework/ios-arm64/$framework_name.framework/$framework_name"
simulator_binary="$xcframework/ios-arm64-simulator/$framework_name.framework/$framework_name"

test -f "$policy"
test -f "$device_binary"
test -f "$simulator_binary"

sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$policy" | LC_ALL=C sort -u \
  >"$report.expected"

audit_binary() {
  local name="$1"
  local binary="$2"
  xcrun nm -u "$binary" | awk '{ print $NF }' | LC_ALL=C sort -u \
    >"$report.$name.imported"
  LC_ALL=C comm -12 "$report.expected" "$report.$name.imported" \
    >"$report.$name"
}

audit_binary "ios-arm64" "$device_binary"
audit_binary "ios-arm64-simulator" "$simulator_binary"
LC_ALL=C sort -u "$report.ios-arm64" "$report.ios-arm64-simulator" >"$report"

if [[ -s "$report" ]]; then
  echo "The iOS bridge imports Apple required-reason APIs:" >&2
  for name in ios-arm64 ios-arm64-simulator; do
    if [[ -s "$report.$name" ]]; then
      echo "  $name:" >&2
      sed 's/^/    /' "$report.$name" >&2
    fi
  done
  echo >&2
  echo "Do not add a privacy manifest until each concrete call path has an approved, accurate reason." >&2
  echo "See docs/ios-required-reason-audit.md for the pinned dependency paths." >&2
  exit 1
fi
