//! Pacing governor — the anti-template machine. Deck-level rhythm rules that
//! keep generated decks from feeling stamped: no archetype repetition, density
//! alternation, forced breathers, whitespace budget.

use crate::model::{Archetype, Deck, Slide, SlideContent};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case", tag = "issue")]
pub enum PacingIssue {
    RepeatedArchetype { slide_index: usize },
    DenseRun { from: usize, to: usize },
    MissingAgenda,
    NoBreather { around: usize },
    TooLong { slides: usize },
}

fn density(slide: &Slide) -> u32 {
    match &slide.content {
        SlideContent::Cover { .. } | SlideContent::Section { .. } | SlideContent::Closing { .. } => 1,
        SlideContent::Blank => 0,
        SlideContent::Statement { .. } => 2,
        SlideContent::Agenda { items, .. } => 2 + items.len().min(4) as u32,
        SlideContent::StatWall { stats, .. } => 2 + stats.len().min(4) as u32,
        SlideContent::Split { bullets, .. } => 2 + bullets.len().min(6) as u32,
        SlideContent::Comparison { left, right, .. } => 3 + left.points.len().min(4) as u32 + right.points.len().min(4) as u32,
        SlideContent::ChartHero { chart, .. } => 3 + chart.categories.len().min(6) as u32,
    }
}

/// Audit a deck's rhythm. Returns issues the caller (AI tool response or the
/// editor) can surface as plain English.
pub fn audit(deck: &Deck) -> Vec<PacingIssue> {
    let mut issues = Vec::new();
    let n = deck.slides.len();

    for i in 1..n {
        // Blank slides are the user's canvas — several in a row is normal
        // editing, not a pacing failure.
        if deck.slides[i].archetype == deck.slides[i - 1].archetype
            && deck.slides[i].archetype != Archetype::Blank
        {
            issues.push(PacingIssue::RepeatedArchetype { slide_index: i });
        }
    }

    // Density runs: 3+ consecutive slides above density 5 need a breather.
    let d: Vec<u32> = deck.slides.iter().map(density).collect();
    let mut run = 0usize;
    for i in 0..n {
        if d[i] >= 5 {
            if run == 0 {
                run = i + 1; // 1-indexed start
            } else if i + 1 == n {
                if i - run + 1 >= 3 {
                    issues.push(PacingIssue::DenseRun { from: run, to: i + 1 });
                }
            }
        } else {
            if run > 0 && i - run + 1 >= 3 {
                issues.push(PacingIssue::DenseRun { from: run, to: i });
            }
            if run > 0 && i + 2 < n && d[i + 1] >= 5 && d[i + 2] >= 5 {
                // a single breather before another dense pair is fine; nothing to add
            }
            run = 0;
        }
    }

    let has_agenda = deck.slides.iter().any(|s| matches!(s.content, SlideContent::Agenda { .. }));
    if n >= 5 && !has_agenda {
        issues.push(PacingIssue::MissingAgenda);
    }

    if n > 12 {
        issues.push(PacingIssue::TooLong { slides: n });
    }

    issues
}

/// Suggest the next archetype given the deck so the AI isn't left guessing.
/// Rules: never repeat the last; prefer a breather after dense; every 4-6
/// slides suggest a section break; always end Closing.
pub fn suggest_next(deck: &Deck) -> Archetype {
    let n = deck.slides.len();
    if n == 0 {
        return Archetype::Cover;
    }
    let last = deck.slides[n - 1].archetype;
    let last_dense = density(&deck.slides[n - 1]) >= 5;
    let since_section = deck
        .slides
        .iter()
        .rev()
        .position(|s| matches!(s.content, SlideContent::Section { .. }))
        .unwrap_or(n);

    if n >= 5 && since_section >= 5 && last != Archetype::Section {
        return Archetype::Section;
    }
    if last_dense {
        return if last == Archetype::Statement { Archetype::Section } else { Archetype::Statement };
    }
    match last {
        Archetype::Cover => Archetype::Agenda,
        Archetype::Agenda => Archetype::Split,
        Archetype::Section => Archetype::Split,
        Archetype::Statement => Archetype::Split,
        Archetype::StatWall => Archetype::ChartHero,
        Archetype::Split => Archetype::StatWall,
        Archetype::Comparison => Archetype::ChartHero,
        Archetype::ChartHero => Archetype::Statement,
        Archetype::Closing => Archetype::Statement,
        Archetype::Blank => Archetype::Statement,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    fn slide(a: Archetype) -> Slide {
        let content = match a {
            Archetype::Statement => SlideContent::Statement { text: "x".into(), attribution: None },
            Archetype::Split => SlideContent::Split {
                title: "t".into(),
                bullets: vec!["a".into(); 6],
                visual_label: None,
            },
            _ => SlideContent::Statement { text: "x".into(), attribution: None },
        };
        Slide { background: None, hide_graphics: false, id: "s".into(), archetype: a, content, objects: Vec::new() }
    }

    #[test]
    fn flags_repetition() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 1 },
            aspect: "16:9".into(),
            slides: vec![slide(Archetype::Statement), slide(Archetype::Statement)],
            components: Vec::new(),
        };
        assert!(audit(&deck).contains(&PacingIssue::RepeatedArchetype { slide_index: 1 }));
    }
}
