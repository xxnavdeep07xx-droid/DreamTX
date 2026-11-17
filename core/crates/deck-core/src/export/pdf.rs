//! Minimal PDF 1.4 writer. v0.1 is Latin-first: text maps to base-14 fonts
//! (Helvetica/Times) in WinAnsi; non-Latin-1 chars are transliterated or
//! dropped (M2 ships embedded subset fonts + full Unicode).

use crate::command::object_polygon;
use crate::model::{Deck, Fill, Shape, SLIDE_H, SLIDE_W};
use crate::layout::{layout_slide, Element};

/// Slightly oversize page for crispness in viewers; everything in points.
const PW: f64 = 960.0;
const PH: f64 = 540.0;
const KX: f64 = PW / SLIDE_W;
const KY: f64 = PH / SLIDE_H;

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
                let m = (o.w + o.h);
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

/// Render deck to PDF bytes.
pub fn to_pdf(deck: &Deck) -> Vec<u8> {
    let mut pages_content: Vec<String> = Vec::new();
    let mut alphas: Vec<(f64, String)> = Vec::new();

    for slide in &deck.slides {
        let layout = layout_slide(&deck.dna, slide);
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
        // manual vector overlay on top
        for obj in &slide.objects {
            ops.push_str(&object_pdf(obj, &mut alphas));
        }
        pages_content.push(ops);
    }

    // ---- assemble objects -------------------------------------------------
    let mut objs: Vec<String> = Vec::new(); // object bodies, index+1 = obj num

    // reserve: 1 = catalog, 2 = pages tree, fonts come after.
    objs.push(String::new()); // obj 1 Catalog (filled below)
    objs.push(String::new()); // obj 2 Pages (filled below)

    // Font objects 3..=6
    let font_defs = [
        ("/F1", "Helvetica"),
        ("/F1b", "Helvetica-Bold"),
        ("/F2", "Times-Roman"),
        ("/F3", "Times-Bold"),
    ];
    let mut font_refs = String::new();
    for (tag, base) in font_defs.iter() {
        let num = objs.len() + 1;
        objs.push(format!("<< /Type /Font /Subtype /Type1 /BaseFont /{} >>", base));
        font_refs.push_str(&format!("{} {} 0 R ", tag, num));
    }
    let resources = if alphas.is_empty() {
        format!("<< /Font << {font_refs} >> >>")
    } else {
        let mut gs_refs = String::new();
        for (a, name) in &alphas {
            let num = objs.len() + 1;
            objs.push(format!("<< /Type /ExtGState /ca {:.3} /CA {:.3} /BM /Normal >>", a, a));
            gs_refs.push_str(&format!("/{} {} 0 R ", name, num));
        }
        format!("<< /Font << {font_refs} >> /ExtGState << {gs_refs} >> >>")
    };

    let mut kids = String::new();
    for content in &pages_content {
        let page_num = objs.len() + 1;
        let content_num = page_num + 1;
        objs.push(format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PW} {PH}] /Resources {} /Contents {content_num} 0 R >>",
            resources
        ));
        objs.push(format!("<< /Length {} >>\nstream\n{}\nendstream", content.len(), content));
        kids.push_str(&format!(" {} 0 R", page_num));
    }

    objs[0] = "<< /Type /Catalog /Pages 2 0 R >>".to_string();
    objs[1] = format!("<< /Type /Pages /Kids [{kids}] /Count {} >>", pages_content.len());

    // ---- serialize --------------------------------------------------------
    let mut out = String::from("%PDF-1.4\n");
    let mut offsets = Vec::with_capacity(objs.len());
    for (i, body) in objs.iter().enumerate() {
        offsets.push(out.len());
        out.push_str(&format!("{} 0 obj\n{}\nendobj\n", i + 1, body));
    }
    let xref_pos = out.len();
    out.push_str(&format!("xref\n0 {}\n", objs.len() + 1));
    out.push_str("0000000000 65535 f \n");
    for off in &offsets {
        out.push_str(&format!("{:010} 00000 n \n", off));
    }
    out.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
        objs.len() + 1,
        xref_pos
    ));
    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    #[test]
    fn produces_pdf_magic_and_pages() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::MagazineSerif, seed: 9 },
            slides: vec![
                Slide {
                    id: "s1".into(),
                    archetype: Archetype::Cover,
                    content: SlideContent::Cover { kicker: None, title: "Bonjour".into(), subtitle: None },
                    objects: Vec::new(),
                },
                Slide {
                    id: "s2".into(),
                    archetype: Archetype::Statement,
                    content: SlideContent::Statement { text: "Ship it".into(), attribution: None },
                    objects: Vec::new(),
                },
            ],
            components: Vec::new(),
        };
        let b = to_pdf(&deck);
        let s = String::from_utf8_lossy(&b);
        assert!(s.starts_with("%PDF-1.4"));
        assert!(s.contains("/Count 2"));
        assert!(s.contains("%%EOF"));
    }

    #[test]
    fn objects_render_as_vectors() {
        let deck = Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 3 },
            slides: vec![Slide {
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Hi".into(), subtitle: None },
                objects: vec![
                    Shape {
                        id: "o1".into(),
                        preset: "rectangle".into(),
                        x: 100.0, y: 100.0, w: 300.0, h: 200.0,
                        rotation: 0.0, opacity: 0.5, locked: false,
                        group: None, component: None,
                        fill: Fill::Solid { color: "D03028".into() },
                        stroke: crate::model::Stroke::default(),
                        effects: crate::model::Effects::default(),
                        points: None, closed: true,
                    },
                    Shape {
                        id: "o2".into(),
                        preset: "line".into(),
                        x: 100.0, y: 500.0, w: 400.0, h: 0.0,
                        rotation: 0.0, opacity: 1.0, locked: false,
                        group: None, component: None,
                        fill: Fill::None,
                        stroke: crate::model::Stroke { color: "17181A".into(), width: 3.0, ..Default::default() },
                        effects: crate::model::Effects::default(),
                        points: None, closed: false,
                    },
                ],
            }],
            components: Vec::new(),
        };
        let b = to_pdf(&deck);
        let s = String::from_utf8_lossy(&b);
        assert!(s.contains("/ExtGState"), "alpha state missing");
        assert!(s.contains("gs0"), "gs ref missing");
        assert!(s.contains(" m\n") || s.contains(" m ") || s.contains(" m"), "path move missing");
        assert!(s.contains(" l "), "path line missing");
        assert!(s.contains(" h f"), "close+fill missing");
    }
}
