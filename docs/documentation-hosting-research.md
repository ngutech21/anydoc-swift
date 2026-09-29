# Documentation authoring and hosting research

Research date: 2026-09-29. This records the original proposal. No hosting
configuration, package dependency, or release was changed during that research.

Implementation follow-up: the catalog, `.spi.yml`, and `just docs` workflow
have since been added locally. The observations and checks below describe the
original research snapshot; current authoring and build instructions live in
[CONTRIBUTING](../CONTRIBUTING.md#documentation). Hosted deployment still needs
verification after publication.

## Current repository

The checkout has Swift documentation comments, including those on
[`AnyDocConverter`](../Sources/AnyDocSwift/AnyDocConverter.swift), but no
`.docc` catalog or `.spi.yml`. [`Package.swift`](../Package.swift) declares the
`AnyDocSwift` library target, requires Swift 6.2, and consumes a checksum-pinned
native bridge. The macOS bridge is arm64-only. These are local observations;
successful documentation generation on Swift Package Index has not been tested.

## Recommended hosting setup

Swift Package Index can generate and host DocC documentation from a repository.
Its current configuration uses schema version `1` and a list of Swift target
names. The first target becomes the documentation landing module. macOS is the
default documentation platform. SPI injects the DocC plugin automatically when
it is absent, so enabling SPI hosting does not require adding a dependency to
this package. Default-branch changes can take up to 24 hours to process;
releases are processed as soon as possible.
([SPIManifest common use cases](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Documentation.docc/CommonUseCases.md))

Proposed repository-root `.spi.yml`:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [AnyDocSwift]
```

If an explicit platform is desired, `platform: macos-spm` names the SwiftPM
macOS builder; `macos` is also accepted as an alias. `macos-xcodebuild` is a
separate platform value. The minimal proposal above leaves the documented
default in place.
([SPIManifest platform parser](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Platform.swift))

After implementing and validating the catalog, the configuration must reach the
default branch or the intended release before SPI can discover it. Validate
the YAML with the [SPI manifest validator](https://swiftpackageindex.com/validate-spi-manifest),
then inspect the hosted result and documentation build log. A successful local
preview alone does not verify the hosted build. Do not rewrite existing
immutable release tags; follow the [release procedure](releasing.md) for a new
release.

## Writing and previewing

Keep API reference prose in `///` comments near public declarations. A proposed
`Sources/AnyDocSwift/AnyDocSwift.docc/` catalog can hold a module overview,
getting-started guide, and longer articles about formats, structured documents,
errors, and hosted OCR. DocC combines symbol documentation with Markdown
articles and tutorials.
([Swift-DocC overview](https://github.com/swiftlang/swift-docc))

For local command-line preview, the official `swift-docc-plugin` provides
`preview-documentation` and `generate-documentation`. Using these package
commands locally requires making the plugin available as a package dependency;
SPI's automatic injection only applies to its build service. The preview
command disables the plugin sandbox because it starts a local web server.
([Plugin README](https://github.com/swiftlang/swift-docc-plugin),
[preview documentation](https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin/previewing-documentation/))

Suggested command after adding the plugin; not run for this research:

```sh
swift package --disable-sandbox preview-documentation --target AnyDocSwift
```

GitHub Pages or another static host is an alternative when a separately managed
site is desired. The plugin supports static output with
`--transform-for-static-hosting` and a `--hosting-base-path` matching the site's
URL path. SPI can link to an independently hosted site using
`external_links.documentation` in `.spi.yml`.
([Plugin README](https://github.com/swiftlang/swift-docc-plugin),
[SPI external documentation configuration](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Documentation.docc/CommonUseCases.md))

## Verification boundary

The linked package-maintainer page could not be retrieved through the research
browser. This note uses SPI's official configuration documentation and source
instead. No package-specific hosted documentation status, exact retention of
older release documentation, or successful remote build is claimed.

Repository inspection and source research were read-only apart from this note.
`git diff --check` and a Python check for trailing whitespace and a final
newline passed. The new note was also checked with `git diff --no-index --check
/dev/null docs/documentation-hosting-research.md`; it produced no whitespace
diagnostics (exit 1 because the files differ). No DocC build, test suite,
publication, or `just final-check` was run for this explanatory research artifact.
