//! Minimal PDF 1.4 writer. v0.1 is Latin-first: text maps to base-14 fonts
//! (Helvetica/Times) in WinAnsi; non-Latin-1 chars are transliterated or
//! dropped (M2 ships embedded subset fonts + full Unicode).

use crate::layout::{layout_slide, Element};
use crate::model::{Deck, SLIDE_H, SLIDE_W};

/// Slightly oversize page for crispness in viewers; everything in points.
const PW: f64 = 960.0;
const PH: f64 = 540.0;
const KX: f64 = PW / SLIDE_W;
const KY: f64 = PH / SLIDE_H;

/// Map a char to a WinAnsi-representable equivalent. Returns '?' when hopeless.
fn latinize(c: char) -> char {
    let u = c as u32;
    if u < 256 {
        return u as u8 as char;
    }
    match c {
        '’' | '‘' | '‛' => '\'',
        '“' | '”' | '„' => '"',
        '–' | '—' | '―' => '-',
        '…' => '.',
        '•' | '·' => '-',
        '×' => 'x',
        '→' | '⇒' => '>',
        '←' => '<',
        '€' => 'E',
        '™' => 'T',
        '©' => 'c',
        '®' => 'R',
        '°' => 'o',
        '½' => '1',
        '¼' => '1',
        '¾' => '3',
        _ => '?',
    }
}

fn pdf_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '(' => out.push_str("\\("),
            ')' => out.push_str("\\)"),
            '\\' => out.push_str("\\\\"),
            _ => {
                let l = latinize(c);
                if (l as u8) >= 32 {
                    out.push(l);
                }
            }
        }
    }
    out
}

fn font_name(serif: bool, bold: bool) -> &'static str {
    match (serif, bold) {
        (true, true) => "/F3",
        (true, false) => "/F2",
        (false, true) => "/F1b",
        (false, false) => "/F1",
    }
}

/// Fill color op.
fn set_fill(c: &str) -> String {
    let v = u32::from_str_radix(c.trim_start_matches('#'), 16).unwrap_or(0);
    let (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    format!("{:.3} {:.3} {:.3} rg", r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0)
}

/// Render deck to PDF bytes.
pub fn to_pdf(deck: &Deck) -> Vec<u8> {
    let mut pages_content: Vec<String> = Vec::new();

    for slide in &deck.slides {
        let layout = layout_slide(&deck.dna, slide);
        let mut ops = String::new();

        for el in &layout.elements {
            match el {
                Element::Rect { x, y, w, h, color, .. } => {
                    let (x, w) = (*x * KX, *w * KX);
                    let (y, h) = (*y * KY, *h * KY);
                    let top = PH - y - h; // PDF origin is bottom-left
                    ops.push_str(&set_fill(color));
                    ops.push_str(&format!("\n{:.2} {:.2} {:.2} {:.2} re f", x, top, w, h));
                }
                Element::Text { x, y, size, color, font, bold, lines, .. } => {
                    let serif = matches!(font, crate::dna::FontRole::Serif);
                    let size = size * KX; // uniform scale keeps proportions
                    let fname = font_name(serif, *bold);
                    let line_h = size * 1.28;
                    ops.push_str(&set_fill(color));
                    ops.push('\n');
                    for (i, line) in lines.iter().enumerate() {
                        let ly = PH - (*y * KY) - line_h * (i as f64 + 0.92);
                        ops.push_str(&format!(
                            "BT {} {:.2} Tf {:.2} {:.2} Td ({}) Tj ET\n",
                            fname,
                            size,
                            *x * KX,
                            ly,
                            pdf_escape(line)
                        ));
                    }
                }
            }
        }
        pages_content.push(ops);
    }

    // ---- assemble objects -------------------------------------------------
    let mut objs: Vec<String> = Vec::new(); // object bodies, index+1 = obj num

    // reserve: 1 = catalog, 2 = pages tree, fonts come after.
    objs.push(String::new()); // obj 1 Catalog (filled below)
    objs.push(String::new()); // obj 2 Pages (filled below)

    // Font objects 3..=6
    let font_defs = [
        ("/F1", "Helvetica"),
        ("/F1b", "Helvetica-Bold"),
        ("/F2", "Times-Roman"),
        ("/F3", "Times-Bold"),
    ];
    let mut font_refs = String::new();
    for (tag, base) in font_defs.iter() {
        let num = objs.len() + 1;
        objs.push(format!("<< /Type /Font /Subtype /Type1 /BaseFont /{} >>", base));
        font_refs.push_str(&format!("{} {} 0 R ", tag, num));
    }
    let resources = format!("<< /Font << {font_refs} >> >>");

    let mut kids = String::new();
    let mut page_objs: Vec<u32> = Vec::new();
    for content in &pages_content {
        let page_num = objs.len() + 1;
        let content_num = page_num + 1;
        objs.push(format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PW} {PH}] /Resources {} /Contents {content_num} 0 R >>",
            resources
        ));
        objs.push(format!("<< /Length {} >>\nstream\n{}\nendstream", content.len(), content));
        kids.push_str(&format!(" {} 0 R", page_num));
        page_objs.push(page_num);
    }

    objs[0] = "<< /Type /Catalog /Pages 2 0 R >>".to_string();
    objs[1] = format!("<< /Type /Pages /Kids [{kids}] /Count {} >>", pages_content.len());

    // ---- serialize --------------------------------------------------------
    let mut out = String::from("%PDF-1.4\n");
    let mut offsets = Vec::with_capacity(objs.len());
    for (i, body) in objs.iter().enumerate() {
        offsets.push(out.len());
        out.push_str(&format!("{} 0 obj\n{}\nendobj\n", i + 1, body));
    }
    let xref_pos = out.len();
    out.push_str(&format!("xref\n0 {}\n", objs.len() + 1));
    out.push_str("0000000000 65535 f \n");
    for off in &offsets {
        out.push_str(&format!("{:010} 00000 n \n", off));
    }
    out.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
        objs.len() + 1,
        xref_pos
    ));
    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    #[test]
    fn produces_pdf_magic_and_pages() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::MagazineSerif, seed: 9 },
            slides: vec![
                Slide {
                    id: "s1".into(),
                    archetype: Archetype::Cover,
                    content: SlideContent::Cover { kicker: None, title: "Bonjour".into(), subtitle: None },
                },
                Slide {
                    id: "s2".into(),
                    archetype: Archetype::Statement,
                    content: SlideContent::Statement { text: "Ship it".into(), attribution: None },
                },
            ],
        };
        let b = to_pdf(&deck());
        let s = String::from_utf8_lossy(&b);
        assert!(s.starts_with("%PDF-1.4"));
        assert!(s.contains("/Count 2"));
        assert!(s.contains("%%EOF"));
    }
}
