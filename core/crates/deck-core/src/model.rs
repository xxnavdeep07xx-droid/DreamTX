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
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Slide {
    pub id: String,
    pub archetype: Archetype,
    #[serde(flatten)]
    pub content: SlideContent,
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
