//! JSON command protocol — the single API surface shared by every consumer:
//! - Flutter app via FFI (`dreamtx_command`)
//! - Cloudflare Worker via wasm (`command`)
//! - MCP tools (worker/src/tools.ts wraps these ops)
//!
//! The caller owns deck state (app: local files; worker: Deck DO). Every
//! command is a pure function: deck JSON in (where needed) → deck JSON /
//! layout JSON / file bytes (base64) out.

use crate::dna::{cycle_family, next_variant, resolve};
use crate::export::pdf::to_pdf;
use crate::export::pptx::to_pptx;
use crate::layout::layout_slide;
use crate::model::*;
use crate::pacing;
use crate::shapes;
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
        /// Blank start: no cover slide, no template content — an empty
        /// stage the user builds on (the Files drawer's "New · Blank").
        #[serde(default)]
        blank: bool,
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
    /// Change the deck's slide-frame aspect. Objects re-frame with the
    /// change: x and w scale to the new frame width (y and h are untouched —
    /// the design height is the same 720 in every aspect). The caller shows
    /// that re-framing explicitly before invoking; the response reports
    /// whether geometry actually moved.
    SetAspect {
        deck: Deck,
        /// One of [ASPECTS]: "16:9" | "16:10" | "4:3" | "1:1".
        aspect: String,
    },
    // ---- vector overlay layer (manual studio tools) ----------------------
    AddObject {
        deck: Deck,
        slide_id: String,
        shape: Value,
    },
    UpdateObject {
        deck: Deck,
        slide_id: String,
        object_id: String,
        shape: Value,
    },
    DeleteObject {
        deck: Deck,
        slide_id: String,
        object_id: String,
    },
    MoveObjectZ {
        deck: Deck,
        slide_id: String,
        object_id: String,
        to_index: usize,
    },
    BooleanOp {
        deck: Deck,
        slide_id: String,
        a: String,
        b: String,
        /// "union" | "subtract" (a−b) | "intersect"
        mode: String,
    },
    GroupObjects {
        deck: Deck,
        slide_id: String,
        ids: Vec<String>,
    },
    UngroupObjects {
        deck: Deck,
        slide_id: String,
        ids: Vec<String>,
    },
    AlignObjects {
        deck: Deck,
        slide_id: String,
        ids: Vec<String>,
        /// left|center|right|top|middle|bottom (to slide)
        mode: String,
    },
    SaveComponent {
        deck: Deck,
        slide_id: String,
        ids: Vec<String>,
        name: String,
    },
    PlaceComponent {
        deck: Deck,
        slide_id: String,
        component_id: String,
    },
    /// Push the geometry of one instance (the object's slide + component)
    /// to every other instance and the registry — global component update.
    UpdateComponent {
        deck: Deck,
        slide_id: String,
        object_id: String,
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
        "blank" => Some(Archetype::Blank),
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
        Archetype::Blank => SlideContent::Blank,
    }
}

fn next_slide_id(deck: &Deck) -> String {
    let n = deck.slides.len() + 1;
    format!("s_{}_{n}", deck.id.chars().filter(|c| c.is_ascii_alphanumeric()).take(6).collect::<String>())
}

fn next_object_id(deck: &Deck) -> String {
    let n = object_id_counter(deck) + 1;
    format!("o{}_{}", deck_id_prefix(deck), n)
}

fn object_id_counter(deck: &Deck) -> usize {
    deck.slides.iter().map(|s| s.objects.len()).sum::<usize>()
        + deck.components.iter().map(|c| c.objects.len()).sum::<usize>()
}

fn deck_id_prefix(deck: &Deck) -> String {
    deck.id.chars().filter(|c| c.is_ascii_alphanumeric()).take(4).collect::<String>()
}

/// Absolute-space polygon for a shape (preset geometry or freeform points).
/// Also used by the exporters to build custGeom/polygon paths.
pub fn object_polygon(o: &Shape) -> Vec<(f64, f64)> {
    if let Some(pts) = &o.points {
        return pts.iter().map(|p| (o.x + p.x * o.w, o.y + p.y * o.h)).collect();
    }
    shapes::preset_polygon(&o.preset, o.w, o.h).into_iter().map(|(px, py)| (o.x + px, o.y + py)).collect()
}

/// Deck DNA seed. wasm32-unknown-unknown has no wall clock — `SystemTime::now`
/// panics there, which took down the Worker's `new_deck` — so on wasm a
/// per-process sequence mixed with the title length keeps seeds unique within
/// one Worker isolate; native (Flutter FFI, tests) keeps the nanosecond clock
/// and the exact same seed as before.
fn fresh_seed(title: &str) -> u64 {
    #[cfg(target_family = "wasm")]
    {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(1);
        let n = SEQ.fetch_add(1, Ordering::Relaxed) as u64;
        n.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (title.len() as u64)
    }
    #[cfg(not(target_family = "wasm"))]
    {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(42)
            ^ (title.len() as u64)
    }
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
            "aspects": ASPECTS,
            "object_presets": shapes::presets().iter().map(|p| json!({
                "name": p.name,
                "label": p.label,
                "convex": p.convex,
                "open": p.open,
            })).collect::<Vec<_>>(),
        }),
        Command::NewDeck { title, family, blank } => {
            let fam = parse_family(&family).unwrap_or(DnaFamily::SwissEditorial);
            let seed = fresh_seed(&title);
            let mut deck = Deck {
                id: format!("d{:x}", seed & 0xFFFF_FFFF),
                title: title.clone(),
                version: 1,
                dna: Dna { family: fam, seed },
                aspect: "16:9".into(),
                slides: Vec::new(),
                components: Vec::new(),
            };
            if blank {
                // Blank start: zero slides, no template content — the editor
                // already handles the empty deck ("No slide here yet") and
                // the + adds the first slide.
                return json!({ "ok": true, "deck": deck });
            }
            let cover = Slide {
                id: next_slide_id(&deck),
                archetype: Archetype::Cover,
                content: default_content(Archetype::Cover, &deck),
                objects: Vec::new(),
            };
            deck.slides.push(cover);
            json!({ "ok": true, "deck": deck })
        }
        Command::AddSlide { mut deck, archetype, content } => {
            let a = match parse_archetype(&archetype) {
                Some(a) => a,
                None => return json!({ "ok": false, "error": format!("unknown archetype '{archetype}'") }),
            };
            let mut slide = Slide { id: next_slide_id(&deck), archetype: a, content: default_content(a, &deck), objects: Vec::new() };
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
            let old_objects = deck.slides[idx].objects.clone();
            deck.slides[idx] = Slide { id: slide_id, archetype: a, content, objects: old_objects };
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
        Command::SetAspect { mut deck, aspect } => {
            let Some((w, _)) = aspect_dims(&aspect) else {
                return json!({ "ok": false, "error": format!("unknown aspect '{aspect}' — supported: {}", ASPECTS.join(", ")) });
            };
            let old_w = deck_dims(&deck).0;
            let k = w / old_w;
            let reframed = (k - 1.0).abs() > 1e-9;
            if reframed {
                // Re-frame existing geometry to the new width: x and w scale
                // by the width ratio; y and h are untouched (the design height
                // is 720 in every aspect). Normalized polygon points are
                // bbox-local, so they ride along inside each new bbox.
                for s in deck.slides.iter_mut() {
                    for o in s.objects.iter_mut() {
                        o.x *= k;
                        o.w *= k;
                    }
                }
                for c in deck.components.iter_mut() {
                    for o in c.objects.iter_mut() {
                        o.x *= k;
                        o.w *= k;
                    }
                }
            }
            deck.aspect = aspect;
            deck.version += 1;
            json!({ "ok": true, "deck": deck, "reframed": reframed })
        }
        // ---- vector overlay ops --------------------------------------------------
        Command::AddObject { mut deck, slide_id, shape } => {
            let mut obj: Shape = match serde_json::from_value(shape) {
                Ok(s) => s,
                Err(e) => return json!({ "ok": false, "error": format!("bad shape: {e}") }),
            };
            if obj.id.is_empty() {
                obj.id = next_object_id(&deck);
            }
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            slide.objects.push(obj);
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::UpdateObject { mut deck, slide_id, object_id, shape } => {
            let mut obj: Shape = match serde_json::from_value(shape) {
                Ok(s) => s,
                Err(e) => return json!({ "ok": false, "error": format!("bad shape: {e}") }),
            };
            obj.id = object_id;
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let Some(slot) = slide.objects.iter_mut().find(|o| o.id == obj.id) else {
                return json!({ "ok": false, "error": "object not found" });
            };
            *slot = obj;
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::DeleteObject { mut deck, slide_id, object_id } => {
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let before = slide.objects.len();
            slide.objects.retain(|o| o.id != object_id);
            if slide.objects.len() == before {
                return json!({ "ok": false, "error": "object not found" });
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::MoveObjectZ { mut deck, slide_id, object_id, to_index } => {
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let Some(idx) = slide.objects.iter().position(|o| o.id == object_id) else {
                return json!({ "ok": false, "error": "object not found" });
            };
            if to_index >= slide.objects.len() {
                return json!({ "ok": false, "error": "to_index out of range" });
            }
            let obj = slide.objects.remove(idx);
            slide.objects.insert(to_index, obj);
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::BooleanOp { mut deck, slide_id, a, b, mode } => {
            let Some(slide) = deck.slides.iter().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let (Some(sa), Some(sb)) = (slide.objects.iter().find(|o| o.id == a), slide.objects.iter().find(|o| o.id == b)) else {
                return json!({ "ok": false, "error": "object not found" });
            };
            if sa.holes.is_some() || sb.holes.is_some() {
                return json!({ "ok": false, "error": "can't combine holed results — duplicate them first" });
            }
            let pa = object_polygon(sa);
            let pb = object_polygon(sb);
            let m = match mode.as_str() {
                "union" => shapes::BooleanMode::Union,
                "subtract" => shapes::BooleanMode::Subtract,
                "intersect" => shapes::BooleanMode::Intersect,
                other => return json!({ "ok": false, "error": format!("unknown boolean mode '{other}'") }),
            };
            let outcome = match shapes::boolean(pa, pb, m) {
                Ok(o) => o,
                Err(e) => return json!({ "ok": false, "error": e }),
            };
            if outcome.outline.len() < 3 {
                if mode == "subtract" {
                    // a − b removed everything → delete both inputs
                    let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                        return json!({ "ok": false, "error": "slide not found" });
                    };
                    slide.objects.retain(|o| o.id != a && o.id != b);
                    deck.version += 1;
                    return json!({ "ok": true, "deck": deck, "note": "subtracted to nothing — both removed" });
                }
                return json!({ "ok": false, "error": "shapes do not overlap — nothing to combine" });
            }
            let (bx, by, bw, bh) = shapes::bbox(&outcome.outline);
            let (bw, bh) = (bw.max(1.0), bh.max(1.0));
            let norm = |v: &[(f64, f64)]| -> Vec<Pt> {
                v.iter().map(|&(x, y)| Pt { x: ((x - bx) / bw).clamp(0.0, 1.0), y: ((y - by) / bh).clamp(0.0, 1.0) }).collect()
            };
            let pts = norm(&outcome.outline);
            let holes = if outcome.holes.is_empty() {
                None
            } else {
                Some(outcome.holes.iter().map(|h| norm(h)).collect::<Vec<_>>())
            };
            let result = Shape {
                id: next_object_id(&deck),
                preset: "path".into(),
                x: bx, y: by, w: bw, h: bh,
                rotation: 0.0,
                opacity: sa.opacity,
                locked: false,
                group: None,
                component: None,
                fill: sa.fill.clone(),
                stroke: sa.stroke.clone(),
                effects: sa.effects.clone(),
                points: Some(pts),
                holes,
                closed: true,
            };
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let ai = slide.objects.iter().position(|o| o.id == a);
            let bi = slide.objects.iter().position(|o| o.id == b);
            let insert_at = ai.unwrap_or(0).min(bi.unwrap_or(usize::MAX));
            slide.objects.retain(|o| o.id != a && o.id != b);
            let at = insert_at.min(slide.objects.len());
            slide.objects.insert(at, result);
            deck.version += 1;
            json!({ "ok": true, "deck": deck, "note": "union is the convex hull of the two shapes" })
        }
        Command::GroupObjects { mut deck, slide_id, ids } => {
            let gid = format!("g{}", deck.version);
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let mut n = 0;
            for o in slide.objects.iter_mut() {
                if ids.contains(&o.id) {
                    o.group = Some(gid.clone());
                    n += 1;
                }
            }
            if n == 0 {
                return json!({ "ok": false, "error": "no objects to group" });
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::UngroupObjects { mut deck, slide_id, ids } => {
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            for o in slide.objects.iter_mut() {
                if ids.contains(&o.id) {
                    o.group = None;
                    o.component = None;
                }
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::AlignObjects { mut deck, slide_id, ids, mode } => {
            // The frame width is read before the mutable slide borrow —
            // the deck's aspect (16:9 unless changed) decides what
            // center/right mean here.
            let dw = deck_dims(&deck).0;
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            for o in slide.objects.iter_mut() {
                if !ids.contains(&o.id) {
                    continue;
                }
                match mode.as_str() {
                    "left" => o.x = 0.0,
                    "center" => o.x = (dw - o.w) / 2.0,
                    "right" => o.x = dw - o.w,
                    "top" => o.y = 0.0,
                    "middle" => o.y = (SLIDE_H - o.h) / 2.0,
                    "bottom" => o.y = SLIDE_H - o.h,
                    other => return json!({ "ok": false, "error": format!("unknown align mode '{other}'") }),
                }
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::SaveComponent { mut deck, slide_id, ids, name } => {
            let cid = format!("c{}", deck.version);
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let mut picked: Vec<Shape> = Vec::new();
            for o in slide.objects.iter_mut() {
                if ids.contains(&o.id) {
                    o.component = Some(cid.clone());
                    picked.push(o.clone());
                }
            }
            if picked.is_empty() {
                return json!({ "ok": false, "error": "no objects selected" });
            }
            deck.components.push(Component { id: cid.clone(), name, objects: picked });
            deck.version += 1;
            json!({ "ok": true, "deck": deck, "component_id": cid })
        }
        Command::PlaceComponent { mut deck, slide_id, component_id } => {
            let Some(comp) = deck.components.iter().find(|c| c.id == component_id).cloned() else {
                return json!({ "ok": false, "error": "component not found" });
            };
            if comp.objects.is_empty() {
                return json!({ "ok": false, "error": "component is empty" });
            }
            // center the copy on the slide
            let dw = deck_dims(&deck).0;
            let (mut minx, mut miny, mut maxx, mut maxy) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
            for o in &comp.objects {
                minx = minx.min(o.x);
                miny = miny.min(o.y);
                maxx = maxx.max(o.x + o.w);
                maxy = maxy.max(o.y + o.h);
            }
            let dx = (dw - (maxx - minx)) / 2.0 - minx;
            let dy = (SLIDE_H - (maxy - miny)) / 2.0 - miny;
            // pre-generate ids before the mutable slide borrow
            let base = object_id_counter(&deck);
            let prefix = deck_id_prefix(&deck);
            let mut counter = base;
            let mut placed: Vec<Shape> = Vec::with_capacity(comp.objects.len());
            for mut o in comp.objects {
                counter += 1;
                o.id = format!("o{prefix}_{counter}");
                o.x += dx;
                o.y += dy;
                o.group = None;
                o.component = Some(component_id.clone());
                placed.push(o);
            }
            let Some(slide) = deck.slides.iter_mut().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            slide.objects.extend(placed);
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::UpdateComponent { mut deck, slide_id, object_id } => {
            let Some(slide) = deck.slides.iter().find(|s| s.id == slide_id) else {
                return json!({ "ok": false, "error": "slide not found" });
            };
            let Some(ref_obj) = slide.objects.iter().find(|o| o.id == object_id) else {
                return json!({ "ok": false, "error": "object not found" });
            };
            let Some(cid) = ref_obj.component.clone() else {
                return json!({ "ok": false, "error": "object is not a component instance" });
            };
            // canonical geometry = the reference instance's member objects
            let canonical: Vec<Shape> = slide
                .objects
                .iter()
                .filter(|o| o.component.as_deref() == Some(cid.as_str()))
                .cloned()
                .collect();
            if canonical.is_empty() {
                return json!({ "ok": false, "error": "component instance has no objects" });
            }
            let (mut minx, mut miny) = (f64::MAX, f64::MAX);
            for o in &canonical {
                minx = minx.min(o.x);
                miny = miny.min(o.y);
            }
            // registry
            if let Some(comp) = deck.components.iter_mut().find(|c| c.id == cid) {
                comp.objects = canonical.clone();
            }
            // one instance per slide per component in v0.2: replace every
            // slide's instance objects with the canonical geometry, keeping
            // each slide's instance anchor (its top-left member position).
            let base = object_id_counter(&deck);
            let prefix = deck_id_prefix(&deck);
            let mut counter = base;
            let cid_ref = cid.as_str();
            for slide in deck.slides.iter_mut() {
                let has = slide.objects.iter().any(|o| o.component.as_deref() == Some(cid_ref));
                if !has {
                    continue;
                }
                let (ax, ay) = slide
                    .objects
                    .iter()
                    .filter(|o| o.component.as_deref() == Some(cid_ref))
                    .fold((f64::MAX, f64::MAX), |(mx, my), o| (mx.min(o.x), my.min(o.y)));
                let idx = slide
                    .objects
                    .iter()
                    .position(|o| o.component.as_deref() == Some(cid_ref))
                    .unwrap_or(0);
                slide.objects.retain(|o| o.component.as_deref() != Some(cid_ref));
                let at = idx.min(slide.objects.len());
                for (k, o) in canonical.iter().enumerate() {
                    counter += 1;
                    let mut c = o.clone();
                    c.id = format!("o{prefix}_{counter}");
                    c.x += ax - minx;
                    c.y += ay - miny;
                    c.group = None;
                    c.component = Some(cid.clone());
                    slide.objects.insert(at + k, c);
                }
            }
            deck.version += 1;
            json!({ "ok": true, "deck": deck })
        }
        Command::GetLayout { deck, slide_index } => {
            let Some(slide) = deck.slides.get(slide_index) else {
                return json!({ "ok": false, "error": "slide_index out of range" });
            };
            json!({ "ok": true, "layout": layout_slide(&deck, slide) })
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
        SlideContent::Blank => Archetype::Blank,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn deck_with_object() -> Deck {
        Deck {
            id: "d_test".into(),
            title: "T".into(),
            version: 3,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 11 },
            aspect: "16:9".into(),
            slides: vec![Slide {
                id: "s1".into(),
                archetype: Archetype::Blank,
                content: SlideContent::Blank,
                objects: vec![Shape {
                    id: "o1".into(),
                    preset: "rect".into(),
                    x: 640.0,
                    y: 100.0,
                    w: 320.0,
                    h: 80.0,
                    rotation: 0.0,
                    opacity: 1.0,
                    locked: false,
                    group: None,
                    component: None,
                    fill: Fill::None,
                    stroke: Stroke::default(),
                    effects: Effects::default(),
                    points: None,
                    holes: None,
                    closed: false,
                }],
            }],
            components: vec![],
        }
    }

    #[test]
    fn new_deck_blank_starts_empty() {
        let r = execute(r#"{"op":"new_deck","title":"B","blank":true}"#);
        assert_eq!(r["ok"], true);
        assert_eq!(r["deck"]["slides"].as_array().map(Vec::len), Some(0));
        // The default aspect round-trips through the struct: the raw JSON
        // omits "16:9" (skip_serializing_if) so old deck files stay
        // byte-stable — deserialization restores the default.
        let deck: Deck = serde_json::from_value(r["deck"].clone()).unwrap();
        assert_eq!(deck.aspect, "16:9");
        assert!(deck.slides.is_empty());
    }

    #[test]
    fn new_deck_classic_still_carries_a_cover() {
        let r = execute(r#"{"op":"new_deck","title":"C"}"#);
        assert_eq!(r["ok"], true);
        assert_eq!(r["deck"]["slides"].as_array().map(Vec::len), Some(1));
        assert_eq!(r["deck"]["slides"][0]["archetype"], "cover");
    }

    #[test]
    fn set_aspect_reframes_objects() {
        let req = r#"{"op":"set_aspect","deck":__DECK__,"aspect":"4:3"}"#
            .replace("__DECK__", &serde_json::to_string(&deck_with_object()).unwrap());
        let r = execute(&req);
        assert_eq!(r["ok"], true);
        assert_eq!(r["reframed"], true);
        let deck: Deck = serde_json::from_value(r["deck"].clone()).unwrap();
        assert_eq!(deck.aspect, "4:3");
        assert_eq!(deck.version, 4);
        let o = &deck.slides[0].objects[0];
        // x/w scale by 960/1280 = 0.75; y/h untouched.
        assert!((o.x - 480.0).abs() < 1e-9, "x = {}", o.x);
        assert!((o.w - 240.0).abs() < 1e-9, "w = {}", o.w);
        assert!((o.y - 100.0).abs() < 1e-9);
        assert!((o.h - 80.0).abs() < 1e-9);
    }

    #[test]
    fn set_aspect_rejects_unknown() {
        let req = r#"{"op":"set_aspect","deck":__DECK__,"aspect":"21:9"}"#
            .replace("__DECK__", &serde_json::to_string(&deck_with_object()).unwrap());
        let r = execute(&req);
        assert_eq!(r["ok"], false);
        assert!(r["error"].as_str().unwrap().contains("21:9"));
    }

    #[test]
    fn set_aspect_same_ratio_moves_nothing() {
        let req = r#"{"op":"set_aspect","deck":__DECK__,"aspect":"16:9"}"#
            .replace("__DECK__", &serde_json::to_string(&deck_with_object()).unwrap());
        let r = execute(&req);
        assert_eq!(r["ok"], true);
        assert_eq!(r["reframed"], false);
        let deck: Deck = serde_json::from_value(r["deck"].clone()).unwrap();
        let o = &deck.slides[0].objects[0];
        assert!((o.x - 640.0).abs() < 1e-9);
        assert!((o.w - 320.0).abs() < 1e-9);
    }

    #[test]
    fn get_layout_honors_aspect() {
        let mut deck = deck_with_object();
        deck.aspect = "1:1".into();
        let req = r#"{"op":"get_layout","deck":__DECK__,"slide_index":0}"#
            .replace("__DECK__", &serde_json::to_string(&deck).unwrap());
        let r = execute(&req);
        assert_eq!(r["ok"], true);
        assert_eq!(r["layout"]["w"].as_f64(), Some(720.0));
        assert_eq!(r["layout"]["h"].as_f64(), Some(720.0));
    }

    #[test]
    fn meta_lists_aspects() {
        let r = execute(r#"{"op":"meta"}"#);
        assert_eq!(r["ok"], true);
        assert_eq!(
            r["aspects"].as_array().map(|a| a.len()),
            Some(ASPECTS.len())
        );
    }
}
