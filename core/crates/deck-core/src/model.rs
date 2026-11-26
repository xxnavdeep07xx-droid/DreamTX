#![allow(clippy::needless_doctest_main)]
//! Deck model. The single source of truth shared by the Flutter app (via FFI
//! JSON), the Worker (via wasm JSON), and the MCP tool schema (worker/src/tools.ts).
//!
//! The AI only ever produces this model — never coordinates. Pixels are the
//! layout solver's job (see layout.rs).

use serde::{Deserialize, Serialize};

pub const SLIDE_W: f64 = 1280.0;
pub const SLIDE_H: f64 = 720.0;

/// Supported slide-frame aspects. The design HEIGHT stays 720 in every one;
/// the width follows the ratio: 16:9 → 1280, 16:10 → 1152, 4:3 → 960,
/// 1:1 → 720 (all in the same design-px space, so vertical layout math and
/// type scale are untouched by a ratio change).
pub const ASPECTS: [&str; 4] = ["16:9", "16:10", "4:3", "1:1"];

/// (width, height) of the design space for a supported aspect; None for an
/// unrecognized one (callers decide between rejecting and defaulting).
pub fn aspect_dims(aspect: &str) -> Option<(f64, f64)> {
    match aspect {
        "16:9" => Some((1280.0, 720.0)),
        "16:10" => Some((1152.0, 720.0)),
        "4:3" => Some((960.0, 720.0)),
        "1:1" => Some((720.0, 720.0)),
        _ => None,
    }
}

/// A deck's design-space dimensions — the deck's aspect when recognized,
/// the classic 1280×720 otherwise (old decks predate the field).
pub fn deck_dims(deck: &Deck) -> (f64, f64) {
    aspect_dims(&deck.aspect).unwrap_or((SLIDE_W, SLIDE_H))
}

fn default_aspect() -> String {
    "16:9".into()
}

fn is_default_aspect(a: &str) -> bool {
    a == "16:9"
}

fn is_false(b: &bool) -> bool {
    !*b
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Deck {
    pub id: String,
    pub title: String,
    pub version: u64,
    pub dna: Dna,
    /// Slide-frame aspect (see [ASPECTS]). Old decks predate the field and
    /// deserialize as the default; the classic width is omitted from
    /// serialization so existing deck files stay byte-stable.
    #[serde(default = "default_aspect", skip_serializing_if = "is_default_aspect")]
    pub aspect: String,
    pub slides: Vec<Slide>,
    /// Reusable design components (logos, quote cards, badges). Instances on
    /// slides reference these by `Shape.component`; edits propagate globally
    /// via `update_component`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub components: Vec<Component>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Slide {
    pub id: String,
    pub archetype: Archetype,
    /// Nested (not flattened): serde-flatten + internally-tagged enums is a
    /// known landmine; the explicit field keeps the protocol robust.
    pub content: SlideContent,
    /// Manual vector overlay layer: shapes, connectors, scribbles. Drawn on
    /// top of the archetype layout; the AI protocol never needs to know it
    /// exists (but the ops are exposed, so it can drive it too).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub objects: Vec<Shape>,
    /// Hide the DNA's background graphics (the motif stamp / edge bar / rule)
    /// on this slide. Off by default; set with `set_slide_hide_graphics`.
    #[serde(default, skip_serializing_if = "is_false")]
    pub hide_graphics: bool,
    /// Solid background color for this slide (6 hex digits, no `#`). None
    /// uses the DNA background. Text switches to a readable ink on it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub background: Option<String>,
}

// ---------------------------------------------------------------------------
// Vector overlay layer
// ---------------------------------------------------------------------------

/// A positioned vector object in the 1280x720 design space. `points` are
/// normalized (0..1) bbox-local coordinates for polygon/path presets, so
/// geometry survives resizes.
///
/// Objects that carry `content` render as CONTENT, not as their vector
/// silhouette: the base geometry (x/y/w/h/rotation/opacity/locked/group)
/// keeps the whole gesture/z-order/component machinery working unchanged,
/// while the payload describes what the object IS — a rich text box, an
/// image or media asset reference, a vector icon sticker, or a table. The
/// core stores and round-trips `content` verbatim (it is part of the deck
/// model, so it persists with the deck file like every other field); the
/// app owns its interpretation. Export renders the object's vector box
/// (fill/stroke as declared) — content rendering is a client capability.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Shape {
    pub id: String,
    /// Preset name (see `shapes::presets()`) or "path" for freeform geometry.
    pub preset: String,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    #[serde(default)]
    pub rotation: f64, // degrees, clockwise, around bbox center
    #[serde(default = "one")]
    pub opacity: f64, // 0..1
    #[serde(default)]
    pub locked: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub component: Option<String>,
    #[serde(default)]
    pub fill: Fill,
    #[serde(default)]
    pub stroke: Stroke,
    #[serde(default)]
    pub effects: Effects,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub points: Option<Vec<Pt>>,
    /// Holes for boolean-subtract results where the cut shape sits fully
    /// inside the outline (donut). Normalized like `points`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub holes: Option<Vec<Vec<Pt>>>,
    #[serde(default)]
    pub closed: bool,
    /// The object's content payload — present when the object is a text
    /// box, image, icon sticker, media asset, or table rather than a pure
    /// vector shape. Absent for classic shapes (so existing deck files stay
    /// byte-stable).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<ObjectContent>,
    /// Tap-action: opens a web link or jumps to another slide. Exported as
    /// PPTX hyperlinks and PDF link annotations. Absent for plain objects.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link: Option<Link>,
}

/// What a tap-action does.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum LinkKind {
    /// `target` is an absolute http(s) or mailto URL.
    Url,
    /// `target` is the id of a slide in this deck.
    Slide,
}

/// A tap-action attached to an object (see `Shape.link`).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Link {
    pub kind: LinkKind,
    pub target: String,
}

impl Link {
    /// The target URL when this is a `Url` link that is safe to export.
    /// Only http, https, and mailto are allowed, with no whitespace or
    /// control characters, so `javascript:` and `file:` targets never ship.
    pub fn safe_url(&self) -> Option<&str> {
        if self.kind != LinkKind::Url {
            return None;
        }
        let t = self.target.as_str();
        let ok_scheme = ["https://", "http://", "mailto:"]
            .iter()
            .any(|p| t.len() > p.len() && t.get(..p.len()).is_some_and(|head| head.eq_ignore_ascii_case(p)));
        let clean = t.chars().all(|c| !c.is_whitespace() && !c.is_control());
        (ok_scheme && clean).then_some(t)
    }
}

// ---------------------------------------------------------------------------
// Object content payloads
// ---------------------------------------------------------------------------

/// What an object IS when it is not a plain vector shape. Internally
/// tagged (`{"kind":"text", ...}`), additive, and app-interpreted: the core
/// round-trips it with the deck and never reaches inside.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ObjectContent {
    /// A rich text box. The plain text (paragraphs separated by `\n`) is
    /// the caret/selection coordinate space; `runs` are character-format
    /// marks over that string; `paras` are per-paragraph styles anchored at
    /// paragraph starts.
    Text {
        doc: TextDoc,
    },
    /// An image placed on the slide. The bytes live in the device resource
    /// store (`brand` picks the scope); `name` survives for display when
    /// the asset file itself is gone.
    Image {
        resource_id: String,
        #[serde(default)]
        brand: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
    },
    /// A vector icon sticker. `name` is the icon key (the app's icon
    /// registry); the object's fill color paints the glyph.
    Icon {
        name: String,
    },
    /// A video or audio asset placed on the slide (an import — never a
    /// recording). `media_kind` is "video" or "audio" for display.
    Media {
        resource_id: String,
        #[serde(default)]
        brand: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        media_kind: Option<String>,
    },
    /// A table with editable cells. `cells` is row-major, `rows * cols`
    /// entries, each cell a plain-text string.
    Table {
        rows: u32,
        cols: u32,
        #[serde(default)]
        cells: Vec<String>,
    },
    /// A native chart with literal data: `labels` are the categories and
    /// each series holds one value per label. PPTX gets a real chart part;
    /// PDF gets the same drawing as vectors.
    Chart {
        style: ChartStyle,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        #[serde(default)]
        labels: Vec<String>,
        #[serde(default)]
        series: Vec<ChartSeries>,
    },
}

/// How a chart draws its data.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ChartStyle {
    /// Vertical bars, one group per label.
    Column,
    /// Horizontal bars, one group per label.
    Bar,
    /// One line per series across the labels.
    Line,
    /// A pie of the first series; labels name the slices.
    Pie,
}

/// One data series of a chart. `color` is a 6-digit hex (with or without
/// `#`); anything else falls back to the palette.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ChartSeries {
    pub name: String,
    #[serde(default)]
    pub values: Vec<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
}

/// Default chart colors, used in order when a series has no valid color.
pub const CHART_PALETTE: [&str; 6] = ["4F46E5", "10B981", "F59E0B", "EF4444", "6B7280", "0EA5E9"];

impl ChartSeries {
    /// The series color as 6 hex digits (no `#`). Without a valid color of
    /// its own, the series takes entry `i` of `palette` (the deck's chart
    /// palette); an empty palette falls back to `CHART_PALETTE`.
    pub fn color_at(&self, i: usize, palette: &[String]) -> String {
        if let Some(c) = &self.color {
            let h = c.trim_start_matches('#');
            if h.len() == 6 && h.chars().all(|ch| ch.is_ascii_hexdigit()) {
                return h.to_ascii_uppercase();
            }
        }
        if palette.is_empty() {
            CHART_PALETTE[i % CHART_PALETTE.len()].to_string()
        } else {
            palette[i % palette.len()].clone()
        }
    }
}

/// The value scale for a set of series: the lowest and highest values,
/// always including zero. A flat range is widened by 1 so it still draws.
pub fn chart_range(series: &[ChartSeries]) -> (f64, f64) {
    let mut lo = 0.0_f64;
    let mut hi = 0.0_f64;
    for v in series.iter().flat_map(|s| s.values.iter().copied()) {
        if v.is_finite() {
            lo = lo.min(v);
            hi = hi.max(v);
        }
    }
    if hi <= lo {
        hi = lo + 1.0;
    }
    (lo, hi)
}

/// A rich text document: plain text + formatting marks. Offsets are UTF-16
/// code-unit indices into `text` — the same space a Flutter text field's
/// `TextSelection` uses — so the app maps selections onto runs directly.
/// Rust never interprets these; they are model data.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct TextDoc {
    pub text: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub runs: Vec<TextRun>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub paras: Vec<ParaStyle>,
    #[serde(default)]
    pub valign: VerticalAlign,
    #[serde(default)]
    pub autofit: Autofit,
}

/// One character-formatting mark over `[start, end)` of the doc's text.
/// Only set attributes serialize; an absent attribute inherits the doc's
/// base style.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TextRun {
    pub start: u32,
    pub end: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bold: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub italic: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub underline: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub strike: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subscript: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub superscript: Option<bool>,
    /// Text color, RRGGBB.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    /// Color behind the text (highlight), RRGGBB.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub highlight: Option<String>,
    /// 'sans' | 'serif' | 'mono' (the app's renderable families).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_family: Option<String>,
    /// Design-space font size.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_size: Option<f64>,
}

/// Paragraph-level style, anchored at a paragraph start offset and applying
/// until the next anchor (or the end).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ParaStyle {
    pub start: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub align: Option<TextAlign>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub list: Option<ListKind>,
    /// List indent level, 0-based.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub indent: Option<u32>,
    /// Line-spacing multiplier (1.0, 1.15, 1.5, 2.0).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub line_spacing: Option<f64>,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum VerticalAlign {
    #[default]
    Top,
    Middle,
    Bottom,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Autofit {
    /// No autofit — text overflows the box as-is.
    #[default]
    None,
    /// Shrink text on overflow until it fits.
    Shrink,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TextAlign {
    #[default]
    Left,
    Center,
    Right,
    Justify,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ListKind {
    #[default]
    None,
    Bullet,
    Number,
}

fn one() -> f64 {
    1.0
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct Pt {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Fill {
    None,
    Solid {
        color: String, // RRGGBB
    },
    LinearGradient {
        angle: f64, // degrees; 0 = left→right
        from: String,
        to: String,
    },
    RadialGradient {
        from: String,
        to: String,
    },
}

impl Default for Fill {
    fn default() -> Self {
        Fill::None
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Stroke {
    #[serde(default = "default_stroke_color")]
    pub color: String,
    #[serde(default)]
    pub width: f64, // design px; 0 = no stroke
    #[serde(default)]
    pub dash: DashStyle,
    #[serde(default)]
    pub start_arrow: ArrowHead,
    #[serde(default)]
    pub end_arrow: ArrowHead,
}

fn default_stroke_color() -> String {
    "17181A".into()
}

impl Default for Stroke {
    fn default() -> Self {
        Stroke {
            color: default_stroke_color(),
            width: 0.0,
            dash: DashStyle::Solid,
            start_arrow: ArrowHead::None,
            end_arrow: ArrowHead::None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum DashStyle {
    #[default]
    Solid,
    Dash,
    Dot,
    DashDot,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum ArrowHead {
    #[default]
    None,
    Arrow,
    Triangle,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Effects {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub shadow: Option<Shadow>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub glow: Option<Glow>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Shadow {
    #[serde(default)]
    pub dx: f64,
    #[serde(default)]
    pub dy: f64,
    #[serde(default = "default_blur")]
    pub blur: f64,
    #[serde(default = "default_shadow_color")]
    pub color: String,
    #[serde(default = "default_shadow_alpha")]
    pub opacity: f64,
}

fn default_blur() -> f64 {
    12.0
}
fn default_shadow_color() -> String {
    "000000".into()
}
fn default_shadow_alpha() -> f64 {
    0.45
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Glow {
    #[serde(default = "default_glow_color")]
    pub color: String,
    #[serde(default = "default_blur")]
    pub blur: f64,
}

fn default_glow_color() -> String {
    "D03028".into()
}

/// A reusable component definition: a named bag of shapes. Instances on
/// slides carry `component: Some(id)` and a verbatim copy of the geometry.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Component {
    pub id: String,
    pub name: String,
    pub objects: Vec<Shape>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Archetype {
    Cover,
    Agenda,
    Section,
    Statement,
    StatWall,
    Split,
    Comparison,
    ChartHero,
    Closing,
    /// Empty canvas — no archetype elements, just the DNA background. The
    /// user fills it with the vector overlay (shapes, scribbles) or switches
    /// it to a content layout later. Not in `all()`: pickers/MCP list the
    /// curated content layouts; blank is what `+` creates directly.
    Blank,
}

impl Archetype {
    pub fn all() -> [Archetype; 9] {
        [
            Archetype::Cover,
            Archetype::Agenda,
            Archetype::Section,
            Archetype::Statement,
            Archetype::StatWall,
            Archetype::Split,
            Archetype::Comparison,
            Archetype::ChartHero,
            Archetype::Closing,
        ]
    }

    pub fn label(&self) -> &'static str {
        match self {
            Archetype::Cover => "Cover",
            Archetype::Agenda => "Agenda",
            Archetype::Section => "Section break",
            Archetype::Statement => "Big statement",
            Archetype::StatWall => "Stat wall",
            Archetype::Split => "Split text + visual",
            Archetype::Comparison => "Comparison",
            Archetype::ChartHero => "Chart hero",
            Archetype::Closing => "Closing",
            Archetype::Blank => "Blank",
        }
    }
}

/// Per-archetype content. Every field is semantic — never positional.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SlideContent {
    Cover {
        kicker: Option<String>,
        title: String,
        subtitle: Option<String>,
    },
    Agenda {
        title: String,
        items: Vec<String>,
    },
    Section {
        index: u32,
        title: String,
        blurb: Option<String>,
    },
    Statement {
        text: String,
        attribution: Option<String>,
    },
    StatWall {
        title: Option<String>,
        stats: Vec<Stat>,
    },
    Split {
        title: String,
        bullets: Vec<String>,
        visual_label: Option<String>,
    },
    Comparison {
        title: Option<String>,
        left: CompareSide,
        right: CompareSide,
    },
    ChartHero {
        title: String,
        chart: ChartSpec,
        takeaway: Option<String>,
    },
    Closing {
        title: String,
        subtitle: Option<String>,
    },
    /// Empty canvas — serializes as `{"kind":"blank"}`. Pairs with
    /// `Archetype::Blank`.
    Blank,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Stat {
    pub value: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompareSide {
    pub title: String,
    pub points: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ChartSpec {
    #[serde(rename = "type")]
    pub kind: ChartKind,
    pub categories: Vec<String>,
    pub series: Vec<Series>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ChartKind {
    Bar,
    Line,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Series {
    pub name: String,
    pub values: Vec<f64>,
}

/// Deck DNA — the per-deck design identity. `seed` drives deterministic
/// variation inside a curated family (accent pick, bg tint, motif).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Dna {
    pub family: DnaFamily,
    pub seed: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DnaFamily {
    SwissEditorial,
    Cinematic,
    MagazineSerif,
    Bold,
    Pastel,
}

impl DnaFamily {
    pub fn label(&self) -> &'static str {
        match self {
            DnaFamily::SwissEditorial => "Swiss editorial",
            DnaFamily::Cinematic => "Cinematic",
            DnaFamily::MagazineSerif => "Magazine serif",
            DnaFamily::Bold => "Bold",
            DnaFamily::Pastel => "Pastel",
        }
    }
}

#[cfg(test)]
mod link_tests {
    use super::*;

    fn url(target: &str) -> Link {
        Link { kind: LinkKind::Url, target: target.into() }
    }

    #[test]
    fn safe_url_allows_web_and_mail_only() {
        assert_eq!(url("https://example.com/a?x=1").safe_url(), Some("https://example.com/a?x=1"));
        assert_eq!(url("HTTP://example.com").safe_url(), Some("HTTP://example.com"));
        assert_eq!(url("mailto:hi@example.com").safe_url(), Some("mailto:hi@example.com"));
        assert_eq!(url("javascript:alert(1)").safe_url(), None);
        assert_eq!(url("file:///etc/passwd").safe_url(), None);
        assert_eq!(url("https://exa mple.com").safe_url(), None);
        assert_eq!(url("https://").safe_url(), None);
        assert_eq!(url("").safe_url(), None);
        let slide = Link { kind: LinkKind::Slide, target: "s2".into() };
        assert_eq!(slide.safe_url(), None);
    }
}

#[cfg(test)]
mod chart_tests {
    use super::*;

    #[test]
    fn series_color_accepts_hex_and_falls_back_to_palette() {
        let mut s = ChartSeries { name: "a".into(), values: vec![], color: Some("#10b981".into()) };
        assert_eq!(s.color_at(0, &[]), "10B981");
        s.color = Some("red".into());
        assert_eq!(s.color_at(0, &[]), CHART_PALETTE[0]);
        s.color = None;
        assert_eq!(s.color_at(2, &[]), CHART_PALETTE[2]);
        let deck_pal: Vec<String> = vec!["AAAAAA".into(), "BBBBBB".into(), "CCCCCC".into()];
        assert_eq!(s.color_at(1, &deck_pal), "BBBBBB");
        assert_eq!(s.color_at(4, &deck_pal), "BBBBBB");
    }

    #[test]
    fn chart_range_includes_zero_and_widens_flat_data() {
        let s = vec![ChartSeries { name: "a".into(), values: vec![-2.0, 5.0], color: None }];
        assert_eq!(chart_range(&s), (-2.0, 5.0));
        let flat = vec![ChartSeries { name: "a".into(), values: vec![0.0, 0.0], color: None }];
        assert_eq!(chart_range(&flat), (0.0, 1.0));
    }

    #[test]
    fn chart_content_reads_from_json() {
        let c: ObjectContent = serde_json::from_value(serde_json::json!({
            "kind": "chart", "style": "pie", "labels": ["a"], "series": [{"name": "s", "values": [1]}]
        }))
        .unwrap();
        match c {
            ObjectContent::Chart { style, title, labels, series } => {
                assert_eq!(style, ChartStyle::Pie);
                assert!(title.is_none());
                assert_eq!(labels, vec!["a".to_string()]);
                assert_eq!(series[0].values, vec![1.0]);
            }
            _ => panic!("expected a chart"),
        }
    }
}
