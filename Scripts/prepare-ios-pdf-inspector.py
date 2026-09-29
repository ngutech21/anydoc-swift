#!/usr/bin/env python3
"""Stage the reviewed iOS-only patch without changing Cargo's registry or lockfile."""

import argparse
import difflib
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile

CRATE = "pdf-inspector-1.24.0"
ARCHIVE_SHA = "e22dc125a533d212c847c8c85e4fcb7358f4384869ef76b2b8721f039b1b633a"
BEFORE_SHA = "ac91977b5dc7b73898d1a357a79629c6ffb985771d48809510fbbebb050831cf"
AFTER_SHA = "c250473e5ec7e5f7dbac07a8f3d57c5eec45c9ca94094602dac28289827abbab"
SOURCE = "src/tounicode.rs"
PATCH = Path(__file__).resolve().parents[1] / "Native/patches" / (CRATE + "-ios-cmaps.patch")


def checked(condition, message):
    if not condition:
        raise ValueError(message)


def prepare(registry_manifest, output_directory):
    crate = registry_manifest.resolve().parent
    checked(registry_manifest.name == "Cargo.toml" and crate.name == CRATE,
            "expected the registry manifest for " + CRATE)
    checked(crate.parents[1].name == "src", "expected a Cargo registry source path")
    archive = crate.parents[2] / "cache" / crate.parent.name / (CRATE + ".crate")
    archive_bytes = archive.read_bytes()
    checked(hashlib.sha256(archive_bytes).hexdigest() == ARCHIVE_SHA,
            "published crate checksum mismatch: " + str(archive))
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as package:
        for member in package.getmembers():
            path = PurePosixPath(member.name)
            checked(not path.is_absolute() and ".." not in path.parts
                    and path.parts[0] == CRATE and len(path.parts) > 1
                    and member.isfile(), "unsafe crate archive member: " + member.name)
            relative = path.relative_to(CRATE).as_posix()
            checked(relative not in files, "duplicate crate archive member: " + relative)
            files[relative] = package.extractfile(member).read()
    original = files[SOURCE]
    checked(hashlib.sha256(original).hexdigest() == BEFORE_SHA, "unexpected upstream CMap source")
    before = original.decode("utf-8")
    old = '#[cfg(not(target_arch = "wasm32"))]'
    checked(before.count(old) == 3, "expected exactly three CMap override cfg attributes")
    after = before.replace(old, '#[cfg(not(any(target_arch = "wasm32", target_os = "ios")))]')
    expected_patch = "".join(difflib.unified_diff(
        before.splitlines(keepends=True), after.splitlines(keepends=True),
        fromfile="a/" + SOURCE, tofile="b/" + SOURCE, n=0))
    patch_bytes = PATCH.read_bytes()
    checked(patch_bytes == expected_patch.encode("utf-8"), "committed patch differs from reviewed change")
    files[SOURCE] = after.encode("utf-8")
    checked(hashlib.sha256(files[SOURCE]).hexdigest() == AFTER_SHA, "patched CMap source checksum mismatch")
    output = output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / CRATE
    checked(not destination.is_symlink(), "staged crate must not be a symlink")
    existing = {p.relative_to(destination).as_posix(): p for p in destination.rglob("*") if p.is_file()}
    intact = (existing.keys() == files.keys() and
              all(not existing[name].is_symlink() and existing[name].read_bytes() == data
                  for name, data in files.items()))
    if not intact:
        with tempfile.TemporaryDirectory(prefix=".prepare-", dir=output) as temporary:
            staged = Path(temporary) / CRATE
            for name, data in files.items():
                path = staged / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            if destination.exists():
                shutil.rmtree(destination)
            staged.rename(destination)
    config = output / "cargo-config.toml"
    config.write_text("paths = [" + json.dumps(str(destination)) + "]\n", encoding="utf-8")
    provenance = {"crate": CRATE, "archive_sha256": ARCHIVE_SHA,
                  "patch_sha256": hashlib.sha256(patch_bytes).hexdigest(),
                  "source_before_sha256": BEFORE_SHA, "source_after_sha256": AFTER_SHA}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    return config


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("registry_manifest", type=Path)
    parser.add_argument("output_directory", type=Path)
    arguments = parser.parse_args()
    try:
        print(prepare(arguments.registry_manifest, arguments.output_directory))
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        parser.exit(1, str(error) + "\n")
