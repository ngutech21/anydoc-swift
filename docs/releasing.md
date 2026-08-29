## Release model

AnyDocSwift uses two immutable releases:

- `binary-X.Y.Z` publishes `AnyDocSwiftBridge.xcframework.zip`.
- `X.Y.Z` publishes the Swift package manifest that pins that binary's URL and
  checksum.

The binary must be published and verified before the Swift package can point to
it. Both release workflows accept `MAJOR.MINOR.PATCH` without a leading `v`,
must run from `master`, and refuse an existing tag or release.

## 1. Publish the native binary

Run the [Release Binary](../.github/workflows/release-binary.yml) workflow with
version `X.Y.Z`. The workflow:

1. verifies that repository release immutability is enabled;
2. builds and verifies the native archive with `just artifact`;
3. creates and verifies the `binary-X.Y.Z` tag;
4. uploads the archive to a draft release;
5. downloads the uploaded asset and verifies its bytes, checksum, framework,
   license resources, exported ABI, and smoke consumers; and
6. publishes and verifies the immutable release.

Record the SwiftPM checksum reported by the release. Do not update
`Package.swift` until the published asset has passed these checks.

## 2. Update and verify the Swift package

Update the binary URL and checksum together in `Package.swift`. Keep the README,
example package, architecture guide, contributor guidance, and current-state
documentation consistent with the release.

Run the complete local gate:

```sh
just final-check
```

Then verify ordinary consumers against the published binary rather than the
locally built bridge:

```sh
xcrun swift package reset
xcrun swift build
xcrun swift build -c release
xcrun swift test
```

## 3. Publish the Swift package

After the manifest and documentation changes are on `master`, run the
[Release Swift Package](../.github/workflows/release-swift.yml) workflow with
version `X.Y.Z`. The workflow:

1. runs the Rust and Swift CI suites;
2. resets SwiftPM state and builds debug and release configurations against the
   published binary dependency;
3. runs the Swift tests against that dependency;
4. publishes the `X.Y.Z` GitHub release and tag; and
5. verifies that the release is published, non-prerelease, and immutable.

## Immutability

Never rewrite a published native archive. Any change to native code, bundled
licenses, notices, or framework metadata requires a new binary release and
checksum. The corresponding Swift package release must pin that new immutable
asset.
