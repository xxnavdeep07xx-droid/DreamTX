//! DNAs: curated deck identities + deterministic per-deck variation.
//!
//! Variation comes from a seeded PRNG over *curated* choices (never free
//! parameters) so any output stays on-purpose. Two decks asking for the same
//! thing look different; both still look designed.

use crate::model::{Dna, DnaFamily};
use serde::{Deserialize, Serialize};

/// A fully resolved design identity for one deck.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResolvedDna {
    pub family: String,
    pub palette: Palette,
    /// Six chart series colors (6 hex digits, no `#`), derived from the
    /// palette: accent first, then fg and muted, then tints. Charts with no
    /// explicit series color read this list, so a chart matches its deck.
    pub chart_palette: Vec<String>,
    /// "serif" or "sans" display role; maps to bundled font files.
    pub display_font: FontRole,
    pub body_font: FontRole,
    /// Corner radius language (px at 1280x720).
    pub corner: f64,
    /// Signature motif variant.
    pub motif: Motif,
    /// Type scale ratio (display sizes multiplier).
    pub scale: f64,
}

/// The chart series palette for a deck: accent, fg, muted, then mixes of
/// those with the accent and the background. Every entry is 6 hex digits.
pub fn chart_palette_of(p: &Palette) -> Vec<String> {
    vec![
        p.accent.clone(),
        p.fg.clone(),
        p.muted.clone(),
        mix_hex(&p.accent, &p.fg, 0.5),
        mix_hex(&p.accent, &p.bg, 0.5),
        mix_hex(&p.muted, &p.bg, 0.5),
    ]
}

/// Linear RGB mix of two 6-digit hex colors; `t` is the share of `b`.
fn mix_hex(a: &str, b: &str, t: f64) -> String {
    let ch = |h: &str, i: usize| u8::from_str_radix(h.get(i..i + 2).unwrap_or("00"), 16).unwrap_or(0) as f64;
    let mix = |i: usize| (ch(a, i) * (1.0 - t) + ch(b, i) * t).round() as u8;
    format!("{:02X}{:02X}{:02X}", mix(0), mix(2), mix(4))
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FontRole {
    Sans,
    Serif,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Palette {
    pub bg: String,
    pub surface: String,
    pub fg: String,
    pub muted: String,
    pub accent: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Motif {
    RuleLine,
    NumberStamp,
    EdgeBar,
}

/// Tiny deterministic PRNG (xorshift) — same seed, same deck, everywhere.
fn rng(seed: u64) -> impl FnMut() -> u64 {
    let mut s = if seed == 0 { 0x9E37_79B9_7F4A_7C15 } else { seed };
    move || {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        s
    }
}

/// Curated accent pools per family. Hex without '#'.
const SWISS_ACCENTS: [&str; 6] = ["D03028", "1A4FBF", "0F7B5A", "C25E00", "5B3EA8", "B0006E"];
const CINE_ACCENTS: [&str; 5] = ["F5A623", "E85D42", "4ECDC4", "C2356B", "A8DADC"];
const MAG_ACCENTS: [&str; 5] = ["7A1E2E", "27536B", "5C4406", "1F4D3F", "3D2C5E"];

fn pick<'a>(r: &mut impl FnMut() -> u64, items: &[&'a str]) -> &'a str {
    items[(r() % items.len() as u64) as usize]
}

/// WCAG-style relative luminance of a 6-digit hex color.
fn luminance(hex: &str) -> f64 {
    let v = u32::from_str_radix(hex, 16).unwrap_or(0);
    let ch = |shift: u32| {
        let c = ((v >> shift) & 0xFF) as f64 / 255.0;
        if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powi(2) }
    };
    0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0)
}

/// Contrast ratio between two hex colors (1..21). We keep text/background >= 4.5.
fn contrast(a: &str, b: &str) -> f64 {
    let (la, lb) = (luminance(a), luminance(b));
    let (hi, lo) = if la > lb { (la, lb) } else { (lb, la) };
    (hi + 0.05) / (lo + 0.05)
}

/// Resolve a deck's DNA into concrete style values.
pub fn resolve(dna: &Dna) -> ResolvedDna {
    let mut r = rng(dna.seed);
    let (bg_pool, accent_pool, display, body, corner, motifs, scale) = match dna.family {
        DnaFamily::SwissEditorial => (
            ["F7F6F3", "FFFFFF", "EFEDE8"],
            &SWISS_ACCENTS[..],
            FontRole::Sans,
            FontRole::Sans,
            0.0,
            &[Motif::RuleLine, Motif::NumberStamp][..],
            1.0,
        ),
        DnaFamily::Cinematic => (
            ["0D1117", "141920", "0A0E13"],
            &CINE_ACCENTS[..],
            FontRole::Sans,
            FontRole::Sans,
            6.0,
            &[Motif::EdgeBar, Motif::NumberStamp][..],
            1.08,
        ),
        DnaFamily::MagazineSerif => (
            ["F4EFE6", "FAF7F0", "EDE6D8"],
            &MAG_ACCENTS[..],
            FontRole::Serif,
            FontRole::Sans,
            2.0,
            &[Motif::RuleLine, Motif::EdgeBar][..],
            1.0,
        ),
    };

    let bg = bg_pool[(r() % bg_pool.len() as u64) as usize];
    let surface = bg_pool[(r() % bg_pool.len() as u64) as usize];
    let fg = match dna.family {
        DnaFamily::Cinematic => "F2F0EC".to_string(),
        _ => "17181A".to_string(),
    };
    let muted = if luminance(bg) > 0.5 { "6B6E76".to_string() } else { "9AA0A8".to_string() };

    // Accent must contrast with bg for text use; walk the pool until it does.
    let mut accent = pick(&mut r, accent_pool).to_string();
    if contrast(&accent, bg) < 3.0 {
        for cand in accent_pool {
            if contrast(cand, bg) >= 3.0 {
                accent = cand.to_string();
                break;
            }
        }
    }

    let motif = motifs[(r() % motifs.len() as u64) as usize];
    let scale = scale * (0.97 + (r() % 7) as f64 / 100.0); // ±3% type-scale drift

    let palette = Palette { bg: bg.to_string(), surface: surface.to_string(), fg, muted, accent };
    let chart_palette = chart_palette_of(&palette);
    ResolvedDna {
        family: dna.family.label().to_string(),
        palette,
        chart_palette,
        display_font: display,
        body_font: body,
        corner,
        motif,
        scale,
    }
}

/// Deterministic "variant" bump: same family, new seed → new look.
pub fn next_variant(dna: &Dna) -> Dna {
    let mut s = dna.seed;
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    Dna { family: dna.family, seed: s }
}

/// Flip to the next curated family (cycles the trio).
pub fn cycle_family(dna: &Dna) -> Dna {
    let family = match dna.family {
        DnaFamily::SwissEditorial => DnaFamily::Cinematic,
        DnaFamily::Cinematic => DnaFamily::MagazineSerif,
        DnaFamily::MagazineSerif => DnaFamily::SwissEditorial,
    };
    Dna { family, seed: dna.seed }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_resolution() {
        let dna = Dna { family: DnaFamily::SwissEditorial, seed: 42 };
        assert_eq!(resolve(&dna), resolve(&dna));
    }

    #[test]
    fn chart_palette_comes_from_the_dna() {
        let r = resolve(&Dna { family: DnaFamily::SwissEditorial, seed: 7 });
        assert_eq!(r.chart_palette.len(), 6);
        assert_eq!(r.chart_palette[0], r.palette.accent);
        assert_eq!(r.chart_palette[1], r.palette.fg);
        for c in &r.chart_palette {
            assert!(c.len() == 6 && c.chars().all(|ch| ch.is_ascii_hexdigit()), "hex: {c}");
        }
    }

    #[test]
    fn variation_actually_varies() {
        let mut seen = std::collections::HashSet::new();
        for seed in 0..50 {
            let d = Dna { family: DnaFamily::SwissEditorial, seed };
            seen.insert(resolve(&d).palette.accent);
        }
        // 50 seeds over 6 accents + bg drift should produce >1 identity.
        assert!(seen.len() >= 2);
    }

    #[test]
    fn text_contrast_holds() {
        for family in [DnaFamily::SwissEditorial, DnaFamily::Cinematic, DnaFamily::MagazineSerif] {
            for seed in 0..30 {
                let d = Dna { family, seed };
                let r = resolve(&d);
                assert!(contrast(&r.palette.fg, &r.palette.bg) >= 7.0, "fg contrast");
                assert!(contrast(&r.palette.accent, &r.palette.bg) >= 3.0, "accent contrast");
            }
        }
    }
}
