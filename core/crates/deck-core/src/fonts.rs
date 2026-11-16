//! Font metrics for the layout solver. Bundled DejaVu (see fonts/README.md)
//! gives real advance widths for Latin text; CJK glyph widths are approximated
//! (full-width em) until M2 ships subset CJK fonts.

use std::sync::OnceLock;
use ttf_parser::Face;

pub struct FontSet {
    sans: Option<Face<'static>>,
    sans_bold: Option<Face<'static>>,
    serif: Option<Face<'static>>,
    serif_bold: Option<Face<'static>>,
}

static FONTS: OnceLock<FontSet> = OnceLock::new();

fn parse(bytes: &'static [u8]) -> Option<Face<'static>> {
    Face::parse(bytes, 0).ok()
}

fn fonts() -> &'static FontSet {
    FONTS.get_or_init(|| FontSet {
        sans: parse(include_bytes!("../fonts/DejaVuSans.ttf")),
        sans_bold: parse(include_bytes!("../fonts/DejaVuSans-Bold.ttf")),
        serif: parse(include_bytes!("../fonts/DejaVuSerif.ttf")),
        serif_bold: parse(include_bytes!("../fonts/DejaVuSerif-Bold.ttf")),
    })
}

fn face(serif: bool, bold: bool) -> Option<&'static Face<'static>> {
    let f = fonts();
    match (serif, bold) {
        (true, true) => f.serif_bold.as_ref(),
        (true, false) => f.serif.as_ref(),
        (false, true) => f.sans_bold.as_ref(),
        (false, false) => f.sans.as_ref(),
    }
}

fn is_fullwidth(c: char) -> bool {
    let u = c as u32;
    (0x1100..=0x115F).contains(&u) // Hangul Jamo
        || (0x2E80..=0xA4CF).contains(&u) // CJK radicals..Yi
        || (0xAC00..=0xD7AF).contains(&u) // Hangul syllables
        || (0xF900..=0xFAFF).contains(&u)
        || (0xFF00..=0xFF60).contains(&u) // fullwidth forms
        || (0x20000..=0x3FFFD).contains(&u)
}

/// Width of a single character at `size` px. Unknown glyphs fall back to 0.55em
/// (a decent average for proportional Latin text).
fn char_width(c: char, size: f64, serif: bool, bold: bool) -> f64 {
    if is_fullwidth(c) {
        return size; // approximate CJK full-width until M2
    }
    if let Some(f) = face(serif, bold) {
        if let Some(gid) = f.glyph_index(c) {
            if let Some(adv) = f.glyph_hor_advance(gid) {
                let upem = f.units_per_em() as f64;
                if upem > 0.0 {
                    return adv as f64 / upem * size;
                }
            }
        }
    }
    size * 0.55
}

/// Measured width of a rendered string.
pub fn measure(text: &str, size: f64, serif: bool, bold: bool) -> f64 {
    text.chars().map(|c| char_width(c, size, serif, bold)).sum()
}

/// Greedy word-wrap into lines that fit `max_w`. CJK text breaks per character.
pub fn wrap(text: &str, max_w: f64, size: f64, serif: bool, bold: bool) -> Vec<String> {
    let mut lines = Vec::new();
    let mut cur = String::new();
    let mut cur_w = 0.0;

    let mut push = |lines: &mut Vec<String>, cur: &mut String, cur_w: &mut f64| {
        if !cur.is_empty() {
            lines.push(std::mem::take(cur));
            *cur_w = 0.0;
        }
    };

    for token in tokenize(text) {
        let piece_w = measure(&token.piece, size, serif, bold);
        let sep_w = if token.needs_space && !cur.is_empty() { measure(" ", size, serif, bold) } else { 0.0 };
        if cur_w + sep_w + piece_w > max_w && !cur.is_empty() {
            push(&mut lines, &mut cur, &mut cur_w);
        }
        if token.needs_space && !cur.is_empty() && cur_w > 0.0 {
            cur.push(' ');
            cur_w += sep_w;
        }
        if piece_w > max_w {
            // single token longer than the box: hard-break by char
            for c in token.piece.chars() {
                let cw = char_width(c, size, serif, bold);
                if cur_w + cw > max_w && !cur.is_empty() {
                    push(&mut lines, &mut cur, &mut cur_w);
                }
                cur.push(c);
                cur_w += cw;
            }
        } else {
            cur.push_str(&token.piece);
            cur_w += piece_w;
        }
    }
    if !cur.is_empty() {
        lines.push(cur);
    }
    if lines.is_empty() {
        lines.push(String::new());
    }
    lines
}

struct Token {
    piece: String,
    needs_space: bool,
}

/// Split into layout tokens: runs of non-CJK characters, or single CJK
/// characters (which wrap per character, no space between).
fn tokenize(text: &str) -> Vec<Token> {
    let mut out: Vec<Token> = Vec::new();
    let mut buf = String::new();
    for c in text.chars() {
        if is_fullwidth(c) {
            if !buf.is_empty() {
                out.push(Token { piece: std::mem::take(&mut buf), needs_space: false });
            }
            out.push(Token { piece: c.to_string(), needs_space: false });
        } else if c == ' ' {
            if !buf.is_empty() {
                out.push(Token { piece: std::mem::take(&mut buf), needs_space: false });
            }
            if let Some(last) = out.last_mut() {
                last.needs_space = true;
            }
        } else {
            buf.push(c);
        }
    }
    if !buf.is_empty() {
        out.push(Token { piece: buf, needs_space: false });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn measure_is_sane() {
        let w = measure("Hello world", 20.0, false, false);
        assert!(w > 60.0 && w < 160.0, "measured {w}");
        // bold should not be dramatically narrower
        assert!(measure("Hello world", 20.0, false, true) >= w * 0.9);
    }

    #[test]
    fn wrap_respects_width() {
        let size = 20.0;
        let lines = wrap("the quick brown fox jumps over the lazy dog repeatedly", 200.0, size, false, false);
        assert!(lines.len() > 1);
        for l in &lines {
            assert!(measure(l, size, false, false) <= 200.0 + 1.0);
        }
    }

    #[test]
    fn cjk_wraps_by_char() {
        let lines = wrap("宏大的产品发布计划讨论", 120.0, 24.0, false, false);
        assert!(lines.len() >= 5);
    }
}
