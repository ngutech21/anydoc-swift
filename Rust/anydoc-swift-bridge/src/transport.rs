//! Versioned JSON transport for structured document results.

#![forbid(unsafe_code)]

use anydoc::model as source;
use serde::Serialize;

use super::{BridgeFailure, DOCUMENT_LIMIT_CODE, TRANSPORT_CODE, TRANSPORT_MESSAGE};

pub(super) const SCHEMA_VERSION: u32 = 1;

/// Bridge-owned structural bytes and separately retained asset buffers.
pub(super) struct DocumentPayload {
    pub(super) manifest: Box<[u8]>,
    pub(super) assets: Vec<Box<[u8]>>,
}

pub(super) fn encode_document(
    document: source::Document,
    maximum_document_bytes: u64,
) -> Result<DocumentPayload, BridgeFailure> {
    let source::Document {
        blocks,
        notes,
        assets,
    } = document;
    let mut metadata = Vec::with_capacity(assets.len());
    let mut retained_assets = Vec::with_capacity(assets.len());

    for (index, asset) in assets.into_iter().enumerate() {
        let source::Asset {
            id,
            media_type,
            origin_part,
            bytes,
        } = asset;
        if id.0 != index {
            return Err(transport_failure());
        }
        metadata.push(AssetMetadata {
            id: checked_u64(id.0)?,
            media_type,
            origin_part,
            byte_length: checked_u64(bytes.len())?,
        });
        retained_assets.push(bytes.into_boxed_slice());
    }

    let manifest_value = Manifest {
        schema_version: SCHEMA_VERSION,
        blocks: blocks
            .into_iter()
            .map(convert_block)
            .collect::<Result<_, _>>()?,
        notes: notes
            .into_iter()
            .map(convert_note)
            .collect::<Result<_, _>>()?,
        assets: metadata,
    };
    let manifest = serde_json::to_vec(&manifest_value).map_err(|_| transport_failure())?;
    drop(manifest_value);

    enforce_document_limit(
        checked_u64(manifest.len())?,
        retained_assets.iter().map(|asset| checked_u64(asset.len())),
        maximum_document_bytes,
    )?;

    Ok(DocumentPayload {
        manifest: manifest.into_boxed_slice(),
        assets: retained_assets,
    })
}

fn enforce_document_limit<I>(
    manifest_length: u64,
    asset_lengths: I,
    maximum_document_bytes: u64,
) -> Result<(), BridgeFailure>
where
    I: IntoIterator<Item = Result<u64, BridgeFailure>>,
{
    let mut total = manifest_length;
    for asset_length in asset_lengths {
        total = total
            .checked_add(asset_length?)
            .ok_or_else(transport_failure)?;
    }
    if total > maximum_document_bytes {
        return Err(BridgeFailure::new(
            DOCUMENT_LIMIT_CODE,
            "structured document exceeds the configured wire-result limit",
        ));
    }
    Ok(())
}

fn checked_u64(value: usize) -> Result<u64, BridgeFailure> {
    u64::try_from(value).map_err(|_| transport_failure())
}

fn transport_failure() -> BridgeFailure {
    BridgeFailure::new(TRANSPORT_CODE, TRANSPORT_MESSAGE)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: u32,
    blocks: Vec<Block>,
    notes: Vec<Note>,
    assets: Vec<AssetMetadata>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AssetMetadata {
    id: u64,
    media_type: String,
    origin_part: String,
    byte_length: u64,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
#[allow(
    clippy::enum_variant_names,
    reason = "wire tags intentionally mirror the pinned upstream Block cases"
)]
enum Block {
    Heading {
        level: u64,
        anchor: Option<String>,
        content: Vec<Inline>,
    },
    Paragraph(Vec<Inline>),
    List(List),
    Table(Table),
    BlockQuote(Vec<Block>),
    CodeBlock {
        language: Option<String>,
        text: String,
    },
    Rule,
    Math(String),
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum Inline {
    Text {
        text: String,
        style: Style,
    },
    Link {
        content: Vec<Inline>,
        target: LinkTarget,
    },
    Image {
        alt: String,
        source: ImageSource,
    },
    Anchor(String),
    NoteRef(String),
    LineBreak,
    Math(String),
    Checkbox(bool),
}

#[derive(Serialize)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "the four independent style flags are part of manifest schema version 1"
)]
struct Style {
    bold: bool,
    italic: bool,
    strike: bool,
    code: bool,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum LinkTarget {
    External(String),
    Relative(String),
    Anchor(String),
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum ImageSource {
    External(String),
    Asset(u64),
    Unavailable,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct List {
    marker: MarkerKind,
    start: u64,
    items: Vec<ListItem>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ListItem {
    blocks: Vec<Block>,
    marker_label: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
enum MarkerKind {
    Bullet,
    Decimal,
    LowerAlpha,
    UpperAlpha,
    LowerRoman,
    UpperRoman,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Table {
    grid: Vec<Vec<CellSlot>>,
    header_rows: u64,
    kind: TableKind,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
enum TableKind {
    Data,
    Layout,
}

#[derive(Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum CellSlot {
    Origin(Cell),
    Covered {
        #[serde(rename = "originRow")]
        origin_row: u64,
        #[serde(rename = "originColumn")]
        origin_column: u64,
    },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Cell {
    blocks: Vec<Block>,
    column_span: u64,
    row_span: u64,
}

#[derive(Serialize)]
struct Note {
    id: String,
    kind: NoteKind,
    blocks: Vec<Block>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
enum NoteKind {
    Footnote,
    Endnote,
}

fn convert_block(block: source::Block) -> Result<Block, BridgeFailure> {
    match block {
        source::Block::Heading {
            level,
            anchor,
            content,
        } => Ok(Block::Heading {
            level: u64::from(level),
            anchor,
            content: convert_inlines(content)?,
        }),
        source::Block::Paragraph(content) => Ok(Block::Paragraph(convert_inlines(content)?)),
        source::Block::List(list) => Ok(Block::List(convert_list(list)?)),
        source::Block::Table(table) => Ok(Block::Table(convert_table(table)?)),
        source::Block::BlockQuote(blocks) => Ok(Block::BlockQuote(convert_blocks(blocks)?)),
        source::Block::CodeBlock { lang, text } => Ok(Block::CodeBlock {
            language: lang,
            text,
        }),
        source::Block::Rule => Ok(Block::Rule),
        source::Block::Math(value) => Ok(Block::Math(value)),
    }
}

fn convert_blocks(blocks: Vec<source::Block>) -> Result<Vec<Block>, BridgeFailure> {
    blocks.into_iter().map(convert_block).collect()
}

fn convert_inline(inline: source::Inline) -> Result<Inline, BridgeFailure> {
    match inline {
        source::Inline::Text { text, style } => Ok(Inline::Text {
            text,
            style: Style {
                bold: style.bold,
                italic: style.italic,
                strike: style.strike,
                code: style.code,
            },
        }),
        source::Inline::Link { content, target } => Ok(Inline::Link {
            content: convert_inlines(content)?,
            target: convert_link_target(target),
        }),
        source::Inline::Image { alt, source } => Ok(Inline::Image {
            alt,
            source: convert_image_source(source)?,
        }),
        source::Inline::Anchor(id) => Ok(Inline::Anchor(id)),
        source::Inline::NoteRef(id) => Ok(Inline::NoteRef(id)),
        source::Inline::LineBreak => Ok(Inline::LineBreak),
        source::Inline::Math(value) => Ok(Inline::Math(value)),
        source::Inline::Checkbox(is_checked) => Ok(Inline::Checkbox(is_checked)),
    }
}

fn convert_inlines(inlines: Vec<source::Inline>) -> Result<Vec<Inline>, BridgeFailure> {
    inlines.into_iter().map(convert_inline).collect()
}

fn convert_link_target(target: source::LinkTarget) -> LinkTarget {
    match target {
        source::LinkTarget::External(value) => LinkTarget::External(value),
        source::LinkTarget::Relative(value) => LinkTarget::Relative(value),
        source::LinkTarget::Anchor(value) => LinkTarget::Anchor(value),
    }
}

fn convert_image_source(source: source::ImageSource) -> Result<ImageSource, BridgeFailure> {
    match source {
        source::ImageSource::External(value) => Ok(ImageSource::External(value)),
        source::ImageSource::Asset(id) => Ok(ImageSource::Asset(checked_u64(id.0)?)),
        source::ImageSource::Unavailable => Ok(ImageSource::Unavailable),
    }
}

fn convert_list(list: source::List) -> Result<List, BridgeFailure> {
    Ok(List {
        marker: match list.marker {
            source::MarkerKind::Bullet => MarkerKind::Bullet,
            source::MarkerKind::Decimal => MarkerKind::Decimal,
            source::MarkerKind::LowerAlpha => MarkerKind::LowerAlpha,
            source::MarkerKind::UpperAlpha => MarkerKind::UpperAlpha,
            source::MarkerKind::LowerRoman => MarkerKind::LowerRoman,
            source::MarkerKind::UpperRoman => MarkerKind::UpperRoman,
        },
        start: list.start,
        items: list
            .items
            .into_iter()
            .map(|item| {
                Ok(ListItem {
                    blocks: convert_blocks(item.blocks)?,
                    marker_label: item.marker_label,
                })
            })
            .collect::<Result<_, BridgeFailure>>()?,
    })
}

fn convert_table(table: source::Table) -> Result<Table, BridgeFailure> {
    Ok(Table {
        grid: table
            .grid
            .into_iter()
            .map(|row| row.into_iter().map(convert_cell_slot).collect())
            .collect::<Result<_, BridgeFailure>>()?,
        header_rows: checked_u64(table.header_rows)?,
        kind: match table.kind {
            source::TableKind::Data => TableKind::Data,
            source::TableKind::Layout => TableKind::Layout,
        },
    })
}

fn convert_cell_slot(slot: source::CellSlot) -> Result<CellSlot, BridgeFailure> {
    match slot {
        source::CellSlot::Origin(mut cell) => {
            // anydoc 0.2.4's GridBuilder fills gaps with Cell::default(): an
            // empty 0x0 origin representing one unoccupied grid position.
            // Canonicalize only that placeholder before enforcing the wire
            // contract's positive spans in Swift.
            if cell.blocks.is_empty() && cell.col_span == 0 && cell.row_span == 0 {
                cell.col_span = 1;
                cell.row_span = 1;
            }
            Ok(CellSlot::Origin(Cell {
                blocks: convert_blocks(cell.blocks)?,
                column_span: u64::from(cell.col_span),
                row_span: u64::from(cell.row_span),
            }))
        }
        source::CellSlot::Covered {
            origin_row,
            origin_col,
        } => Ok(CellSlot::Covered {
            origin_row: checked_u64(origin_row)?,
            origin_column: checked_u64(origin_col)?,
        }),
    }
}

fn convert_note(note: source::Note) -> Result<Note, BridgeFailure> {
    Ok(Note {
        id: note.id,
        kind: match note.kind {
            source::NoteKind::Footnote => NoteKind::Footnote,
            source::NoteKind::Endnote => NoteKind::Endnote,
        },
        blocks: convert_blocks(note.blocks)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(
        clippy::too_many_lines,
        reason = "one literal snapshot proves the complete associated-value schema"
    )]
    fn exact_schema_covers_every_associated_value_variant() {
        let styled = source::Inline::Text {
            text: "styled".to_owned(),
            style: source::Style {
                bold: true,
                italic: true,
                strike: true,
                code: true,
            },
        };
        let document = source::Document {
            blocks: vec![
                source::Block::Heading {
                    level: 7,
                    anchor: Some("heading".to_owned()),
                    content: vec![
                        styled,
                        source::Inline::Link {
                            content: vec![],
                            target: source::LinkTarget::External("https://example.com".to_owned()),
                        },
                        source::Inline::Link {
                            content: vec![],
                            target: source::LinkTarget::Relative("chapter.xml".to_owned()),
                        },
                        source::Inline::Link {
                            content: vec![],
                            target: source::LinkTarget::Anchor("inside".to_owned()),
                        },
                        source::Inline::Image {
                            alt: "remote".to_owned(),
                            source: source::ImageSource::External(
                                "https://example.com/image.png".to_owned(),
                            ),
                        },
                        source::Inline::Image {
                            alt: "embedded".to_owned(),
                            source: source::ImageSource::Asset(source::AssetId(1)),
                        },
                        source::Inline::Image {
                            alt: "missing".to_owned(),
                            source: source::ImageSource::Unavailable,
                        },
                        source::Inline::Anchor("inside".to_owned()),
                        source::Inline::NoteRef("note-1".to_owned()),
                        source::Inline::LineBreak,
                        source::Inline::Math("x+y".to_owned()),
                        source::Inline::Checkbox(true),
                    ],
                },
                source::Block::Paragraph(vec![]),
                source::Block::List(source::List {
                    marker: source::MarkerKind::Bullet,
                    start: 1,
                    items: vec![source::ListItem {
                        blocks: vec![source::Block::Rule],
                        marker_label: Some("custom".to_owned()),
                    }],
                }),
                source::Block::Table(source::Table {
                    grid: vec![vec![
                        source::CellSlot::Origin(source::Cell {
                            blocks: vec![],
                            col_span: 2,
                            row_span: 1,
                        }),
                        source::CellSlot::Covered {
                            origin_row: 0,
                            origin_col: 0,
                        },
                    ]],
                    header_rows: 1,
                    kind: source::TableKind::Data,
                }),
                source::Block::Table(source::Table {
                    grid: vec![],
                    header_rows: 0,
                    kind: source::TableKind::Layout,
                }),
                source::Block::BlockQuote(vec![source::Block::Rule]),
                source::Block::CodeBlock {
                    lang: Some("swift".to_owned()),
                    text: "let x = 1".to_owned(),
                },
                source::Block::Rule,
                source::Block::Math("x^2".to_owned()),
            ],
            notes: vec![
                source::Note {
                    id: "note-1".to_owned(),
                    kind: source::NoteKind::Footnote,
                    blocks: vec![],
                },
                source::Note {
                    id: "note-2".to_owned(),
                    kind: source::NoteKind::Endnote,
                    blocks: vec![],
                },
            ],
            assets: vec![
                source::Asset {
                    id: source::AssetId(0),
                    media_type: "application/octet-stream".to_owned(),
                    origin_part: "empty.bin".to_owned(),
                    bytes: vec![],
                },
                source::Asset {
                    id: source::AssetId(1),
                    media_type: "image/png".to_owned(),
                    origin_part: "image.png".to_owned(),
                    bytes: vec![1, 2],
                },
            ],
        };

        let payload = encode_document(document, u64::MAX).expect("document should encode");
        let manifest = String::from_utf8(payload.manifest.into_vec()).expect("manifest is UTF-8");
        assert_eq!(
            manifest,
            concat!(
                "{\"schemaVersion\":1,\"blocks\":[",
                "{\"kind\":\"heading\",\"value\":{\"level\":7,\"anchor\":\"heading\",\"content\":[",
                "{\"kind\":\"text\",\"value\":{\"text\":\"styled\",\"style\":{\"bold\":true,\"italic\":true,\"strike\":true,\"code\":true}}},",
                "{\"kind\":\"link\",\"value\":{\"content\":[],\"target\":{\"kind\":\"external\",\"value\":\"https://example.com\"}}},",
                "{\"kind\":\"link\",\"value\":{\"content\":[],\"target\":{\"kind\":\"relative\",\"value\":\"chapter.xml\"}}},",
                "{\"kind\":\"link\",\"value\":{\"content\":[],\"target\":{\"kind\":\"anchor\",\"value\":\"inside\"}}},",
                "{\"kind\":\"image\",\"value\":{\"alt\":\"remote\",\"source\":{\"kind\":\"external\",\"value\":\"https://example.com/image.png\"}}},",
                "{\"kind\":\"image\",\"value\":{\"alt\":\"embedded\",\"source\":{\"kind\":\"asset\",\"value\":1}}},",
                "{\"kind\":\"image\",\"value\":{\"alt\":\"missing\",\"source\":{\"kind\":\"unavailable\"}}},",
                "{\"kind\":\"anchor\",\"value\":\"inside\"},",
                "{\"kind\":\"noteRef\",\"value\":\"note-1\"},",
                "{\"kind\":\"lineBreak\"},",
                "{\"kind\":\"math\",\"value\":\"x+y\"},",
                "{\"kind\":\"checkbox\",\"value\":true}]}}",
                ",{\"kind\":\"paragraph\",\"value\":[]}",
                ",{\"kind\":\"list\",\"value\":{\"marker\":\"bullet\",\"start\":1,\"items\":[{\"blocks\":[{\"kind\":\"rule\"}],\"markerLabel\":\"custom\"}]}}",
                ",{\"kind\":\"table\",\"value\":{\"grid\":[[{\"kind\":\"origin\",\"value\":{\"blocks\":[],\"columnSpan\":2,\"rowSpan\":1}},{\"kind\":\"covered\",\"value\":{\"originRow\":0,\"originColumn\":0}}]],\"headerRows\":1,\"kind\":\"data\"}}",
                ",{\"kind\":\"table\",\"value\":{\"grid\":[],\"headerRows\":0,\"kind\":\"layout\"}}",
                ",{\"kind\":\"blockQuote\",\"value\":[{\"kind\":\"rule\"}]}",
                ",{\"kind\":\"codeBlock\",\"value\":{\"language\":\"swift\",\"text\":\"let x = 1\"}}",
                ",{\"kind\":\"rule\"}",
                ",{\"kind\":\"math\",\"value\":\"x^2\"}",
                "],\"notes\":[",
                "{\"id\":\"note-1\",\"kind\":\"footnote\",\"blocks\":[]},",
                "{\"id\":\"note-2\",\"kind\":\"endnote\",\"blocks\":[]}",
                "],\"assets\":[",
                "{\"id\":0,\"mediaType\":\"application/octet-stream\",\"originPart\":\"empty.bin\",\"byteLength\":0},",
                "{\"id\":1,\"mediaType\":\"image/png\",\"originPart\":\"image.png\",\"byteLength\":2}",
                "]}"
            )
        );
        assert_eq!(
            payload.assets,
            [
                Vec::<u8>::new().into_boxed_slice(),
                vec![1, 2].into_boxed_slice()
            ]
        );
    }

    #[test]
    fn only_empty_upstream_filler_cells_receive_unit_spans() {
        let document = source::Document {
            blocks: vec![source::Block::Table(source::Table {
                grid: vec![vec![
                    source::CellSlot::Origin(source::Cell::default()),
                    source::CellSlot::Origin(source::Cell {
                        blocks: vec![],
                        col_span: 0,
                        row_span: 1,
                    }),
                    source::CellSlot::Origin(source::Cell {
                        blocks: vec![],
                        col_span: 1,
                        row_span: 0,
                    }),
                    source::CellSlot::Origin(source::Cell {
                        blocks: vec![source::Block::Rule],
                        col_span: 0,
                        row_span: 0,
                    }),
                ]],
                header_rows: 0,
                kind: source::TableKind::Data,
            })],
            ..source::Document::default()
        };

        let payload = encode_document(document, u64::MAX).expect("document should encode");
        let manifest: serde_json::Value =
            serde_json::from_slice(&payload.manifest).expect("manifest should decode");
        // Other malformed spans must remain visible to Swift's validation.
        assert_eq!(
            manifest.pointer("/blocks/0/value/grid/0"),
            Some(&serde_json::json!([
                {
                    "kind": "origin",
                    "value": { "blocks": [], "columnSpan": 1, "rowSpan": 1 }
                },
                {
                    "kind": "origin",
                    "value": { "blocks": [], "columnSpan": 0, "rowSpan": 1 }
                },
                {
                    "kind": "origin",
                    "value": { "blocks": [], "columnSpan": 1, "rowSpan": 0 }
                },
                {
                    "kind": "origin",
                    "value": { "blocks": [{ "kind": "rule" }], "columnSpan": 0, "rowSpan": 0 }
                }
            ]))
        );
    }

    #[test]
    fn unit_enum_tags_are_camel_case() {
        assert_eq!(
            serde_json::to_string(&[
                MarkerKind::Bullet,
                MarkerKind::Decimal,
                MarkerKind::LowerAlpha,
                MarkerKind::UpperAlpha,
                MarkerKind::LowerRoman,
                MarkerKind::UpperRoman,
            ])
            .expect("markers should serialize"),
            "[\"bullet\",\"decimal\",\"lowerAlpha\",\"upperAlpha\",\"lowerRoman\",\"upperRoman\"]"
        );
    }

    #[test]
    fn cumulative_length_overflow_is_a_transport_failure() {
        let error =
            enforce_document_limit(u64::MAX, [Ok(1)], u64::MAX).expect_err("overflow must fail");
        assert_eq!(error.code, TRANSPORT_CODE);
        assert_eq!(error.message, TRANSPORT_MESSAGE);
    }

    #[test]
    fn document_limit_counts_the_manifest_and_asset_buffers_exactly() {
        fn document() -> source::Document {
            source::Document {
                blocks: vec![],
                notes: vec![],
                assets: vec![source::Asset {
                    id: source::AssetId(0),
                    media_type: "application/octet-stream".to_owned(),
                    origin_part: "asset.bin".to_owned(),
                    bytes: vec![1, 2, 3],
                }],
            }
        }

        let unlimited = encode_document(document(), u64::MAX).expect("document should encode");
        let exact_limit = checked_u64(unlimited.manifest.len())
            .expect("manifest length should fit")
            .checked_add(3)
            .expect("test total should fit");

        assert!(encode_document(document(), exact_limit).is_ok());
        let error = encode_document(document(), exact_limit - 1)
            .err()
            .expect("one byte below the cumulative size must fail");
        assert_eq!(error.code, DOCUMENT_LIMIT_CODE);
    }
}
