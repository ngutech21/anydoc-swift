# Native dependency patches

`pdf-inspector-1.24.0-ios-cmaps.patch` disables only the optional
`PDF_INSPECTOR_BCMAPS_DIR` filesystem override on iOS, including the simulator.
The three changed `cfg` attributes cover its import, implementation, and caller.
The existing embedded CMaps remain available. Other targets retain upstream
behavior; this patch does not repair the separate binary CMap decoder limitation.

The source is the published
[`pdf-inspector` 1.24.0 crate](https://crates.io/crates/pdf-inspector/1.24.0),
whose archive SHA-256 is
`e22dc125a533d212c847c8c85e4fcb7358f4384869ef76b2b8721f039b1b633a`.
`Scripts/prepare-ios-pdf-inspector.py` reads that archive from Cargo's cache,
checks its checksum, validates the exact source before and after the patch,
and stages a separate copy. It never edits Cargo's shared registry sources.

The preparation script takes the registry `Cargo.toml` path reported by
`cargo metadata --locked --offline --format-version 1` and an output directory
under `.build`. It prints a generated Cargo configuration path. Pass that path
as `--config <path>` to each iOS Cargo build. Its standard Cargo `paths` override
preserves the registry lockfile and requires an unchanged dependency graph;
metadata reports the actual staged crate path. The generated `provenance.json`
records the archive, patch, and source checksums. Unchanged staging is reused;
modified staging is reconstructed from the verified archive.

The patch and preparation script are part of the reviewed native build inputs.
The registry lockfile alone does not describe the patched iOS source. Keep the
archive/version and source checksums synchronized when intentionally upgrading
or removing this patch. Existing upstream license files remain unchanged.
