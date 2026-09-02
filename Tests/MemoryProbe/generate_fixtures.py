#!/usr/bin/env python3

import pathlib
import sys
import zipfile
from typing import Dict, Tuple

ASSET_BYTE_COUNT = 24 * 1024 * 1024
MANIFEST_BLOCK_COUNT = 40_000

CONTENT_TYPES = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

ROOT_RELATIONSHIPS = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

DOCUMENT_PREFIX = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>"""
DOCUMENT_SUFFIX = "</w:body></w:document>"


def write_entry(archive: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data)


def write_package(path: pathlib.Path, document: bytes, extras: Dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", allowZip64=True) as archive:
        write_entry(archive, "[Content_Types].xml", CONTENT_TYPES)
        write_entry(archive, "_rels/.rels", ROOT_RELATIONSHIPS)
        write_entry(archive, "word/document.xml", document)
        for name, data in extras.items():
            write_entry(archive, name, data)


def asset_document() -> Tuple[bytes, Dict[str, bytes]]:
    drawing = """<w:p><w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><wp:extent cx="100000" cy="100000"/><wp:docPr id="1" name="Memory asset"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:blipFill><a:blip r:embed="rId1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"""
    relationships = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/memory.png"/>
</Relationships>
"""
    png_prefix = b"\x89PNG\r\n\x1a\n"
    asset = png_prefix + (b"A" * (ASSET_BYTE_COUNT - len(png_prefix)))
    document = (DOCUMENT_PREFIX + drawing + DOCUMENT_SUFFIX).encode()
    return document, {
        "word/_rels/document.xml.rels": relationships,
        "word/media/memory.png": asset,
    }


def manifest_document() -> bytes:
    paragraphs = []
    for index in range(MANIFEST_BLOCK_COUNT):
        text = f"manifest-block-{index:05d}-" + ("x" * 96)
        paragraphs.append(f"<w:p><w:r><w:t>{text}</w:t></w:r></w:p>")
    return (DOCUMENT_PREFIX + "".join(paragraphs) + DOCUMENT_SUFFIX).encode()


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_fixtures.py OUTPUT_DIRECTORY")
    output = pathlib.Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    document, extras = asset_document()
    write_package(output / "asset-heavy.docx", document, extras)
    write_package(output / "manifest-heavy.docx", manifest_document(), {})


if __name__ == "__main__":
    main()
