#![allow(clippy::needless_doctest_main)]
//! Deck model. The single source of truth shared by the Flutter app (via FFI
//! JSON), the Worker (via wasm JSON), and the MCP tool schema (worker/src/tools.ts).
//!
//! The AI only ever produces this model — never coordinates. Pixels are the
//! layout solver's job (see layout.rs).

use serde::{Deserialize, Serialize};

pub const SLIDE_W: f64 = 1280.0;
pub const SLIDE_H: f64 = 720.0;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Deck {
    pub id: String,
    pub title: String,
    pub version: u64,
    pub dna: Dna,
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
}

// ---------------------------------------------------------------------------
// Vector overlay layer
// ---------------------------------------------------------------------------

/// A positioned vector object in the 1280x720 design space. `points` are
/// normalized (0..1) bbox-local coordinates for polygon/path presets, so
/// geometry survives resizes.
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
    #[serde(default)]
    pub closed: bool,
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
}

impl DnaFamily {
    pub fn label(&self) -> &'static str {
        match self {
            DnaFamily::SwissEditorial => "Swiss editorial",
            DnaFamily::Cinematic => "Cinematic",
            DnaFamily::MagazineSerif => "Magazine serif",
        }
    }
}
