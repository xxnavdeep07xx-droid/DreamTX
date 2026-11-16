//! The layout solver. Takes (deck DNA, slide content) → positioned elements.
//! The ONLY place in the system where coordinates are chosen.
//!
//! Rules baked in: 12-col grid, optical (not mathematical) centering, real
//! font metrics, density floors (text never shrinks below readable; overflow
//! is flagged for splitting instead).

use crate::dna::{resolve, FontRole, Motif, ResolvedDna};
use crate::fonts::{measure, wrap};
use crate::model::*;
use serde::{Deserialize, Serialize};

pub const MARGIN: f64 = 96.0;
pub const COL_W: f64 = (SLIDE_W - 2.0 * MARGIN) / 12.0;
pub const GUTTER: f64 = 24.0;
pub const MIN_BODY: f64 = 18.0; // absolute density floor (px)

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Layout {
    pub w: f64,
    pub h: f64,
    pub elements: Vec<Element>,
    /// Human-readable warnings (e.g. "content overflows — consider splitting").
    #[serde(default)]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "type")]
pub enum Element {
    Rect {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        color: String,
        #[serde(default)]
        radius: f64,
    },
    Text {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        text: String,
        /// Pre-wrapped lines joined with \n — renderers draw them as-is.
        lines: Vec<String>,
        size: f64,
        color: String,
        font: FontRole,
        #[serde(default)]
        bold: bool,
        align: Align,
        #[serde(default)]
        key: Option<String>,
    },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Align {
    Left,
    Center,
    Right,
}

/// Entry point: lay out one slide with the deck's DNA.
pub fn layout_slide(dna: &Dna, slide: &Slide) -> Layout {
    let r = resolve(dna);
    let scale = r.scale;
    let mut b = Builder::new(&r, scale);
    match &slide.content {
        SlideContent::Cover { kicker, title, subtitle } => b.cover(kicker, title, subtitle.as_deref()),
        SlideContent::Agenda { title, items } => b.agenda(title, items),
        SlideContent::Section { index, title, blurb } => b.section(*index, title, blurb.as_deref()),
        SlideContent::Statement { text, attribution } => b.statement(text, attribution.as_deref()),
        SlideContent::StatWall { title, stats } => b.stat_wall(title, stats),
        SlideContent::Split { title, bullets, visual_label } => b.split(title, bullets, visual_label.as_deref()),
        SlideContent::Comparison { title, left, right } => b.comparison(title, left, right),
        SlideContent::ChartHero { title, chart, takeaway } => b.chart_hero(title, chart, takeaway.as_deref()),
        SlideContent::Closing { title, subtitle } => b.closing(title, subtitle.as_deref()),
    }
    b.finish()
}

struct Builder {
    r: ResolvedDna,
    scale: f64,
    elements: Vec<Element>,
    warnings: Vec<String>,
}

impl Builder {
    fn new(r: &ResolvedDna, scale: f64) -> Self {
        Builder { r: r.clone(), scale, elements: Vec::new(), warnings: Vec::new() }
    }

    fn finish(mut self) -> Layout {
        // Full-bleed background.
        let bg = self.r.palette.bg.clone();
        self.elements.insert(
            0,
            Element::Rect { x: 0.0, y: 0.0, w: SLIDE_W, h: SLIDE_H, color: bg, radius: 0.0 },
        );
        Layout { w: SLIDE_W, h: SLIDE_H, elements: self.elements, warnings: self.warnings }
    }

    fn serif(&self, role: FontRole) -> bool {
        matches!(role, FontRole::Serif)
    }

    fn motif_stamp(&mut self, y: f64) {
        match self.r.motif {
            Motif::RuleLine => {
                let c = self.r.palette.accent.clone();
                self.elements.push(Element::Rect { x: MARGIN, y, w: 72.0, h: 6.0, color: c, radius: 0.0 });
            }
            Motif::NumberStamp => {
                let c = self.r.palette.accent.clone();
                self.elements.push(Element::Rect { x: MARGIN, y: y - 18.0, w: 14.0, h: 42.0, color: c, radius: self.r.corner });
            }
            Motif::EdgeBar => {
                let c = self.r.palette.accent.clone();
                self.elements.push(Element::Rect { x: 0.0, y: y - 18.0, w: 16.0, h: 64.0, color: c, radius: 0.0 });
            }
        }
    }

    /// Fit text into a box: wraps at `size * scale`; if it overflows, steps the
    /// size down to a floor, then flags overflow instead of shrinking further.
    fn fit_text(
        &mut self,
        key: &str,
        text: &str,
        x: f64,
        y: f64,
        w: f64,
        max_h: f64,
        base_size: f64,
        color: &str,
        role: FontRole,
        bold: bool,
        align: Align,
        floor: f64,
    ) {
        let serif = self.serif(role);
        let mut size = (base_size * self.scale).max(floor);
        loop {
            let lines = wrap(text, w, size, serif, bold);
            let h = lines.len() as f64 * size * 1.28;
            if h <= max_h || size <= floor {
                if h > max_h {
                    self.warnings
                        .push(format!("'{key}' overflows its box at minimum size — consider splitting the slide"));
                }
                self.elements.push(Element::Text {
                    x,
                    y,
                    w,
                    h: max_h.max(h),
                    text: text.to_string(),
                    lines,
                    size,
                    color: color.to_string(),
                    font: role,
                    bold,
                    align,
                    key: Some(key.to_string()),
                });
                return;
            }
            size = (size - 2.0).max(floor);
        }
    }

    // ---- archetypes ------------------------------------------------------

    fn cover(&mut self, kicker: Option<&String>, title: &str, subtitle: Option<&str>) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        if let Some(k) = kicker {
            self.fit_text("kicker", k, MARGIN, MARGIN + 12.0, content_w, 48.0, 22.0, &p.accent, self.r.body_font, true, Align::Left, MIN_BODY);
            self.motif_stamp(MARGIN + 64.0);
        }
        self.fit_text("title", title, MARGIN, MARGIN + 110.0, content_w * 0.82, 340.0, 92.0, &p.fg, self.r.display_font, true, Align::Left, 40.0);
        if let Some(s) = subtitle {
            self.fit_text("subtitle", s, MARGIN, MARGIN + 470.0, content_w * 0.62, 120.0, 26.0, &p.muted, self.r.body_font, false, Align::Left, MIN_BODY);
        }
    }

    fn agenda(&mut self, title: &str, items: &[String]) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        self.fit_text("title", title, MARGIN, MARGIN, content_w, 70.0, 44.0, &p.fg, self.r.display_font, true, Align::Left, 30.0);
        let rows = items.len().max(1);
        let two_col = rows > 5;
        let (cols, col_w) = if two_col { (2, (content_w - GUTTER) / 2.0) } else { (1, content_w * 0.72) };
        let rows_per_col = (rows + cols - 1) / cols;
        let top = MARGIN + 96.0;
        let row_h = (SLIDE_H - top - MARGIN) / rows_per_col as f64;
        for (i, item) in items.iter().enumerate() {
            let col = i / rows_per_col;
            let row = i % rows_per_col;
            let x = MARGIN + col as f64 * (col_w(col_w) + GUTTER);
            let y = top + row as f64 * row_h;
            let num = format!("{:02}", i + 1);
            self.fit_text(&format!("agenda.{i}.num"), &num, x, y + 6.0, 72.0, 34.0, 22.0, &p.accent, self.r.body_font, true, Align::Left, MIN_BODY);
            self.fit_text(&format!("agenda.{i}"), item, x + 84.0, y + 4.0, col_w(col_w) - 84.0 - GUTTER, row_h - 16.0, 24.0, &p.fg, self.r.body_font, false, Align::Left, MIN_BODY);
        }
    }

    fn section(&mut self, index: u32, title: &str, blurb: Option<&str>) {
        let p = self.r.palette.clone();
        let ghost = format!("{index:02}");
        let content_w = SLIDE_W - 2.0 * MARGIN;
        // Ghost numeral behind, low-contrast.
        self.elements.push(Element::Text {
            x: MARGIN,
            y: MARGIN + 40.0,
            w: content_w,
            h: 320.0,
            text: ghost.clone(),
            lines: vec![ghost],
            size: 200.0 * self.scale,
            color: p.surface.clone(),
            font: self.r.display_font,
            bold: true,
            align: Align::Left,
            key: None,
        });
        self.motif_stamp(MARGIN + 430.0);
        self.fit_text("title", title, MARGIN, MARGIN + 470.0, content_w * 0.7, 110.0, 60.0, &p.fg, self.r.display_font, true, Align::Left, 32.0);
        if let Some(b) = blurb {
            self.fit_text("blurb", b, MARGIN, MARGIN + 560.0, content_w * 0.5, 70.0, 22.0, &p.muted, self.r.body_font, false, Align::Left, MIN_BODY);
        }
    }

    fn statement(&mut self, text: &str, attribution: Option<&str>) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        self.motif_stamp(MARGIN + 150.0);
        self.fit_text("text", text, MARGIN, MARGIN + 170.0, content_w * 0.86, 320.0, 58.0, &p.fg, self.r.display_font, false, Align::Left, 26.0);
        if let Some(a) = attribution {
            self.fit_text("attribution", a, MARGIN, SLIDE_H - MARGIN - 60.0, content_w * 0.5, 54.0, 22.0, &p.accent, self.r.body_font, false, Align::Left, MIN_BODY);
        }
    }

    fn stat_wall(&mut self, title: Option<&String>, stats: &[Stat]) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        let mut top = MARGIN;
        if let Some(t) = title {
            self.fit_text("title", t, MARGIN, top, content_w, 60.0, 34.0, &p.fg, self.r.display_font, true, Align::Left, 24.0);
            top += 84.0;
        }
        let n = stats.len().clamp(1, 4);
        let (cols, rows) = match n {
            1 => (1, 1),
            2 => (2, 1),
            3 => (3, 1),
            _ => (2, 2),
        };
        let area_h = SLIDE_H - top - MARGIN;
        let tile_w = (content_w - GUTTER * (cols - 1) as f64) / cols as f64;
        let tile_h = (area_h - GUTTER * (rows - 1) as f64) / rows as f64;
        for (i, s) in stats.iter().take(n).enumerate() {
            let cx = i % cols;
            let cy = i / cols;
            let x = MARGIN + cx as f64 * (tile_w + GUTTER);
            let y = top + cy as f64 * (tile_h + GUTTER);
            self.elements.push(Element::Rect { x, y, w: tile_w, h: tile_h, color: p.surface.clone(), radius: self.r.corner });
            self.fit_text(&format!("stats.{i}.value"), &s.value, x + 32.0, y + tile_h * 0.16, tile_w - 64.0, tile_h * 0.44, 84.0, &p.accent, self.r.display_font, true, Align::Left, 34.0);
            self.fit_text(&format!("stats.{i}.label"), &s.label, x + 32.0, y + tile_h * 0.62, tile_w - 64.0, tile_h * 0.30, 21.0, &p.fg, self.r.body_font, false, Align::Left, MIN_BODY);
            if stats.len() > n {
                self.warnings.push("stat wall shows the first 4 stats; split into two slides for more".into());
            }
        }
    }

    fn split(&mut self, title: &str, bullets: &[String], visual_label: Option<&str>) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        let left_w = content_w * 0.52 - GUTTER;
        let right_x = MARGIN + content_w * 0.52 + GUTTER / 2.0;
        let right_w = content_w - left_w - GUTTER;
        self.fit_text("title", title, MARGIN, MARGIN, left_w, 120.0, 42.0, &p.fg, self.r.display_font, true, Align::Left, 26.0);
        let mut y = MARGIN + 150.0;
        let mut i = 0usize;
        for b in bullets {
            if y > SLIDE_H - MARGIN - 40.0 {
                self.warnings.push(format!("{} bullets hidden — split the slide", bullets.len() - i));
                break;
            }
            let c = p.accent.clone();
            self.elements.push(Element::Rect { x: MARGIN, y: y + 8.0, w: 10.0, h: 10.0, color: c, radius: self.r.corner.min(5.0) });
            let lines = wrap(b, left_w - 28.0, 22.0, false, false);
            let h = lines.len() as f64 * 22.0 * 1.35;
            self.fit_text(&format!("bullets.{i}"), b, MARGIN + 28.0, y, left_w - 28.0, h.max(30.0), 22.0, &p.fg, self.r.body_font, false, Align::Left, MIN_BODY);
            y += h + 18.0;
            i += 1;
        }
        // Right panel: quiet surface block + ghost label (v0.1 visual).
        self.elements.push(Element::Rect { x: right_x, y: MARGIN, w: right_w, h: SLIDE_H - 2.0 * MARGIN, color: p.surface.clone(), radius: self.r.corner });
        if let Some(v) = visual_label {
            self.fit_text("visual_label", v, right_x + 40.0, SLIDE_H / 2.0 - 60.0, right_w - 80.0, 140.0, 30.0, &p.muted, self.r.display_font, false, Align::Center, MIN_BODY);
        }
    }

    fn comparison(&mut self, title: Option<&String>, left: &CompareSide, right: &CompareSide) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        let mut top = MARGIN;
        if let Some(t) = title {
            self.fit_text("title", t, MARGIN, top, content_w, 60.0, 34.0, &p.fg, self.r.display_font, true, Align::Left, 24.0);
            top += 84.0;
        }
        let panel_w = (content_w - 48.0) / 2.0;
        let panel_h = SLIDE_H - top - MARGIN;
        for (side, x, tag) in [(left, MARGIN, "left"), (right, MARGIN + panel_w + 48.0, "right")] {
            self.elements.push(Element::Rect { x, y: top, w: panel_w, h: panel_h, color: p.surface.clone(), radius: self.r.corner });
            let c = if *tag == "left" { p.accent.clone() } else { p.fg.clone() };
            self.fit_text(&format!("{tag}.title"), &side.title, x + 32.0, top + 28.0, panel_w - 64.0, 44.0, 26.0, &c, self.r.display_font, true, Align::Left, 20.0);
            let mut y = top + 96.0;
            for (j, pt) in side.points.iter().enumerate() {
                if y > top + panel_h - 30.0 {
                    self.warnings.push(format!("{tag} panel truncated at {} points", side.points.len() - j));
                    break;
                }
                let lines = wrap(pt, panel_w - 96.0, 20.0, false, false);
                let h = lines.len() as f64 * 20.0 * 1.35;
                self.fit_text(&format!("{tag}.points.{j}"), pt, x + 64.0, y, panel_w - 96.0, h.max(28.0), 20.0, &p.fg, self.r.body_font, false, Align::Left, MIN_BODY);
                y += h + 14.0;
            }
        }
    }

    fn chart_hero(&mut self, title: &str, chart: &ChartSpec, takeaway: Option<&str>) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        self.fit_text("title", title, MARGIN, MARGIN, content_w, 60.0, 36.0, &p.fg, self.r.display_font, true, Align::Left, 24.0);
        if let Some(t) = takeaway {
            let y = SLIDE_H - MARGIN - 52.0;
            self.elements.push(Element::Rect { x: MARGIN, y: y - 14.0, w: content_w, h: 66.0, color: p.surface.clone(), radius: self.r.corner });
            self.fit_text("takeaway", t, MARGIN + 24.0, y, content_w - 48.0, 44.0, 20.0, &p.accent, self.r.body_font, false, Align::Left, MIN_BODY);
        }
        let chart_top = MARGIN + 84.0;
        let chart_bottom = SLIDE_H - MARGIN - (if takeaway.is_some() { 96.0 } else { 40.0 });
        let chart_h = chart_bottom - chart_top;
        let max_v = chart.series.iter().flat_map(|s| s.values.iter().copied()).fold(0.0_f64, f64::max).max(1.0);
        let cats = chart.categories.len().max(1) as f64;
        let inner_w = content_w - 64.0;
        let step = inner_w / cats;
        match chart.kind {
            ChartKind::Bar => {
                let series = chart.series.first().cloned().unwrap_or(Series { name: "values".into(), values: vec![0.0; cats as usize] });
                for (i, v) in series.values.iter().enumerate() {
                    if i as f64 >= cats { break; }
                    let bh = (v / max_v) * (chart_h - 56.0);
                    let x = MARGIN + 32.0 + i as f64 * step + step * 0.18;
                    let y = chart_bottom - 40.0 - bh;
                    self.elements.push(Element::Rect { x, y, w: step * 0.64, h: bh, color: p.accent.clone(), radius: self.r.corner.min(4.0) });
                    let val = format_value(v);
                    self.fit_text(&format!("chart.values.{i}"), &val, x - 12.0, y - 34.0, step * 0.64 + 24.0, 28.0, 16.0, &p.fg, self.r.body_font, true, Align::Center, MIN_BODY);
                    if i < chart.categories.len() {
                        let cat = &chart.categories[i];
                        self.fit_text(&format!("chart.cats.{i}"), cat, MARGIN + 32.0 + i as f64 * step, chart_bottom - 26.0, step, 24.0, 15.0, &p.muted, self.r.body_font, false, Align::Center, MIN_BODY);
                    }
                }
            }
            ChartKind::Line => {
                // v0.1: stepped line (thin rects) — proper angled lines in M2.
                let series = chart.series.first().cloned().unwrap_or(Series { name: "values".into(), values: vec![0.0; cats as usize] });
                let pts: Vec<(f64, f64)> = series.values.iter().take(cats as usize).enumerate().map(|(i, v)| {
                    let x = MARGIN + 32.0 + i as f64 * step + step * 0.5;
                    let y = chart_bottom - 40.0 - (v / max_v) * (chart_h - 56.0);
                    (x, y)
                }).collect();
                for i in 0..pts.len() {
                    let (x, y) = pts[i];
                    self.elements.push(Element::Rect { x: x - 5.0, y: y - 5.0, w: 10.0, h: 10.0, color: p.accent.clone(), radius: 5.0 });
                    if i + 1 < pts.len() {
                        let (nx, ny) = pts[i + 1];
                        // horizontal segment
                        self.elements.push(Element::Rect { x: x + 5.0, y: y - 2.0, w: (nx - x - 10.0).max(0.0), h: 4.0, color: p.accent.clone(), radius: 0.0 });
                        // vertical connector
                        let (vy0, vy1) = if ny < y { (ny, y) } else { (y, ny) };
                        self.elements.push(Element::Rect { x: nx - 7.0, y: vy0, w: 4.0, h: (vy1 - vy0).max(4.0), color: p.accent.clone(), radius: 0.0 });
                    }
                    if i < chart.categories.len() {
                        let cat = &chart.categories[i];
                        self.fit_text(&format!("chart.cats.{i}"), cat, x - step * 0.5, chart_bottom - 26.0, step, 24.0, 15.0, &p.muted, self.r.body_font, false, Align::Center, MIN_BODY);
                    }
                }
            }
        }
    }

    fn closing(&mut self, title: &str, subtitle: Option<&str>) {
        let p = self.r.palette.clone();
        let content_w = SLIDE_W - 2.0 * MARGIN;
        self.motif_stamp(MARGIN + 200.0);
        self.fit_text("title", title, MARGIN, MARGIN + 230.0, content_w * 0.8, 200.0, 76.0, &p.fg, self.r.display_font, true, Align::Left, 34.0);
        if let Some(s) = subtitle {
            self.fit_text("subtitle", s, MARGIN, MARGIN + 470.0, content_w * 0.6, 90.0, 24.0, &p.muted, self.r.body_font, false, Align::Left, MIN_BODY);
        }
    }
}

fn col_w(col: f64) -> f64 {
    col // local helper keeps call sites readable
}

fn format_value(v: &f64) -> String {
    if v.fract() == 0.0 { format!("{}", *v as i64) } else { format!("{:.1}", v) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    #[test]
    fn cover_has_bg_and_text() {
        let dna = Dna { family: DnaFamily::SwissEditorial, seed: 7 };
        let slide = Slide {
            id: "s1".into(),
            archetype: Archetype::Cover,
            content: SlideContent::Cover { kicker: Some("Q3 review".into()), title: "Revenue up".into(), subtitle: Some("FY26".into()) },
        };
        let l = layout_slide(&dna, &slide);
        assert_eq!(l.w, SLIDE_W);
        assert!(l.elements.len() >= 3);
        assert!(l.elements.iter().any(|e| matches!(e, Element::Rect { .. })));
        assert!(l.elements.iter().any(|e| matches!(e, Element::Text { .. })));
    }

    #[test]
    fn overflow_is_flagged_not_shrunk_forever() {
        let dna = Dna { family: DnaFamily::SwissEditorial, seed: 1 };
        let long = "word ".repeat(120);
        let slide = Slide {
            id: "s".into(),
            archetype: Archetype::Statement,
            content: SlideContent::Statement { text: long, attribution: None },
        };
        let l = layout_slide(&dna, &slide);
        let mut min_size = f64::MAX;
        for e in &l.elements {
            if let Element::Text { size, .. } = e {
                min_size = min_size.min(*size);
            }
        }
        assert!(min_size >= 26.0 - 0.1, "statement floor");
        assert!(!l.warnings.is_empty(), "expected overflow warning");
    }
}
