# Rust runtime notices

These are unmodified notice files from the pinned Rust **1.94.1** toolchain,
whose compiler source revision is
[`e408947bfd200af42db322daf0fadfe7e26d3bd1`](https://github.com/rust-lang/rust/tree/e408947bfd200af42db322daf0fadfe7e26d3bd1).
They supplement the crate-graph notices generated in
[`THIRD_PARTY_NOTICES.txt`](../../THIRD_PARTY_NOTICES.txt).

| Committed file | Installed source relative to `rustc --print sysroot` | SHA-256 |
| --- | --- | --- |
| `RustStandardLibraryNotices.html` | `share/doc/rust/COPYRIGHT-library.html` | `af70aaabed1b73e872f14f9130db37e09f3f4d73a5f7c598b9173697a5d2729f` |
| `RustCompilerBuiltinsNotices.txt` | `lib/rustlib/src/rust/library/compiler-builtins/LICENSE.txt` | `ab6eec6caf0fa5775e411c7a8bc6a45c4ef2956b0980b157ab74fc5cd62a928b` |
| `RustLibmNotices.txt` | `lib/rustlib/src/rust/library/compiler-builtins/libm/LICENSE.txt` | `3823dda7cf046602f4b4e77ec8e227863dc4736037cc85bb33d9f19febe16bb7` |

The HTML file is Rust's generated standard-library copyright notice, copied
from the installed distribution. The source and generator belong to the
[pinned Rust release](https://github.com/rust-lang/rust/tree/e408947bfd200af42db322daf0fadfe7e26d3bd1/src/tools/generate-copyright).
It includes in-tree Rust notices and the dependency notices relevant to the
selected iOS standard-library features, including `cfg-if`, `libc`,
`rustc-demangle`, `hashbrown`, and `foldhash`. The upstream file also lists
dependencies for other targets; inclusion here does not mean that each one is
linked into an Apple framework.

The HTML does not contain the separate `compiler_builtins` notice. Its pinned
version is 0.1.160. The complete
[compiler-builtins license](https://github.com/rust-lang/rust/blob/e408947bfd200af42db322daf0fadfe7e26d3bd1/library/compiler-builtins/LICENSE.txt)
includes MIT, Apache 2.0, and the LLVM exception, and refers to the bundled math
code's additional
[libm notice](https://github.com/rust-lang/rust/blob/e408947bfd200af42db322daf0fadfe7e26d3bd1/library/compiler-builtins/libm/LICENSE.txt).
Both are retained alongside the HTML, including their upstream copyright
notices and terms.

Keep these files byte-for-byte intact. Committing them makes notice packaging
independent of network access or optional installed documentation. Copy all
three into every Apple framework slice before signing, and verify those copies
after packaging. Recheck their provenance, hashes, and coverage when changing
the Rust toolchain or selected standard-library features.
