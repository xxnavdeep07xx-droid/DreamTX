//! Minimal PDF 1.4 writer. v0.1 is Latin-first: text maps to base-14 fonts
//! (Helvetica/Times) in WinAnsi; non-Latin-1 chars are transliterated or
//! dropped (M2 ships embedded subset fonts + full Unicode).
//!
//! Objects that carry `content` (text boxes, images, icons, media, tables)
//! render as real content in `slide.objects` Z-order: rich text boxes with
//! runs/paragraph styles, images embedded as FlateDecode (or DCTDecode
//! passthrough for JPEG) XObjects with alpha as an SMask, tables as grid +
//! cell text, icons and media as clean cards. A missing image asset falls
//! back to a clean placeholder box.

use crate::command::object_polygon;
use crate::export::{ExportImage, doc_paragraphs, para_anchor_at, run_pieces, utf16_slice};
use crate::model::{
    chart_range, ChartSeries, ChartStyle, Deck, Fill, LinkKind, ObjectContent, Shape, TextDoc, SLIDE_H,
    SLIDE_W, deck_dims,
};
use crate::layout::{layout_slide, Element};
use crate::fonts;
use std::collections::BTreeMap;
use std::io::Write as _;

/// Classic 16:9 page for crispness in viewers; everything in points. The
/// design→page scale is uniform (KY) in every aspect, so the page WIDTH is
/// the only per-deck value; PW/PH/KX below define the classic reference.
const PW: f64 = 960.0;
const PH: f64 = 540.0;
const KX: f64 = PW / SLIDE_W;
const KY: f64 = PH / SLIDE_H;

/// The app's text-box base size (kTextBoxBaseSize) — the export default.
const BASE_FONT_PX: f64 = 32.0;
/// The text box painter's design-space insets.
const BOX_PAD_X: f64 = 14.0;
const BOX_PAD_Y: f64 = 10.0;

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

/// A resolved tap-action for a page's link annotation.
enum PdfLink {
    /// External web link.
    Uri(String),
    /// Jump to the page at this slide index.
    Page(usize),
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

fn set_stroke(c: &str) -> String {
    let v = u32::from_str_radix(c.trim_start_matches('#'), 16).unwrap_or(0);
    let (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    format!("{:.3} {:.3} {:.3} RG", r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0)
}

fn hex_rgb(c: &str) -> (f64, f64, f64) {
    let v = u32::from_str_radix(c.trim_start_matches('#'), 16).unwrap_or(0);
    (
        ((v >> 16) & 0xFF) as f64 / 255.0,
        ((v >> 8) & 0xFF) as f64 / 255.0,
        (v & 0xFF) as f64 / 255.0,
    )
}

fn lerp_color(a: (f64, f64, f64), b: (f64, f64, f64), t: f64) -> String {
    format!(
        "{:.3} {:.3} {:.3} rg",
        a.0 + (b.0 - a.0) * t,
        a.1 + (b.1 - a.1) * t,
        a.2 + (b.2 - a.2) * t
    )
}

/// Design coords (1280x720, y-down) → PDF page coords (points, y-up).
fn tf(px: f64, py: f64) -> (f64, f64) {
    (px * KX, PH - py * KY)
}

fn path_ops(pts: &[(f64, f64)], close: bool) -> String {
    let mut s = String::new();
    for (i, &(px, py)) in pts.iter().enumerate() {
        let (x, y) = tf(px, py);
        if i == 0 {
            s.push_str(&format!("\n{:.2} {:.2} m", x, y));
        } else {
            s.push_str(&format!(" {:.2} {:.2} l", x, y));
        }
    }
    if close && pts.len() > 2 {
        s.push_str(" h");
    }
    s
}

/// Register (dedup) an ExtGState for a given alpha; returns the gs name.
fn gs_for(alpha: f64, set: &mut Vec<(f64, String)>) -> String {
    let a = ((alpha * 20.0).round() / 20.0).clamp(0.0, 1.0);
    for (v, name) in set.iter() {
        if (*v - a).abs() < 1e-6 {
            return name.clone();
        }
    }
    let name = format!("gs{}", set.len());
    set.push((a, name.clone()));
    name
}

/// Rotate polygon points around a center (screen clockwise, degrees).
fn rot_points(poly: &[(f64, f64)], cx: f64, cy: f64, deg: f64) -> Vec<(f64, f64)> {
    let r = deg.to_radians();
    let (c, s) = (r.cos(), r.sin());
    poly.iter()
        .map(|&(px, py)| {
            let (dx, dy) = (px - cx, py - cy);
            (cx + dx * c - dy * s, cy + dx * s + dy * c)
        })
        .collect()
}

/// One vector overlay object as PDF ops. Gradients render as clipped color
/// strips/rings (no shading objects needed — robust everywhere).
fn object_pdf(o: &Shape, alphas: &mut Vec<(f64, String)>) -> String {
    let mut ops = String::new();
    let is_donut = o.preset == "donut" && o.points.is_none();
    let has_holes = o.holes.as_ref().is_some_and(|h| !h.is_empty());
    let mut poly = object_polygon(o);
    if is_donut {
        // hole contour: inner ellipse at 45% radius
        let inner: Vec<(f64, f64)> = {
            let cx = o.x + o.w / 2.0;
            let cy = o.y + o.h / 2.0;
            (0..24)
                .map(|i| {
                    let a = i as f64 * std::f64::consts::TAU / 24.0;
                    (cx + o.w * 0.225 * a.cos(), cy + o.h * 0.225 * a.sin())
                })
                .collect()
        };
        // donut keeps rotation too
        let (cx, cy) = (o.x + o.w / 2.0, o.y + o.h / 2.0);
        let poly2 = rot_points(&poly, cx, cy, o.rotation);
        let inner2 = rot_points(&inner, cx, cy, o.rotation);
        // even-odd fill with hole
        let fill_ops = match &o.fill {
            Fill::None => return format!("\nq {} W n{} S Q", path_ops(&poly2, false), String::new()),
            Fill::Solid { color } => format!("{}{}{} f*", set_fill(color), path_ops(&poly2, true), path_ops(&inner2, true)),
            Fill::LinearGradient { from, .. } => format!("{}{}{} f*", set_fill(from), path_ops(&poly2, true), path_ops(&inner2, true)),
            Fill::RadialGradient { from, .. } => format!("{}{}{} f*", set_fill(from), path_ops(&poly2, true), path_ops(&inner2, true)),
        };
        ops.push_str(&fill_ops);
        return ops;
    }
    let (cx, cy) = (o.x + o.w / 2.0, o.y + o.h / 2.0);
    if o.rotation != 0.0 {
        poly = rot_points(&poly, cx, cy, o.rotation);
    }
    let open = crate::shapes::preset_info(&o.preset).map(|i| i.open).unwrap_or(false) || !o.closed && o.points.is_some();

    // absolute coords for hole contours (normalized like `points`)
    let hole_paths: Vec<Vec<(f64, f64)>> = o
        .holes
        .as_deref()
        .unwrap_or(&[])
        .iter()
        .map(|h| {
            h.iter()
                .map(|p| {
                    let mut pt = (o.x + p.x * o.w, o.y + p.y * o.h);
                    if o.rotation != 0.0 {
                        let r = rot_points(&[pt], cx, cy, o.rotation);
                        pt = r[0];
                    }
                    pt
                })
                .collect()
        })
        .collect();

    // ---- shadow (offset translucent copy) ------------------------------------
    if let Some(sh) = &o.effects.shadow {
        let shifted: Vec<(f64, f64)> = poly.iter().map(|&(px, py)| (px + sh.dx, py + sh.dy)).collect();
        let gs = gs_for(sh.opacity * o.opacity, alphas);
        let sh_fill = set_fill(&sh.color);
        let sh_path = path_ops(&shifted, true);
        ops.push_str(&format!("\nq /{gs} gs {sh_fill} {sh_path} h f Q"));
    }
    // ---- glow (layered translucent strokes) ---------------------------------
    if let Some(gl) = &o.effects.glow {
        let gs = gs_for(0.3 * o.opacity, alphas);
        let gl_stroke = set_stroke(&gl.color);
        let gl_path = path_ops(&poly, open);
        for k in 1..=3 {
            let w = gl.blur * 0.35 * k as f64 * KX;
            ops.push_str(&format!("\nq /{gs} gs {gl_stroke} {w:.2} w {gl_path} S Q"));
        }
    }

    // ---- fill -----------------------------------------------------------------
    if !open {
        if has_holes {
            // even-odd fill: outer + holes in one path
            let color = match &o.fill {
                Fill::Solid { color } => color.clone(),
                Fill::LinearGradient { from, .. } => from.clone(),
                Fill::RadialGradient { from, .. } => from.clone(),
                Fill::None => String::new(),
            };
            if !color.is_empty() {
                let mut combined = path_ops(&poly, true);
                for h in &hole_paths {
                    combined.push_str(&path_ops(h, true));
                }
                if o.opacity < 0.999 {
                    let gs = gs_for(o.opacity, alphas);
                    ops.push_str(&format!("\nq /{gs} gs {} {combined} f* Q", set_fill(&color)));
                } else {
                    ops.push_str(&format!("\n{} {combined} f*", set_fill(&color)));
                }
            }
        } else {
            match &o.fill {
            Fill::None => {}
            Fill::Solid { color } => {
                let body = format!("{} {} h f", set_fill(color), path_ops(&poly, false));
                if o.opacity < 0.999 {
                    let gs = gs_for(o.opacity, alphas);
                    ops.push_str(&format!("\nq /{gs} gs {body} Q"));
                } else {
                    ops.push_str(&format!("\n{body}"));
                }
            }
            Fill::LinearGradient { angle, from, to } => {
                let (fa, fb) = (hex_rgb(from), hex_rgb(to));
                let th = angle.to_radians();
                let (ax, ay) = (th.cos(), th.sin());
                let (px_, py_) = (-ay, ax);
                let l = o.w.abs() * ax.abs() + o.h.abs() * ay.abs();
                let m = o.w + o.h;
                let n = 24;
                ops.push_str(&format!("\nq {} W n", path_ops(&poly, true)));
                for i in 0..n {
                    let t0 = -l / 2.0 + l * i as f64 / n as f64 - 1.0;
                    let t1 = -l / 2.0 + l * (i + 1) as f64 / n as f64 + 1.0;
                    let c0 = [
                        (cx + ax * t0 + px_ * m, cy + ay * t0 + py_ * m),
                        (cx + ax * t1 + px_ * m, cy + ay * t1 + py_ * m),
                        (cx + ax * t1 - px_ * m, cy + ay * t1 - py_ * m),
                        (cx + ax * t0 - px_ * m, cy + ay * t0 - py_ * m),
                    ];
                    let mid = (i as f64 + 0.5) / n as f64;
                    ops.push_str(&format!("\n{} {} h f", lerp_color(fa, fb, mid), path_ops(&c0.to_vec(), true)));
                }
                ops.push_str("\nQ");
            }
            Fill::RadialGradient { from, to } => {
                let (fa, fb) = (hex_rgb(from), hex_rgb(to));
                let r = (o.w.hypot(o.h) / 2.0).max(1.0);
                let n = 20;
                ops.push_str(&format!("\nq {} W n", path_ops(&poly, true)));
                for i in 0..n {
                    let rad = r * (n - i) as f64 / n as f64;
                    let ring: Vec<(f64, f64)> = (0..32)
                        .map(|k| {
                            let a = k as f64 * std::f64::consts::TAU / 32.0;
                            (cx + rad * a.cos(), cy + rad * a.sin())
                        })
                        .collect();
                    let t = 1.0 - (rad / r);
                    ops.push_str(&format!("\n{} {} h f", lerp_color(fa, fb, t), path_ops(&ring, true)));
                }
                ops.push_str("\nQ");
            }
            }
        }
    }

    // ---- stroke ---------------------------------------------------------------
    let mut width = o.stroke.width;
    if open && width <= 0.0 {
        width = 2.0;
    }
    if width > 0.0 {
        let dash = match o.stroke.dash {
            crate::model::DashStyle::Solid => String::new(),
            crate::model::DashStyle::Dash => format!(" [{:.2} {:.2}] 0 d", width * 2.0 * KX, width * KX),
            crate::model::DashStyle::Dot => format!(" [{:.2} {:.2}] 0 d", width * KX, width * 2.0 * KX),
            crate::model::DashStyle::DashDot => format!(
                " [{:.2} {:.2} {:.2} {:.2}] 0 d",
                width * 2.0 * KX,
                width * KX,
                width * KX,
                width * KX
            ),
        };
        let body = format!(
            "\n{} {:.2} w{} {} S",
            set_stroke(&o.stroke.color),
            width * KX,
            dash,
            path_ops(&poly, false)
        );
        if o.opacity < 0.999 {
            let gs = gs_for(o.opacity, alphas);
            ops.push_str(&format!("\nq /{gs} gs{body} Q"));
        } else {
            ops.push_str(&body);
        }
        // arrowheads for open connectors (line / wave / scribble)
        if open && poly.len() >= 2 {
            let size = (width * 3.0).max(8.0);
            let tip_len = size;
            if o.stroke.end_arrow != crate::model::ArrowHead::None && poly.len() >= 2 {
                let last = poly[poly.len() - 1];
                let prev = poly[poly.len() - 2];
                let (dx, dy) = (last.0 - prev.0, last.1 - prev.1);
                let norm = dx.hypot(dy).max(1e-6);
                let (dx, dy) = (dx / norm, dy / norm);
                let (bx, by) = (last.0 - dx * tip_len, last.1 - dy * tip_len);
                let (qx, qy) = (-dy, dx);
                let tri = vec![
                    last,
                    (bx + qx * tip_len * 0.4, by + qy * tip_len * 0.4),
                    (bx - qx * tip_len * 0.4, by - qy * tip_len * 0.4),
                ];
                ops.push_str(&format!("\n{} {} h f", set_fill(&o.stroke.color), path_ops(&tri, true)));
            }
            if o.stroke.start_arrow != crate::model::ArrowHead::None && poly.len() >= 2 {
                let first = poly[0];
                let second = poly[1];
                let (dx, dy) = (first.0 - second.0, first.1 - second.1);
                let norm = dx.hypot(dy).max(1e-6);
                let (dx, dy) = (dx / norm, dy / norm);
                let (bx, by) = (first.0 - dx * tip_len, first.1 - dy * tip_len);
                let (qx, qy) = (-dy, dx);
                let tri = vec![
                    first,
                    (bx + qx * tip_len * 0.4, by + qy * tip_len * 0.4),
                    (bx - qx * tip_len * 0.4, by - qy * tip_len * 0.4),
                ];
                ops.push_str(&format!("\n{} {} h f", set_fill(&o.stroke.color), path_ops(&tri, true)));
            }
        }
    }
    ops
}

// ---------------------------------------------------------------------------
// ObjectContent rendering
// ---------------------------------------------------------------------------

struct TextDraw {
    /// plain text (WinAnsi-safe)
    text: String,
    size: f64,     // page-space font size
    color: String, // RRGGBB
    bold: bool,
    serif: bool,
    /// design-space dx from the line's start (for drawing + advancing)
    dx: f64,
    /// design-space advance width
    dw: f64,
    highlight: Option<String>,
}

/// Greedy word-wrap of one paragraph with per-run sizes, returning lines of
/// positioned draw pieces. Lines break at spaces (and hard-break tokens
/// wider than the box); the pieces carry their own run styling.
fn layout_text_paragraph(
    doc: &TextDoc,
    from: u32,
    to: u32,
    inner_w: f64,
    indent_w: f64,
    base_fg: &str,
) -> Vec<Vec<TextDraw>> {
    let mut lines: Vec<Vec<TextDraw>> = vec![Vec::new()];
    let mut line_w = 0.0;
    let avail = (inner_w - indent_w).max(1.0);
    for piece in run_pieces(doc, from, to) {
        let text = utf16_slice(&doc.text, piece.start, piece.end);
        let run = piece.run;
        let size = run.and_then(|r| r.font_size).unwrap_or(BASE_FONT_PX);
        let bold = run.and_then(|r| r.bold).unwrap_or(false);
        let serif = run.and_then(|r| r.font_family.as_deref()) == Some("serif");
        let color = run
            .and_then(|r| r.color.clone())
            .unwrap_or_else(|| base_fg.to_string());
        let highlight = run.and_then(|r| r.highlight.clone());
        // wrap piece text into words at this piece's own size
        let wrapped = fonts::wrap(&text, avail, size, serif, bold);
        let mut first = true;
        for wtext in wrapped {
            if !first {
                lines.push(Vec::new());
                line_w = 0.0;
            }
            first = false;
            let dw = fonts::measure(&wtext, size, serif, bold);
            let line_empty = lines.last().map(|l| l.is_empty()).unwrap_or(true);
            if line_w + dw > avail && !line_empty {
                lines.push(Vec::new());
                line_w = 0.0;
            }
            lines.last_mut().unwrap().push(TextDraw {
                text: wtext,
                size: size * KX,
                color: color.clone(),
                bold,
                serif,
                dx: line_w,
                dw,
                highlight: highlight.clone(),
            });
            line_w += dw;
        }
    }
    lines
}

/// Rich text box object → PDF ops (runs styled individually, paragraphs
/// aligned, bulleted, vertically aligned, autofit-shrunk).
fn text_object_pdf(o: &Shape, doc: &TextDoc, base_fg: &str) -> String {
    let mut ops = String::new();
    let inner_w = (o.w - BOX_PAD_X * 2.0).max(1.0);
    let inner_h = (o.h - BOX_PAD_Y * 2.0).max(1.0);

    // Layout all paragraphs at natural size.
    struct Para {
        lines: Vec<Vec<TextDraw>>,
        align: String,
        indent: f64,
        prefix: String,
        prefix_w: f64,
        line_spacing: f64,
    }
    let mut paras: Vec<Para> = Vec::new();
    let mut number_seq = 0u32;
    for (ps, pe) in doc_paragraphs(doc) {
        let anchor = para_anchor_at(doc, ps);
        let align = match anchor.and_then(|p| p.align) {
            Some(crate::model::TextAlign::Center) => "center",
            Some(crate::model::TextAlign::Right) => "right",
            Some(crate::model::TextAlign::Justify) => "justify",
            _ => "left",
        }.to_string();
        let list_kind = anchor.and_then(|p| p.list).unwrap_or(crate::model::ListKind::None);
        let indent = anchor.and_then(|p| p.indent).unwrap_or(0) as f64 * 36.0;
        let line_spacing = anchor.and_then(|p| p.line_spacing).unwrap_or(1.15);
        let mut number = 0;
        if list_kind == crate::model::ListKind::Number {
            number_seq += 1;
            number = number_seq;
        } else {
            number_seq = 0;
        }
        let prefix = match list_kind {
            crate::model::ListKind::Bullet => "-  ".to_string(),
            crate::model::ListKind::Number => format!("{number}.  "),
            crate::model::ListKind::None => String::new(),
        };
        let prefix_w = if prefix.is_empty() { 0.0 } else { fonts::measure(&prefix, BASE_FONT_PX, false, false) };
        paras.push(Para {
            lines: layout_text_paragraph(doc, ps, pe, inner_w, indent, base_fg),
            align,
            indent,
            prefix,
            prefix_w,
            line_spacing,
        });
    }

    // Autofit shrink.
    let mut total = 0.0;
    for p in &paras {
        total += p.lines.len() as f64 * BASE_FONT_PX * 1.28 * p.line_spacing;
    }
    let k = if doc.autofit == crate::model::Autofit::Shrink && total > inner_h && total > 0.0 {
        (inner_h / total).clamp(0.05, 1.0)
    } else {
        1.0
    };

    // Vertical alignment.
    let scaled_total = total * k;
    let mut y = o.y + BOX_PAD_Y;
    if doc.valign == crate::model::VerticalAlign::Middle {
        y = o.y + (o.h - scaled_total) / 2.0;
    } else if doc.valign == crate::model::VerticalAlign::Bottom {
        y = o.y + o.h - BOX_PAD_Y - scaled_total;
    }

    for p in &paras {
        let line_h = BASE_FONT_PX * 1.28 * p.line_spacing * k;
        for line in &p.lines {
            let line_w: f64 = p.prefix_w + line.iter().map(|d| d.dw).sum::<f64>();
            let mut x = o.x + BOX_PAD_X + p.indent;
            if p.align == "center" {
                x += (inner_w - p.indent - line_w) / 2.0;
            } else if p.align == "right" {
                x += inner_w - p.indent - line_w;
            }
            // bullet/number prefix (design-space, base color at 55% alpha-ish)
            if !p.prefix.is_empty() {
                let (pxp, pyp) = tf(x, y);
                ops.push_str(&format!(
                    "\nBT {} {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
                    font_name(false, false),
                    BASE_FONT_PX * KX * k,
                    pxp,
                    pyp - BASE_FONT_PX * 1.02 * KX * k,
                    pdf_escape(&p.prefix)
                ));
                x += p.prefix_w;
            }
            for d in line {
                let size = d.size * k;
                let (pxp, pyp) = tf(x + d.dx, y);
                if let Some(h) = &d.highlight {
                    // highlight box behind the text: page-space top at
                    // `by` (design y+2), width `bw` (design dw × KX), and
                    // height `bh = d.size * 1.28 * k` — d.size is ALREADY
                    // page-space (layout bakes KX in), so the height needs
                    // no second KY factor (KX == KY). The rect's origin is
                    // its BOTTOM-left, one bh below the box top: the old
                    // emit double-converted `by` (`PH - by * KY`) and
                    // double-scaled the height, throwing the box off-page.
                    let (bx, by) = tf(x + d.dx, y + 2.0);
                    let bw = d.dw * KX;
                    let bh = d.size * 1.28 * k;
                    ops.push_str(&format!(
                        "\n{} {:.2} {:.2} {:.2} {:.2} re f",
                        set_fill(h),
                        bx,
                        by - bh,
                        bw,
                        bh
                    ));
                }
                ops.push_str(&set_fill(&d.color));
                ops.push_str(&format!(
                    "\nBT {} {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
                    font_name_for_run(d),
                    size,
                    pxp,
                    pyp - size * 1.02,
                    pdf_escape(&d.text)
                ));
            }
            y += line_h;
        }
    }
    ops
}

fn font_name_for_run(d: &TextDraw) -> &'static str {
    font_name(d.serif, d.bold)
}

/// Table object → grid lines + cell text (the app painter's geometry).
/// One line of chart text (ink color), baseline at design point (x, y).
fn chart_text(font: &str, x: f64, y: f64, size: f64, s: &str) -> String {
    let (px, py) = tf(x, y);
    format!("\n{} BT {font} {size:.2} Tf {px:.2} {py:.2} Td ({}) Tj ET", set_fill("1C1C22"), pdf_escape(s))
}

/// A filled axis-aligned rectangle between two design-space corners.
fn chart_rect(x0: f64, y0: f64, x1: f64, y1: f64, color: &str) -> String {
    let pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)];
    format!("\n{}{} f", set_fill(color), path_ops(&pts, true))
}

/// A thin grey stroke through the given design-space points.
fn chart_axis(pts: &[(f64, f64)]) -> String {
    format!("\n{} 0.50 w{} S", set_stroke("9E9EA6"), path_ops(pts, false))
}

/// A native chart drawn as vectors: bars, lines, or a pie, with its title,
/// category labels, and a legend. Data scale and colors match the PPTX
/// chart (`chart_range`, `ChartSeries::color_at`).
fn chart_object_pdf(
    o: &Shape,
    style: ChartStyle,
    title: Option<&str>,
    labels: &[String],
    series: &[ChartSeries],
    palette: &[String],
) -> String {
    let mut ops = String::new();
    let mut top = o.y + 8.0;
    if let Some(t) = title {
        ops.push_str(&chart_text("/F1b", o.x + 8.0, o.y + 20.0, 14.0, t));
        top = o.y + 30.0;
    }
    let left = o.x + 8.0;
    let right = o.x + o.w - 8.0;
    let bottom = o.y + o.h - 34.0;
    let legend_y = o.y + o.h - 6.0;

    // Legend: pie slices are named by label, other charts by series.
    let legend: Vec<(String, String)> = if style == ChartStyle::Pie {
        labels
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let c = series.first().map(|s| s.color_at(i, palette)).unwrap_or_else(|| "9E9EA6".to_string());
                (l.clone(), c)
            })
            .collect()
    } else {
        series.iter().enumerate().map(|(i, s)| (s.name.clone(), s.color_at(i, palette))).collect()
    };
    if legend.len() > 1 {
        let mut lx = left;
        for (name, color) in &legend {
            ops.push_str(&chart_rect(lx, legend_y - 8.0, lx + 8.0, legend_y, color));
            ops.push_str(&chart_text("/F1", lx + 12.0, legend_y, 9.0, name));
            lx += 12.0 + name.chars().count() as f64 * 5.5 + 14.0;
        }
    }

    if style == ChartStyle::Pie {
        let vals: &[f64] = series.first().map(|s| s.values.as_slice()).unwrap_or(&[]);
        let total: f64 = vals.iter().filter(|v| v.is_finite() && **v > 0.0).sum();
        if total > 0.0 {
            let (cx, cy) = ((left + right) / 2.0, (top + bottom) / 2.0);
            let r = ((right - left).min(bottom - top) / 2.0).max(1.0);
            let mut a = -std::f64::consts::FRAC_PI_2;
            for (i, v) in vals.iter().enumerate() {
                if !(v.is_finite() && *v > 0.0) {
                    continue;
                }
                let sweep = v / total * std::f64::consts::TAU;
                let steps = ((sweep.to_degrees() / 3.0).ceil() as usize).clamp(2, 240);
                let mut pts = vec![(cx, cy)];
                for k in 0..=steps {
                    let t = a + sweep * k as f64 / steps as f64;
                    pts.push((cx + r * t.cos(), cy + r * t.sin()));
                }
                let color = series.first().map(|s| s.color_at(i, palette)).unwrap_or_else(|| "9E9EA6".to_string());
                ops.push_str(&format!("\n{}{} f", set_fill(&color), path_ops(&pts, true)));
                a += sweep;
            }
        }
        return ops;
    }

    let n = labels.len().max(series.iter().map(|s| s.values.len()).max().unwrap_or(0)).max(1);
    let (lo, hi) = chart_range(series);
    let span = hi - lo;
    let band_of = |slot: f64| slot * 0.7 / series.len().max(1) as f64;

    if style == ChartStyle::Bar {
        // Horizontal bars: category labels sit in a left gutter.
        let pl = left + 70.0;
        let x_of = |v: f64| pl + (v - lo) / span * (right - pl);
        let zero = x_of(0.0);
        let gs = (bottom - top) / n as f64;
        let band = band_of(gs);
        ops.push_str(&chart_axis(&[(zero, top), (zero, bottom)]));
        for g in 0..n {
            let gy = top + g as f64 * gs;
            if let Some(label) = labels.get(g) {
                ops.push_str(&chart_text("/F1", left, gy + gs / 2.0 + 3.0, 9.0, label));
            }
            for (si, s) in series.iter().enumerate() {
                if let Some(&v) = s.values.get(g) {
                    let y0 = gy + gs * 0.15 + si as f64 * band;
                    ops.push_str(&chart_rect(zero.min(x_of(v)), y0, zero.max(x_of(v)), y0 + band, &s.color_at(si, palette)));
                }
            }
        }
        return ops;
    }

    // Column and line: one group per label along the bottom.
    let gw = (right - left) / n as f64;
    let y_of = |v: f64| top + (hi - v) / span * (bottom - top);
    let zero = y_of(0.0);
    ops.push_str(&chart_axis(&[(left, zero), (right, zero)]));
    for g in 0..n {
        if let Some(label) = labels.get(g) {
            let cx = left + g as f64 * gw + gw / 2.0;
            ops.push_str(&chart_text("/F1", cx - label.chars().count() as f64 * 2.6, bottom + 14.0, 9.0, label));
        }
    }
    if style == ChartStyle::Column {
        let band = band_of(gw);
        for g in 0..n {
            let gx = left + g as f64 * gw;
            for (si, s) in series.iter().enumerate() {
                if let Some(&v) = s.values.get(g) {
                    let x0 = gx + gw * 0.15 + si as f64 * band;
                    ops.push_str(&chart_rect(x0, y_of(v), x0 + band, zero, &s.color_at(si, palette)));
                }
            }
        }
    } else {
        for (si, s) in series.iter().enumerate() {
            let pts: Vec<(f64, f64)> = (0..n)
                .filter_map(|g| s.values.get(g).map(|&v| (left + g as f64 * gw + gw / 2.0, y_of(v))))
                .collect();
            if pts.len() >= 2 {
                ops.push_str(&format!("\n{} 2.00 w{} S", set_stroke(&s.color_at(si, palette)), path_ops(&pts, false)));
            }
        }
    }
    ops
}

fn table_object_pdf(o: &Shape, rows: u32, cols: u32, cells: &[String]) -> String {
    let mut ops = String::new();
    let rows = rows.max(1);
    let cols = cols.max(1);
    let cw = o.w / cols as f64;
    let ch = o.h / rows as f64;
    let stroke_color = set_stroke(&o.stroke.color);
    let lw = o.stroke.width.max(0.75) * KX;
    ops.push_str(&format!("\nq {stroke_color} {lw:.2} w"));
    // Outer border.
    let (x0, y0) = tf(o.x, o.y);
    let (x1, y1) = tf(o.x + o.w, o.y + o.h);
    ops.push_str(&format!("\n{:.2} {:.2} {:.2} {:.2} re S", x0, y1, x1 - x0, y0 - y1));
    for r in 1..rows {
        let (_, ly) = tf(o.x, o.y + ch * r as f64);
        let (_, ry) = tf(o.x + o.w, o.y + ch * r as f64);
        ops.push_str(&format!("\n{:.2} {:.2} m {:.2} {:.2} l S", x0, ly, x1, ry));
    }
    for c in 1..cols {
        let (lx, _) = tf(o.x + cw * c as f64, o.y);
        let (rx, _) = tf(o.x + cw * c as f64, o.y + o.h);
        ops.push_str(&format!("\n{:.2} {:.2} m {:.2} {:.2} l S", lx, y0, rx, y1));
    }
    ops.push_str("\nQ");
    // Cell text: the app's sizing, centered vertically, left with padding.
    let cell_style_px = (BASE_FONT_PX * 0.62).min(ch * 0.42).max(8.0);
    let size = cell_style_px * KX;
    ops.push_str(&set_fill("17181A"));
    for r in 0..rows {
        for c in 0..cols {
            let text = cells.get((r * cols + c) as usize).map(|s| s.as_str()).unwrap_or("");
            if text.is_empty() {
                continue;
            }
            let (px, py) = tf(o.x + cw * c as f64 + 7.0, o.y + ch * r as f64 + (ch - cell_style_px * 1.28) / 2.0);
            ops.push_str(&format!(
                "\nBT /F1 {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
                size,
                px,
                py,
                pdf_escape(text)
            ));
        }
    }
    ops
}

/// Icon sticker → filled rounded card + centered name (the app's icons are
/// Material glyphs, rendered here as their own clean vector+text card).
fn icon_object_pdf(o: &Shape, name: &str) -> String {
    let mut ops = String::new();
    let fill = match &o.fill {
        Fill::Solid { color } => color.clone(),
        _ => "F5F5F7".to_string(),
    };
    let (x0, y0) = tf(o.x, o.y);
    let (x1, y1) = tf(o.x + o.w, o.y + o.h);
    ops.push_str(&format!("\nq {} {:.2} {:.2} {:.2} {:.2} re f Q", set_fill(&fill), x0, y1, x1 - x0, y0 - y1));
    let size = (o.w.min(o.h) * 0.16).clamp(6.0, 14.0) * KX;
    let cy = (y0 + y1) / 2.0;
    ops.push_str(&set_fill("17181A"));
    ops.push_str(&format!(
        "\nBT /F1 {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
        size,
        x0 + 2.0,
        cy - size * 0.36,
        pdf_escape(name)
    ));
    ops
}

/// Media card → dark card + kind label + name (the app's media view).
fn media_object_pdf(o: &Shape, name: &str, media_kind: Option<&str>) -> String {
    let mut ops = String::new();
    let (x0, y0) = tf(o.x, o.y);
    let (x1, y1) = tf(o.x + o.w, o.y + o.h);
    let w = x1 - x0;
    let h = y0 - y1;
    let kind = if media_kind.unwrap_or("video") == "video" { "VIDEO" } else { "AUDIO" };
    ops.push_str(&format!("\nq {} {:.2} {:.2} {:.2} {:.2} re f Q", set_fill("101014"), x0, y1, w, h));
    if o.stroke.width > 0.0 {
        ops.push_str(&format!(
            "\nq {} {:.2} w {:.2} {:.2} {:.2} {:.2} re S Q",
            set_stroke(&o.stroke.color),
            o.stroke.width * KX,
            x0,
            y1,
            w,
            h
        ));
    }
    let kind_size = (o.h * 0.09).clamp(8.0, 16.0) * KX;
    let name_size = (o.h * 0.075).clamp(7.0, 14.0) * KX;
    let cx = (x0 + x1) / 2.0;
    let cy = (y0 + y1) / 2.0;
    ops.push_str(&set_fill("9E9EA6"));
    ops.push_str(&format!(
        "\nBT /F1b {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
        kind_size,
        cx - w * 0.18,
        cy + name_size * 0.4,
        pdf_escape(kind)
    ));
    ops.push_str(&format!(
        "\nBT /F1 {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
        name_size,
        x0 + 4.0,
        cy - name_size,
        pdf_escape(name)
    ));
    ops
}

/// Image object → `q … cm /ImN Do Q` with rotation, or a placeholder card.
fn image_object_pdf(o: &Shape, name: Option<&str>, im_ref: Option<&str>) -> String {
    match im_ref {
        Some(im) => {
            let rot = o.rotation.to_radians();
            let (c, s) = (rot.cos(), rot.sin());
            // image-space vectors in page coords
            let w = o.w * KX;
            let h = o.h * KY;
            let ux = w * c;
            let uy = -w * s; // design y-down → page y-up
            let vx = h * s;
            let vy = h * c;
            // center in page coords
            let (ccx, ccy) = tf(o.x + o.w / 2.0, o.y + o.h / 2.0);
            // origin = center - (u+v)/2
            let ox = ccx - (ux + vx) / 2.0;
            let oy = ccy - (uy + vy) / 2.0;
            format!("\nq {ox:.2} {oy:.2} {ux:.2} {uy:.2} {vx:.2} {vy:.2} cm /{im} Do Q")
        }
        None => {
            let label = name.unwrap_or("image");
            let (x0, y0) = tf(o.x, o.y);
            let (x1, y1) = tf(o.x + o.w, o.y + o.h);
            let size = (o.h * 0.08).clamp(7.0, 14.0) * KX;
            format!(
                "\nq {} 1 w {:.2} {:.2} {:.2} {:.2} re f Q\nq {} 1 w {:.2} {:.2} {:.2} {:.2} re S Q\n{} BT /F1 {:.2} Tf {:.2} {:.2} Td ({}) Tj ET",
                set_fill("1C1C22"),
                x0,
                y1,
                x1 - x0,
                y0 - y1,
                set_stroke("2A2A31"),
                x0,
                y1,
                x1 - x0,
                y0 - y1,
                set_fill("6C6C74"),
                size,
                x0 + 2.0,
                (y0 + y1) / 2.0,
                pdf_escape(label)
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Image XObjects
// ---------------------------------------------------------------------------

/// One embedded image: the resource id it resolves, its page-space draw
/// name, its dict, its compressed bytes and (when the alpha varies) the
/// compressed gray alpha stream.
struct ImageXObject {
    rid: String,
    name: String,
    width: u32,
    height: u32,
    dict: String,
    stream: Vec<u8>,
    smask_stream: Option<Vec<u8>>,
}

/// Build the image XObjects for the given resolved assets. JPEGs pass
/// through as DCTDecode; anything with RGBA embeds as FlateDecode RGB
/// (+ an SMask when the alpha varies). A bad/missing asset is skipped —
/// the caller renders a placeholder.
fn build_image_xobjects(images: &BTreeMap<String, ExportImage>) -> Vec<ImageXObject> {
    let mut out = Vec::new();
    for (rid, asset) in images {
        let format = asset.format.to_ascii_lowercase();
        if format == "jpeg" || format == "jpg" {
            out.push(ImageXObject {
                rid: rid.clone(),
                name: format!("Im{}", out.len()),
                width: asset.width,
                height: asset.height,
                dict: format!(
                    "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {} >>",
                    asset.width,
                    asset.height,
                    asset.bytes.len()
                ),
                stream: asset.bytes.clone(),
                smask_stream: None,
            });
            continue;
        }
        let Some(rgba) = asset.rgba.as_ref() else { continue };
        let n = (asset.width as usize) * (asset.height as usize);
        if rgba.len() < n * 4 || n == 0 {
            continue; // bad payload → placeholder, never a broken PDF
        }
        // strip alpha into RGB + a gray alpha plane
        let mut rgb = Vec::with_capacity(n * 3);
        let mut alpha = Vec::with_capacity(n);
        let mut any_alpha = false;
        for i in 0..n {
            rgb.push(rgba[i * 4]);
            rgb.push(rgba[i * 4 + 1]);
            rgb.push(rgba[i * 4 + 2]);
            alpha.push(rgba[i * 4 + 3]);
            if rgba[i * 4 + 3] != 255 {
                any_alpha = true;
            }
        }
        let flated = deflate(&rgb);
        let smask = if any_alpha { Some(deflate(&alpha)) } else { None };
        let smask_ref = if smask.is_some() { " /SMask 0 0 R" } else { "" };
        out.push(ImageXObject {
            rid: rid.clone(),
            name: format!("Im{}", out.len()),
            width: asset.width,
            height: asset.height,
            dict: format!(
                "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode{smask_ref} /Length {} >>",
                asset.width,
                asset.height,
                flated.len()
            ),
            smask_stream: smask,
            stream: flated,
        });
    }
    out
}

fn deflate(data: &[u8]) -> Vec<u8> {
    let mut zw = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    zw.write_all(data).ok();
    zw.finish().unwrap_or_default()
}

// ---------------------------------------------------------------------------
// The writer
// ---------------------------------------------------------------------------

/// Render deck to PDF bytes. `images` maps resource ids to resolved assets
/// (see [crate::export::ExportImage]); missing entries render as clean
/// placeholders.
pub fn to_pdf(deck: &Deck, images: &BTreeMap<String, ExportImage>) -> Vec<u8> {
    let mut pages_content: Vec<String> = Vec::new();
    let mut pages_links: Vec<Vec<([f64; 4], PdfLink)>> = Vec::new();
    let mut alphas: Vec<(f64, String)> = Vec::new();
    // Page width follows the deck's aspect: the design→page scale is uniform
    // (KX == KY), so width-in-points is KY × design-width. Height stays PH.
    let pw = KY * deck_dims(deck).0;

    // Image XObjects are shared across pages; each page references the ones
    // it draws by name.
    let xobjects = build_image_xobjects(images);
    let xobject_ref = |rid: &str| -> Option<&str> {
        xobjects
            .iter()
            .find(|x| x.rid == rid)
            .map(|x| x.name.as_str())
    };

    let base_fg = crate::dna::resolve(&deck.dna).palette.fg.clone();
    let chart_pal = crate::dna::resolve(&deck.dna).chart_palette;

    for slide in &deck.slides {
        let layout = layout_slide(&deck, slide);
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
        // The object layer in true Z-order — content and shapes interleave
        // exactly as `slide.objects` lists them.
        for obj in &slide.objects {
            match &obj.content {
                Some(ObjectContent::Text { doc }) => {
                    ops.push_str(&text_object_pdf(obj, doc, &base_fg));
                }
                Some(ObjectContent::Table { rows, cols, cells }) => {
                    ops.push_str(&table_object_pdf(obj, *rows, *cols, cells));
                }
                Some(ObjectContent::Icon { name }) => {
                    ops.push_str(&icon_object_pdf(obj, name));
                }
                Some(ObjectContent::Chart { style, title, labels, series }) => {
                    ops.push_str(&chart_object_pdf(obj, *style, title.as_deref(), labels, series, &chart_pal));
                }
                Some(ObjectContent::Media { name, media_kind, .. }) => {
                    ops.push_str(&media_object_pdf(obj, name.as_deref().unwrap_or("media"), media_kind.as_deref()));
                }
                Some(ObjectContent::Image { resource_id, name, .. }) => {
                    ops.push_str(&image_object_pdf(obj, name.as_deref(), xobject_ref(resource_id)));
                }
                None => {
                    ops.push_str(&object_pdf(obj, &mut alphas));
                }
            }
        }
        // Tap-actions become /Link annotations over the object's box.
        let mut links = Vec::new();
        for obj in &slide.objects {
            let Some(l) = &obj.link else { continue };
            let act = match l.kind {
                LinkKind::Url => l.safe_url().map(|u| PdfLink::Uri(u.to_string())),
                LinkKind::Slide => deck.slides.iter().position(|s| s.id == l.target).map(PdfLink::Page),
            };
            let Some(act) = act else { continue };
            let (mut x0, mut y0, mut x1, mut y1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
            for (px, py) in object_polygon(obj) {
                let (x, y) = tf(px, py);
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x);
                y1 = y1.max(y);
            }
            if x0 > x1 {
                continue;
            }
            links.push(([x0, y0, x1, y1], act));
        }
        pages_links.push(links);
        pages_content.push(ops);
    }

    // ---- assemble objects -------------------------------------------------
    let mut objs: Vec<Vec<u8>> = Vec::new(); // object bodies (index+1 = obj num)

    // reserve: 1 = catalog, 2 = pages tree, fonts come after.
    objs.push(Vec::new()); // obj 1 Catalog (filled below)
    objs.push(Vec::new()); // obj 2 Pages (filled below)

    // Font objects
    let font_defs = [
        ("/F1", "Helvetica"),
        ("/F1b", "Helvetica-Bold"),
        ("/F2", "Times-Roman"),
        ("/F3", "Times-Bold"),
    ];
    let mut font_refs = String::new();
    for (tag, base) in font_defs.iter() {
        let num = objs.len() + 1;
        objs.push(format!("<< /Type /Font /Subtype /Type1 /BaseFont /{} >>", base).into_bytes());
        font_refs.push_str(&format!("{} {} 0 R ", tag, num));
    }

    // Image XObjects (+ their SMasks).
    let mut xobject_refs = String::new();
    for x in &xobjects {
        let img_num = objs.len() + 1;
        let smask_num = if x.smask_stream.is_some() { img_num + 1 } else { 0 };
        let dict = if smask_num > 0 {
            x.dict.replace("/SMask 0 0 R", &format!("/SMask {} 0 R", smask_num))
        } else {
            x.dict.clone()
        };
        objs.push(format!("{}
stream
", dict).into_bytes());
        let last = objs.len() - 1;
        objs[last].extend_from_slice(&x.stream);
        objs[last].extend_from_slice(b"
endstream");
        xobject_refs.push_str(&format!("/{} {} 0 R ", x.name, img_num));
        if let Some(smask_bytes) = &x.smask_stream {
            let smask_dict = format!(
                "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length {} >>",
                x.width,
                x.height,
                smask_bytes.len()
            );
            objs.push(format!("{}
stream
", smask_dict).into_bytes());
            let last = objs.len() - 1;
            objs[last].extend_from_slice(smask_bytes);
            objs[last].extend_from_slice(b"
endstream");
        }
    }

    let resources = if alphas.is_empty() {
        format!("<< /Font << {font_refs} >> /XObject << {xobject_refs} >> >>")
    } else {
        let mut gs_refs = String::new();
        for (a, name) in &alphas {
            let num = objs.len() + 1;
            objs.push(format!("<< /Type /ExtGState /ca {:.3} /CA {:.3} /BM /Normal >>", a, a).into_bytes());
            gs_refs.push_str(&format!("/{} {} 0 R ", name, num));
        }
        format!("<< /Font << {font_refs} >> /ExtGState << {gs_refs} >> /XObject << {xobject_refs} >> >>")
    };

    // Object numbers are fixed before writing: a page takes its page
    // object, its content stream, then one object per link annotation. A
    // GoTo action can point at a later page, so every page number is known
    // up front.
    let mut page_nums: Vec<usize> = Vec::with_capacity(pages_content.len());
    let mut next_num = objs.len() + 1;
    for links in &pages_links {
        page_nums.push(next_num);
        next_num += 2 + links.len();
    }
    let mut kids = String::new();
    for (k, content) in pages_content.iter().enumerate() {
        let page_num = page_nums[k];
        let content_num = page_num + 1;
        let links = &pages_links[k];
        let annots = if links.is_empty() {
            String::new()
        } else {
            let refs: Vec<String> = (0..links.len()).map(|a| format!("{} 0 R", page_num + 2 + a)).collect();
            format!(" /Annots [{}]", refs.join(" "))
        };
        objs.push(format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {pw:.0} {PH}] /Resources {} /Contents {content_num} 0 R{annots} >>",
            resources
        ).into_bytes());
        objs.push(format!("<< /Length {} >>\nstream\n{}\nendstream", content.len(), content).into_bytes());
        for (rect, act) in links {
            let action = match act {
                PdfLink::Uri(u) => format!("/A << /S /URI /URI ({}) >>", pdf_escape(u)),
                PdfLink::Page(j) => format!("/A << /S /GoTo /D [{} 0 R /XYZ null null null] >>", page_nums[*j]),
            };
            objs.push(format!(
                "<< /Type /Annot /Subtype /Link /Rect [{:.2} {:.2} {:.2} {:.2}] /Border [0 0 0] {} >>",
                rect[0], rect[1], rect[2], rect[3], action
            ).into_bytes());
        }
        kids.push_str(&format!(" {} 0 R", page_num));
    }

    objs[0] = b"<< /Type /Catalog /Pages 2 0 R >>".to_vec();
    objs[1] = format!("<< /Type /Pages /Kids [{kids}] /Count {} >>", pages_content.len()).into_bytes();

    // ---- serialize (binary-safe) -------------------------------------------
    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(b"%PDF-1.4\n");
    let mut offsets = Vec::with_capacity(objs.len());
    for (i, body) in objs.iter().enumerate() {
        offsets.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        out.extend_from_slice(body);
        out.extend_from_slice(b"\nendobj\n");
    }
    let xref_pos = out.len();
    out.extend_from_slice(format!("xref\n0 {}\n", objs.len() + 1).as_bytes());
    out.extend_from_slice(b"0000000000 65535 f \n");
    for off in &offsets {
        out.extend_from_slice(format!("{:010} 00000 n \n", off).as_bytes());
    }
    out.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
            objs.len() + 1,
            xref_pos
        )
        .as_bytes(),
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    #[test]
    fn charts_draw_labels_and_fills() {
        use serde_json::json;
        let shape: Shape = serde_json::from_value(json!({
            "id": "c", "preset": "rectangle", "x": 100, "y": 100, "w": 400, "h": 300
        }))
        .unwrap();
        let labels: Vec<String> = vec!["Q1".into(), "Q2".into()];
        let series: Vec<ChartSeries> = serde_json::from_value(json!([{"name": "a", "values": [3, 5]}])).unwrap();
        let col = chart_object_pdf(&shape, ChartStyle::Column, Some("Sales"), &labels, &series, &[]);
        assert!(col.contains("(Q1) Tj") && col.contains("(Q2) Tj"), "category labels");
        assert!(col.contains("(Sales) Tj"), "title");
        assert_eq!(col.matches(" h f").count(), 2, "one bar per label");
        let pie_series: Vec<ChartSeries> = serde_json::from_value(json!([{"name": "a", "values": [1, 1]}])).unwrap();
        let pie = chart_object_pdf(&shape, ChartStyle::Pie, None, &labels, &pie_series, &[]);
        // Two wedges plus two legend swatches (the legend names the slices).
        assert_eq!(pie.matches(" h f").count(), 4, "wedges and legend swatches");
    }

    #[test]
    fn links_become_annotations() {
        use serde_json::json;
        let obj = |id: &str, link: serde_json::Value| -> Shape {
            serde_json::from_value(json!({"id": id, "preset": "rectangle", "x": 100, "y": 100, "w": 300, "h": 200, "link": link})).unwrap()
        };
        let slide = |id: &str, objects: Vec<Shape>| Slide {
            background: None,
            hide_graphics: false,
            id: id.into(),
            archetype: Archetype::Cover,
            content: SlideContent::Cover { kicker: None, title: "T".into(), subtitle: None },
            objects,
        };
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::MagazineSerif, seed: 9 },
            aspect: "16:9".into(),
            slides: vec![
                slide(
                    "s1",
                    vec![
                        obj("a", json!({"kind": "slide", "target": "s2"})),
                        obj("b", json!({"kind": "url", "target": "https://example.com/"})),
                        obj("c", json!({"kind": "url", "target": "javascript:alert(1)"})),
                    ],
                ),
                slide("s2", vec![]),
            ],
            components: Vec::new(),
        };
        let bytes = to_pdf(&deck, &BTreeMap::new());
        let text = String::from_utf8_lossy(&bytes);
        assert_eq!(text.matches("/Subtype /Link").count(), 2, "unsafe URL must not export");
        assert!(text.contains("/S /GoTo /D ["));
        assert!(text.contains("/S /URI /URI (https://example.com/)"));
        assert!(text.contains("/Annots ["));
    }

    #[test]
    fn produces_pdf_magic_and_pages() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::MagazineSerif, seed: 9 },
            aspect: "16:9".into(),
            slides: vec![
                Slide {
                    background: None,
                    hide_graphics: false,
                    id: "s1".into(),
                    archetype: Archetype::Cover,
                    content: SlideContent::Cover { kicker: None, title: "Bonjour".into(), subtitle: None },
                    objects: Vec::new(),
                },
                Slide {
                    background: None,
                    hide_graphics: false,
                    id: "s2".into(),
                    archetype: Archetype::Statement,
                    content: SlideContent::Statement { text: "Ship it".into(), attribution: None },
                    objects: Vec::new(),
                },
            ],
            components: Vec::new(),
        };
        let b = to_pdf(&deck, &BTreeMap::new());
        let s = String::from_utf8_lossy(&b);
        assert!(s.starts_with("%PDF-1.4"));
        assert!(s.contains("/Count 2"));
        assert!(s.contains("%%EOF"));
        // 16:9 deck: the classic 960-point page.
        assert!(s.contains("/MediaBox [0 0 960 540]"));
    }

    #[test]
    fn page_width_follows_aspect() {
        // 4:3 deck → 720-point page (same 540 height, same uniform scale).
        let deck = Deck {
            id: "d43".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 5 },
            aspect: "4:3".into(),
            slides: vec![Slide {
                background: None,
                hide_graphics: false,
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Square-ish".into(), subtitle: None },
                objects: Vec::new(),
            }],
            components: Vec::new(),
        };
        let b = to_pdf(&deck, &BTreeMap::new());
        let s = String::from_utf8_lossy(&b);
        assert!(s.contains("/MediaBox [0 0 720 540]"), "4:3 page expected 720pt wide");
    }

    #[test]
    fn objects_render_as_vectors() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 3 },
            aspect: "16:9".into(),
            slides: vec![Slide {
                background: None,
                hide_graphics: false,
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Hi".into(), subtitle: None },
                objects: vec![
                    Shape {
                        id: "o1".into(),
                        link: None,
                        preset: "rectangle".into(),
                        x: 100.0, y: 100.0, w: 300.0, h: 200.0,
                        rotation: 0.0, opacity: 0.5, locked: false,
                        group: None, component: None,
                        fill: Fill::Solid { color: "D03028".into() },
                        stroke: crate::model::Stroke::default(),
                        effects: crate::model::Effects::default(),
                        points: None, holes: None, closed: true,
                        content: None,
                    },
                    Shape {
                        id: "o2".into(),
                        link: None,
                        preset: "line".into(),
                        x: 100.0, y: 500.0, w: 400.0, h: 0.0,
                        rotation: 0.0, opacity: 1.0, locked: false,
                        group: None, component: None,
                        fill: Fill::None,
                        stroke: crate::model::Stroke { color: "17181A".into(), width: 3.0, ..Default::default() },
                        effects: crate::model::Effects::default(),
                        points: None, holes: None, closed: false,
                        content: None,
                    },
                ],
            }],
            components: Vec::new(),
        };
        let b = to_pdf(&deck, &BTreeMap::new());
        let s = String::from_utf8_lossy(&b);
        assert!(s.contains("/ExtGState"), "alpha state missing");
        assert!(s.contains("gs0"), "gs ref missing");
        assert!(s.contains(" m\n") || s.contains(" m ") || s.contains(" m"), "path move missing");
        assert!(s.contains(" l "), "path line missing");
        assert!(s.contains(" h f"), "close+fill missing");
    }

    /// The content-deck from the pptx tests, exported to PDF: text runs,
    /// table cells, and an embedded image (as an XObject with a DCT or
    /// Flate stream) must all be present.
    #[test]
    fn content_objects_render_text_table_and_image() {
        let deck = crate::export::pptx::tests::content_deck_for_pdf();
        let mut images = BTreeMap::new();
        images.insert(
            "r1".into(),
            ExportImage {
                format: "png".into(),
                width: 2,
                height: 1,
                bytes: crate::export::tests_support::tiny_png(),
                rgba: Some(vec![255, 0, 0, 255, 0, 128, 0, 128]),
            },
        );
        let b = to_pdf(&deck, &images);
        let s = String::from_utf8_lossy(&b);
        // Text runs (WinAnsi text + bold font). The bold run splits
        // "Hello" from " world" — assert the pieces.
        assert!(s.contains("Hello"), "text missing");
        assert!(s.contains("Second para"), "second paragraph missing");
        assert!(s.contains("/F1b"), "bold run missing");
        // Table cells + grid.
        assert!(s.contains("(A) Tj"), "table cell A missing");
        assert!(s.contains("(D) Tj"), "table cell D missing");
        // Icon + media cards.
        assert!(s.contains("(star) Tj"), "icon label missing");
        assert!(s.contains("(clip.mp4) Tj"), "media label missing");
        // Image XObject + draw op.
        assert!(s.contains("/Subtype /Image"), "image xobject missing");
        assert!(s.contains("/FlateDecode"), "flate filter missing");
        assert!(s.contains("/Im0 Do"), "image draw op missing");
        assert!(s.contains("/SMask"), "alpha smask missing");
        // A missing image asset (r_missing → media card) renders a
        // placeholder, never a broken ref.
        assert!(!s.contains("/Im1 Do"), "no phantom xobject ref");
    }

    /// A highlighted run paints its background box AT the run's line,
    /// inside the page: the old emit double-converted the box's
    /// page-space Y (`PH - by * KY` on the already-converted `by`) and
    /// double-scaled its height (KY on the already-page-space `d.size`),
    /// parking highlights far above the text they belong to.
    #[test]
    fn highlight_rects_stay_inside_the_page() {
        let text_doc = TextDoc {
            text: "highlighted words".into(),
            runs: vec![TextRun {
                start: 0,
                end: 11,
                bold: None,
                italic: None,
                underline: None,
                strike: None,
                subscript: None,
                superscript: None,
                color: None,
                highlight: Some("FFF3B0".into()),
                font_family: None,
                font_size: Some(32.0),
            }],
            paras: vec![],
            valign: VerticalAlign::Top,
            autofit: Autofit::None,
        };
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 3 },
            aspect: "16:9".into(),
            slides: vec![Slide {
                background: None,
                hide_graphics: false,
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Hi".into(), subtitle: None },
                objects: vec![Shape {
                    id: "txt".into(),
                    link: None,
                    preset: "rectangle".into(),
                    x: 100.0, y: 100.0, w: 400.0, h: 200.0,
                    rotation: 0.0, opacity: 1.0, locked: false,
                    group: None, component: None,
                    fill: Fill::None,
                    stroke: crate::model::Stroke::default(),
                    effects: crate::model::Effects::default(),
                    points: None, holes: None, closed: true,
                    content: Some(ObjectContent::Text { doc: text_doc }),
                }],
            }],
            components: Vec::new(),
        };
        let b = to_pdf(&deck, &BTreeMap::new());
        let s = String::from_utf8_lossy(&b);

        // The highlight fill ("FFF3B0" → "1.000 0.953 0.706 rg"): collect
        // every rect op drawn with it. One line in the stream is
        // "<fill> x y w h re f".
        let hl_fill = set_fill("FFF3B0");
        let mut rects: Vec<(f64, f64, f64, f64)> = Vec::new();
        for line in s.lines() {
            if !line.contains(" re f") || !line.contains(&hl_fill) {
                continue;
            }
            let toks: Vec<&str> = line.split_whitespace().collect();
            let rg = toks.iter().position(|t| *t == "rg").expect("fill op before rect");
            let nums: Vec<f64> = toks[rg + 1..]
                .iter()
                .take(4)
                .map(|t| t.parse().expect("rect numbers"))
                .collect();
            assert_eq!(nums.len(), 4, "the rect op carries x y w h");
            rects.push((nums[0], nums[1], nums[2], nums[3]));
        }
        assert!(!rects.is_empty(), "the highlighted run painted its box");

        // Page bounds: a 16:9 deck is 960×540pt.
        for &(x, y, w, h) in &rects {
            assert!(x >= 0.0 && x + w <= 960.0,
                "highlight box x inside the page: {x}+{w}");
            assert!(y >= 0.0 && y + h <= 540.0,
                "highlight box y inside the page: {y}+{h}");
        }

        // And AT the run's own line: the box's page-space TOP is
        // PH - (y_design + 2) * KY with y_design = o.y + BOX_PAD_Y = 110
        // → 456.0, its height is d.size * 1.28 = 32 * KX * 1.28 = 30.72,
        // and its left is (o.x + BOX_PAD_X) * KX = 85.5. The old emit
        // put the top at ~192 — hundreds of points above the text.
        let (x, y, w, h) = rects[0];
        let top = y + h;
        assert!((top - 456.0).abs() < 0.5,
            "highlight top at the run's page-space line top: {top}");
        assert!((x - 85.5).abs() < 0.5,
            "highlight left at the run's page-space x: {x}");
        assert!((h - 30.72).abs() < 0.5,
            "highlight height covers the whole line: {h}");
    }
}
