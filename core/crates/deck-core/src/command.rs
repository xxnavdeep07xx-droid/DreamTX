//! JSON command protocol — the single API surface shared by every consumer:
//! - Flutter app via FFI (`dreamtx_command`)
//! - Cloudflare Worker via wasm (`command`)
//! - MCP tools (worker/src/tools.ts wraps these ops)
//!
//! The caller owns deck state (app: local files; worker: Deck DO). Every
//! command is a pure function: deck JSON in (where needed) → deck JSON /
//! layout JSON / file bytes (base64) out.

use crate::dna::{cycle_family, next_variant, resolve, DnaFamily};
use crate::export::pdf::to_pdf;
use crate::export::pptx::to_pptx;
use crate::layout::layout_slide;
use crate::model::*;
use crate::pacing;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum Command {
    /// Static metadata for UI pickers / MCP tool descriptions.
    Meta,
    NewDeck {
        title: String,
        #[serde(default = "default_family")]
        family: String,
    },
    AddSlide {
        deck: Deck,
        archetype: String,
        #[serde(default)]
        content: Option<Value>,
    },
    UpdateSlide {
        deck: Deck,
        slide_id: String,
        archetype: String,
        content: Value,
    },
    DeleteSlide {
        deck: Deck,
        slide_id: String,
    },
    MoveSlide {
        deck: Deck,
        slide_id: String,
        to_index: usize,
    },
    ApplyDna {
        deck: Deck,
        /// "next_variant" | "next_family" | a family name.
        change: String,
    },
    GetLayout {
        deck: Deck,
        slide_index: usize,
    },
    Pacing {
        deck: Deck,
    },
    ExportPptx {
        deck: Deck,
    },
    ExportPdf {
        deck: Deck,
    },
}

fn default_family() -> String {
    "swiss_editorial".into()
}

fn parse_family(s: &str) -> Option<DnaFamily> {
    match s {
        "swiss_editorial" | "swiss" => Some(DnaFamily::SwissEditorial),
        "cinematic" | "cinema" => Some(DnaFamily::Cinematic),
        "magazine_serif" | "magazine" => Some(DnaFamily::MagazineSerif),
        _ => None,
    }
}

fn parse_archetype(s: &str) -> Option<Archetype> {
    match s {
        "cover" => Some(Archetype::Cover),
        "agenda" => Some(Archetype::Agenda),
        "section" => Some(Archetype::Section),
        "statement" => Some(Archetype::Statement),
        "stat_wall" => Some(Archetype::StatWall),
        "split" => Some(Archetype::Split),
        "comparison" => Some(Archetype::Comparison),
        "chart_hero" => Some(Archetype::ChartHero),
        "closing" => Some(Archetype::Closing),
        _ => None,
    }
}

fn b64(data: &[u8]) -> String {
    // tiny base64 (no_std-friendly, no deps)
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(T[(n >> 18 & 63) as usize] as char);
        out.push(T[(n >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 { T[(n >> 6 & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { T[(n & 63) as usize] as char } else { '=' });
    }
    out
}

/// Default content when the AI/user adds a slide without providing it.
fn default_content(a: Archetype, deck: &Deck) -> SlideContent {
    match a {
        Archetype::Cover => SlideContent::Cover {
            kicker: None,
            title: deck.title.clone(),
            subtitle: Some("Built with DreamTX".into()),
        },
        Archetype::Agenda => SlideContent::Agenda { title: "Agenda".into(), items: vec!["First topic".into(), "Second topic".into(), "Third topic".into()] },
        Archetype::Section => SlideContent::Section { index: 1, title: "Section".into(), blurb: None },
        Archetype::Statement => SlideContent::Statement { text: "One idea per slide.".into(), attribution: None },
        Archetype::StatWall => SlideContent::StatWall {
            title: None,
            stats: vec![Stat { value: "42%".into(), label: "of something that matters".into() }],
        },
        Archetype::Split => SlideContent::Split { title: "Title".into(), bullets: vec!["Point one".into(), "Point two".into()], visual_label: Some("visual".into()) },
        Archetype::Comparison => SlideContent::Comparison {
            title: None,
            left: CompareSide { title: "Option A".into(), points: vec!["pro".into()] },
            right: CompareSide { title: "Option B".into(), points: vec!["pro".into()] },
        },
        Archetype::ChartHero => SlideContent::ChartHero {
            title: "Trend".into(),
            chart: ChartSpec { kind: ChartKind::Bar, categories: vec!["Q1".into(), "Q2".into(), "Q3".into()], series: vec![Series { name: "value".into(), values: vec![1.0, 2.0, 3.0] }] },
            takeaway: None,
        },
        Archetype::Closing => SlideContent::Closing { title: "Thank you".into(), subtitle: None },
    }
}

fn next_slide_id(deck: &Deck) -> String {
    let n = deck.slides.len() + 1;
    format!("s_{}_{n}", deck.id.chars().filter(|c| c.is_ascii_alphanumeric()).take(6).collect::<String>())
}

/// Execute one JSON command, returning a JSON response object.
pub fn execute(req: &str) -> Value {
    let cmd: Command = match serde_json::from_str(req) {
        Ok(c) => c,
        Err(e) => return json!({ "ok": false, "error": format!("bad command: {e}") }),
    };
    match cmd {
        Command::Meta => json!({
            "ok": true,
            "archetypes": Archetype::all().iter().map(|a| a.label()).collect::<Vec<_>>(),
            "families": ["swiss_editorial", "cinematic", "magazine_serif"],
        }),
        Command::NewDeck { title, family } => {
            let fam = parse_family(&family).unwrap_or(DnaFamily::SwissEditorial);
            let seed = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(42)
                ^ title.len() as u64;
            let mut deck = Deck {
                id: format!("d{:x}", seed & 0xFFFF_FFFF),
                title: title.clone(),
                version: 1,
                dna: Dna { family: fam, seed },
                slides: Vec::new(),
            };
            let cover = Slide {
                id: next_slide_id(&deck),
                archetype: Archetype::Cover,
                content: default_content(Archetype::Cover, &deck),
            };
            deck.slides.push(cover);
            json!({ "ok": true, "deck": deck })
        }
        Command::AddSlide { mut deck, archetype, content } => {
            let a = match parse_archetype(&archetype) {
                Some(a) => a,
                None => return json!({ "ok": false, "error": format!("unknown archetype '{archetype}'") }),
            };
            let mut slide = Slide { id: next_slide_id(&deck), archetype: a, content: default_content(a, &deck) };
            if let Some(c) = content {
                slide.content = match serde_json::from_value(c) {
                    Ok(c) => c,
                    Err(e) => return json!({ "ok": false, "error": format!("content mismatch for {archetype}: {e}") }),
                };
                // keep archetype in sync with content
                slide.archetype = archetype_of(&slide.content);
            }
            deck.slides.push(slide);
            deck.version += 1;
            json!({ "ok": true, "deck": deck, "next_suggested": pacing::suggest_next(&deck) })
        }
        Command::UpdateSlide { mut deck, slide_id, archetype, content } => {
            let idx = deck.slides.iter().position(|s| s.id == slide_id);
            let Some(idx) = idx else { return json!({ "ok": false, "error": "slide not found" }) };
            let a = match parse_archetype(&archetype) {
                Some(a) => a,
                None => return json!({ "ok": false, "error": format!("unknown archetype '{archetype}'") }),
            };
            let content: SlideContent = match serde_json::from_value(content) {
                Ok(c) => c,
                Err(e) => return json!({ "ok": false, "error": format!("content mismatch: {e}") }),
            };
            deck.slides[idx] = Slide { id: slide_id, archetype: a, content };
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::DeleteSlide { mut deck, slide_id } => {
            let before = deck.slides.len();
            deck.slides.retain(|s| s.id != slide_id);
            if deck.slides.len() == before {
                return json!({ "ok": false, "error": "slide not found" });
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::MoveSlide { mut deck, slide_id, to_index } => {
            let Some(idx) = deck.slides.iter().position(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            if to_index >= deck.slides.len() {
                return json!({ "ok": false, "error": "to_index out of range" });
            }
            let slide = deck.slides.remove(idx);
            deck.slides.insert(to_index, slide);
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::ApplyDna { mut deck, change } => {
            deck.dna = match change.as_str() {
                "next_variant" => next_variant(&deck.dna),
                "next_family" => cycle_family(&deck.dna),
                other => match parse_family(other) {
                    Some(f) => Dna { family: f, seed: deck.dna.seed },
                    None => return json!({ "ok": false, "error": format!("unknown change '{other}'") }),
                },
            };
            deck.version += 1;
            json!({ "ok": true, "deck": deck, "dna": resolve(&deck.dna) })
        }
        Command::GetLayout { deck, slide_index } => {
            let Some(slide) = deck.slides.get(slide_index) else {
                return json!({ "ok": false, "error": "slide_index out of range" });
            };
            json!({ "ok": true, "layout": layout_slide(&deck.dna, slide) })
        }
        Command::Pacing { deck } => json!({ "ok": true, "issues": pacing::audit(&deck), "next_suggested": pacing::suggest_next(&deck) }),
        Command::ExportPptx { deck } => {
            let bytes = to_pptx(&deck);
            json!({ "ok": true, "mime": "application/vnd.openxmlformats-officedocument.presentationml.presentation", "base64": b64(&bytes), "size": bytes.len() })
        }
        Command::ExportPdf { deck } => {
            let bytes = to_pdf(&deck);
            json!({ "ok": true, "mime": "application/pdf", "base64": b64(&bytes), "size": bytes.len() })
        }
    }
}

fn archetype_of(c: &SlideContent) -> Archetype {
    match c {
        SlideContent::Cover { .. } => Archetype::Cover,
        SlideContent::Agenda { .. } => Archetype::Agenda,
        SlideContent::Section { .. } => Archetype::Section,
        SlideContent::Statement { .. } => Archetype::Statement,
        SlideContent::StatWall { .. } => Archetype::StatWall,
        SlideContent::Split { .. } => Archetype::Split,
        SlideContent::Comparison { .. } => Archetype::Comparison,
        SlideContent::ChartHero { .. } => Archetype::ChartHero,
        SlideContent::Closing { .. } => Archetype::Closing,
    }
}
