pub mod pdf;
pub mod pptx;

use crate::model::{TextDoc, TextRun};

use std::collections::BTreeMap;

/// One resolved image asset handed to the exporters by the caller (the
/// Flutter side reads the resource store and passes bytes per resource id).
///
/// * `bytes` — the original encoded image (PNG/JPEG/GIF), embedded verbatim
///   into `ppt/media/*` in PPTX exports.
/// * `rgba` — decoded raw RGBA8 (`width * height * 4`), optionally
///   provided for the PDF exporter (FlateDecode XObject; JPEGs may instead
///   pass through as DCTDecode using `bytes`).
///
/// An entry present with a bad/short `rgba` falls back to a clean
/// placeholder box, exactly like a missing entry — a missing asset is
/// never a broken export.
#[derive(Debug, Clone)]
pub struct ExportImage {
    /// "png" | "jpeg" | "gif" (upper/lower variants tolerated).
    pub format: String,
    pub width: u32,
    pub height: u32,
    /// Original encoded image bytes.
    pub bytes: Vec<u8>,
    /// Raw RGBA8 pixels (`width * height * 4`), when provided.
    pub rgba: Option<Vec<u8>>,
}

/// resource id -> resolved asset (deterministic iteration order).
pub type ExportImages = BTreeMap<String, ExportImage>;


// ---------------------------------------------------------------------------
// Shared ObjectContent layout helpers (used by both exporters)
// ---------------------------------------------------------------------------

/// Slice `text` by UTF-16 code-unit offsets (the run/paragraph coordinate
/// space — the same space a Flutter TextSelection uses).
pub(crate) fn utf16_slice(text: &str, start: u32, end: u32) -> String {
    let mut out = String::new();
    let mut units = 0u32;
    for c in text.chars() {
        let len = c.len_utf16() as u32;
        if units >= end {
            break;
        }
        if units >= start {
            // A surrogate pair straddling a boundary: emit the whole char
            // only when both halves are inside the slice.
            let fully_inside = units + len <= end;
            if len == 1 || fully_inside {
                out.push(c);
            }
        }
        units += len;
    }
    out
}

/// One run piece over the doc's text, sliced by UTF-16 offsets.
pub(crate) struct RunPiece<'a> {
    pub start: u32,
    pub end: u32,
    pub run: Option<&'a TextRun>,
}

/// Split `[from, to)` of the doc's text into styled pieces, following the run
/// marks — the Rust mirror of the Flutter span builder. Uncovered gaps are
/// plain pieces (they inherit the base style).
pub(crate) fn run_pieces<'a>(doc: &'a TextDoc, from: u32, to: u32) -> Vec<RunPiece<'a>> {
    let mut out = Vec::new();
    let mut pos = from;
    for r in &doc.runs {
        if r.end <= from || r.start >= to || r.end <= r.start {
            continue; // zero-width pending marks never render
        }
        let a = r.start.max(from);
        let b = r.end.min(to);
        if a > pos {
            out.push(RunPiece { start: pos, end: a, run: None });
        }
        out.push(RunPiece { start: a, end: b, run: Some(r) });
        pos = b;
    }
    if pos < to {
        out.push(RunPiece { start: pos, end: to, run: None });
    }
    out
}

/// Paragraph boundaries in UTF-16 offsets: 0 plus every `\n` + 1.
pub(crate) fn doc_paragraphs(doc: &TextDoc) -> Vec<(u32, u32)> {
    let mut starts = vec![0u32];
    let mut utf16 = 0u32;
    for c in doc.text.chars() {
        if c == '\n' {
            starts.push(utf16 + 1);
        }
        utf16 += c.len_utf16() as u32;
    }
    starts.sort_unstable();
    starts.dedup();
    let mut bounds = Vec::new();
    for (i, &s) in starts.iter().enumerate() {
        let e = if i + 1 < starts.len() { starts[i + 1] } else { doc.text.len() as u32 };
        bounds.push((s, e));
    }
    bounds
}

/// The paragraph's own style anchor at `start` (None = defaults), matching
/// the Flutter `effectiveParaAt` semantics: paragraph styles never bleed.
pub(crate) fn para_anchor_at(doc: &TextDoc, start: u32) -> Option<&crate::model::ParaStyle> {
    doc.paras.iter().find(|p| p.start == start)
}

#[cfg(test)]
pub(crate) mod tests_support {
    /// A minimal valid PNG (1×1 white pixel) for export tests: the PNG
    /// signature + a hand-built IHDR/IDAT/IEND for a single white pixel.
    pub fn tiny_png() -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
        // IHDR: 1x1, 8-bit RGBA
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&1u32.to_be_bytes());
        ihdr.extend_from_slice(&1u32.to_be_bytes());
        ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
        push_chunk(&mut out, b"IHDR", &ihdr);
        // IDAT: filter byte 0 + one white opaque pixel
        let raw: &[u8] = &[0, 255, 255, 255, 255];
        let mut idat = Vec::new();
        let mut zw = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
        use std::io::Write as _;
        zw.write_all(raw).unwrap();
        idat.extend_from_slice(&zw.finish().unwrap());
        push_chunk(&mut out, b"IDAT", &idat);
        push_chunk(&mut out, b"IEND", &[]);
        out
    }

    fn push_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        let mut body = Vec::new();
        body.extend_from_slice(kind);
        body.extend_from_slice(data);
        out.extend_from_slice(&body);
        let crc = crc32(&body);
        out.extend_from_slice(&crc.to_be_bytes());
    }

    fn crc32(data: &[u8]) -> u32 {
        let mut crc = 0xFFFF_FFFFu32;
        for &b in data {
            crc ^= b as u32;
            for _ in 0..8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320;
                } else {
                    crc >>= 1;
                }
            }
        }
        !crc
    }
}
