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
5. downloads the uploaded asset and repeats the three-slice structure,
   signature, resource, generic-destination, physical-device linkage, and real
   iOS Simulator conversion gates; and
6. publishes and verifies the immutable release.

The binary workflow deliberately fails if either iOS slice imports an API on
the checked Apple required-reason list. Surface the concrete native call path
before adding a privacy manifest. Do not invent a reason or publish an empty
declaration merely to pass the gate. The known blocker and reproduction are in
the [iOS required-reason audit](ios-required-reason-audit.md).

Record the SwiftPM checksum reported by the release. Do not update
`Package.swift` until the published asset has passed these checks.

## 2. Update and verify the Swift package

Update the binary URL and checksum together in `Package.swift`. Keep the README,
architecture guide, contributor guidance, and current-state documentation
consistent with the release. Leave the checked-in example on the last existing
Swift tag until the new package tag has been published.

Run the complete local gate:

```sh
just final-check
```

Then verify ordinary macOS and iOS consumers against the published binary,
with Cargo absent from consumer-only steps:

```sh
just verify-published-package
```

## 3. Publish the Swift package

After the manifest and documentation changes are on `master`, run the
[Release Swift Package](../.github/workflows/release-swift.yml) workflow with
version `X.Y.Z`. The workflow:

1. runs the Rust and Swift CI suites;
2. resets SwiftPM state and builds debug and release macOS configurations
   against the published binary dependency;
3. builds generic macOS, iOS-device, and iOS-simulator destinations, final-links
   the public device consumer, and runs the complete test target on a temporary
   arm64 iPhone Simulator;
4. publishes the `X.Y.Z` GitHub release and tag; and
5. verifies that the release is published, non-prerelease, and immutable.

Only after the `X.Y.Z` tag exists, update the checked-in macOS CLI example to
that exact version and verify its resolved revision. Close the originating iOS
support issue only after this remote-package gate passes.

## Immutability

Never rewrite a published native archive. Any change to native code, bundled
licenses, notices, or framework metadata requires a new binary release and
checksum. The corresponding Swift package release must pin that new immutable
asset.
