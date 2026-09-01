# iOS required-reason API audit

The `binary-0.1.5` release is blocked until this audit is resolved. On
2026-08-30, both final iOS arm64 framework variants imported `_stat` and
`_fstat`. Apple lists `stat` and `fstat` in
`NSPrivacyAccessedAPICategoryFileTimestamp`, so the release gate fails rather
than manufacturing a privacy-manifest reason.

The committed symbol list used by the automated comparison is
[`Native/privacy/required-reason-imports.txt`](../Native/privacy/required-reason-imports.txt).
It is derived from Apple's current
[required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
and must be reviewed against that source before a native release.

## Concrete call paths

The locked dependency graph is:

```text
anydoc-swift-bridge 0.1.0
  -> anydoc 0.2.3
    -> pdf-inspector 1.17.0
```

The product conversion path for PDFs is:

```text
engine::convert_markdown
  -> anydoc::to_markdown_bytes
    -> anydoc::formats::pdf::to_markdown
      -> pdf_inspector::process_pdf_mem
        -> pdf_inspector::tounicode::find_bcmaps_dir
          -> std::path::Path::is_dir
            -> stat
        -> pdf_inspector::tounicode::read_builtin_cmap_file
          -> std::fs::read
            -> fstat
```

`find_bcmaps_dir` checks `PDF_INSPECTOR_BCMAPS_DIR` and then a path below the
crate's compile-time `CARGO_MANIFEST_DIR`. That fallback path does not exist in
an iOS application bundle, but the metadata probe is still present in the
shipped executable.

Mach-O disassembly also attributes call sites to Rust's linked symbolization
runtime:

```text
std::backtrace_rs::symbolize::gimli::mmap -> fstat
std::sys::helpers::small_c_string::run_with_cstr_allocating -> stat
```

The bridge intentionally retains unwinding and `catch_unwind`, so removing the
panic runtime without replacing the documented panic-containment contract is
not an acceptable workaround.

## Reproduce

```sh
just build-artifact
just verify-artifact
just audit-required-reason-apis
```

The last command must fail and write the matched imports to
`.build/artifact/verified/required-reason-imports.txt`.

Acceptable resolution requires either removing the covered imports in the
pinned native implementation while preserving all conversion and panic
invariants, or selecting approved reasons that accurately describe every
runtime call path. A blank declaration, an unrelated reason, or merely hiding
the symbols is not a resolution.
