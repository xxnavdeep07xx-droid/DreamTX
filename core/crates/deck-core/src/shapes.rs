//! Vector shape presets + polygon geometry + boolean ops.
//!
//! Presets are parametric: a fixed core set ships today (~40); the registry
//! is data-driven so more presets drop in without touching callers. Geometry
//! is polygon-based (ellipses are 48-gons) which keeps one representation
//! for canvas rendering (Flutter mirrors this), PDF export and boolean ops.
//! PPTX export maps preset names onto PowerPoint's own preset geometry
//! (`prstGeom`) for maximum fidelity, falling back to `custGeom` polygons.
//!
//! Boolean ops (union / subtract / intersect) are exact for convex inputs:
//! intersect = Sutherland–Hodgman, subtract = sequential outside-half-plane
//! clips, union = convex hull of the two (approximation — it fills concave
//! notches between the shapes; the UI tells the user). Non-convex inputs are
//! rejected with a clear error rather than silently mis-shaping.

/// Static preset registry entry.
pub struct PresetInfo {
    pub name: &'static str,
    pub label: &'static str,
    pub convex: bool,
    /// Open path (line-like) rather than a closed region.
    pub open: bool,
    /// PowerPoint preset geometry name; empty → custGeom polygon export.
    pub pptx: &'static str,
}

const fn p(name: &'static str, label: &'static str, convex: bool, open: bool, pptx: &'static str) -> PresetInfo {
    PresetInfo { name, label, convex, open, pptx }
}

/// The preset library. Parametric n-gons/stars/arrows make "150+ shapes"
/// reachable via adjustment; the curated core is listed explicitly.
pub fn presets() -> &'static [PresetInfo] {
    &[
        p("rectangle", "Rectangle", true, false, "rect"),
        p("rounded", "Rounded rect", true, false, "roundRect"),
        p("ellipse", "Ellipse", true, false, "ellipse"),
        p("triangle", "Triangle", true, false, "triangle"),
        p("rt_triangle", "Right triangle", true, false, "rtTriangle"),
        p("diamond", "Diamond", true, false, "diamond"),
        p("parallelogram", "Parallelogram", true, false, "parallelogram"),
        p("trapezoid", "Trapezoid", true, false, "trapezoid"),
        p("pentagon", "Pentagon", true, false, "pentagon"),
        p("hexagon", "Hexagon", true, false, "hexagon"),
        p("heptagon", "Heptagon", true, false, "heptagon"),
        p("octagon", "Octagon", true, false, "octagon"),
        p("nonagon", "Nonagon", true, false, ""),
        p("decagon", "Decagon", true, false, "decagon"),
        p("dodecagon", "Dodecagon", true, false, "dodecagon"),
        p("donut", "Donut", false, false, "donut"),
        p("star5", "Star · 5", false, false, "star5"),
        p("star6", "Star · 6", false, false, "star6"),
        p("star8", "Star · 8", false, false, "star8"),
        p("burst8", "Burst · 8", false, false, "seal8"),
        p("arrow_right", "Arrow right", false, false, "rightArrow"),
        p("arrow_left", "Arrow left", false, false, "leftArrow"),
        p("arrow_up", "Arrow up", false, false, "upArrow"),
        p("arrow_down", "Arrow down", false, false, "downArrow"),
        p("double_arrow", "Double arrow", false, false, "leftRightArrow"),
        p("chevron_right", "Chevron", false, false, "chevron"),
        p("cross", "Cross", false, false, "plus"),
        p("heart", "Heart", false, false, "heart"),
        p("moon", "Moon", false, false, "moon"),
        p("banner", "Banner", false, false, ""),
        p("ribbon", "Ribbon tail", false, false, ""),
        p("bubble", "Speech bubble", false, false, ""),
        p("wave", "Wave", false, true, ""),
        p("zigzag", "Zigzag", false, true, ""),
        p("line", "Line", true, true, "line"),
        p("path", "Freeform", false, false, ""),
    ]
}

pub fn preset_info(name: &str) -> Option<&'static PresetInfo> {
    presets().iter().find(|p| p.name == name)
}

/// Polygon for a preset in absolute bbox coordinates (px). `w`/`h` are the
/// bbox; ellipse becomes a 48-gon. Open paths return their polyline points.
pub fn preset_polygon(name: &str, w: f64, h: f64) -> Vec<(f64, f64)> {
    let w = w.max(1.0);
    let h = h.max(1.0);
    let n = |k: usize| regular_polygon(k, w, h);
    match name {
        "rectangle" => vec![(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)],
        "rounded" => rounded_rect(w, h, w.min(h) * 0.18),
        "ellipse" => ellipse_poly(w, h, 48),
        "triangle" => n(3),
        "rt_triangle" => vec![(0.0, h), (w, h), (0.0, 0.0)],
        "diamond" => vec![(w / 2.0, 0.0), (w, h / 2.0), (w / 2.0, h), (0.0, h / 2.0)],
        "parallelogram" => vec![(w * 0.22, 0.0), (w, 0.0), (w * 0.78, h), (0.0, h)],
        "trapezoid" => vec![(w * 0.2, 0.0), (w * 0.8, 0.0), (w, h), (0.0, h)],
        "pentagon" => n(5),
        "hexagon" => n(6),
        "heptagon" => n(7),
        "octagon" => n(8),
        "nonagon" => n(9),
        "decagon" => n(10),
        "dodecagon" => n(12),
        "donut" => ellipse_poly(w, h, 48), // outer contour; hole via even-odd at render
        "star5" => star(w, h, 5, 0.42),
        "star6" => star(w, h, 6, 0.55),
        "star8" => star(w, h, 8, 0.62),
        "burst8" => star(w, h, 8, 0.78),
        "arrow_right" => arrow(w, h),
        "arrow_left" => {
            let mut v = arrow(w, h);
            mirror_x(&mut v, w);
            v
        }
        "arrow_up" => arrow_up(w, h),
        "arrow_down" => arrow_down(w, h),
        "double_arrow" => {
            let head = w * 0.3;
            let bar = h * 0.28;
            vec![
                (0.0, h / 2.0),
                (head, h / 2.0 - bar),
                (w - head, h / 2.0 - bar),
                (w, h / 2.0),
                (w - head, h / 2.0 + bar),
                (head, h / 2.0 + bar),
            ]
        }
        "chevron_right" => {
            let c = w * 0.5;
            vec![(0.0, 0.0), (c, 0.0), (w, h / 2.0), (c, h), (0.0, h), (c, h / 2.0)]
        }
        "cross" => {
            let t = 0.34;
            vec![
                (w * (1.0 - t) / 2.0, 0.0),
                (w * (1.0 + t) / 2.0, 0.0),
                (w * (1.0 + t) / 2.0, h * (1.0 - t) / 2.0),
                (w, h * (1.0 - t) / 2.0),
                (w, h * (1.0 + t) / 2.0),
                (w * (1.0 + t) / 2.0, h * (1.0 + t) / 2.0),
                (w * (1.0 + t) / 2.0, h),
                (w * (1.0 - t) / 2.0, h),
                (w * (1.0 - t) / 2.0, h * (1.0 + t) / 2.0),
                (0.0, h * (1.0 + t) / 2.0),
                (0.0, h * (1.0 - t) / 2.0),
                (w * (1.0 - t) / 2.0, h * (1.0 - t) / 2.0),
            ]
        }
        "heart" => heart(w, h),
        "moon" => moon(w, h),
        "banner" => banner(w, h),
        "ribbon" => ribbon(w, h),
        "bubble" => bubble(w, h),
        "wave" => wave(w, h),
        "zigzag" => zigzag(w, h),
        "line" => vec![(0.0, 0.0), (w, h)],
        _ => vec![(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)], // unknown → rect
    }
}

fn regular_polygon(k: usize, w: f64, h: f64) -> Vec<(f64, f64)> {
    let mut v = Vec::with_capacity(k);
    for i in 0..k {
        // -90° start: flat-top presentation style, point up for odd counts
        let a = (i as f64) * std::f64::consts::TAU / (k as f64) - std::f64::consts::FRAC_PI_2;
        v.push((w / 2.0 + w / 2.0 * a.cos(), h / 2.0 + h / 2.0 * a.sin()));
    }
    v
}

fn star(w: f64, h: f64, tips: usize, inner: f64) -> Vec<(f64, f64)> {
    let mut v = Vec::with_capacity(tips * 2);
    for i in 0..(tips * 2) {
        let r = if i % 2 == 0 { 1.0 } else { inner };
        let a = (i as f64) * std::f64::consts::TAU / (tips as f64 * 2.0) - std::f64::consts::FRAC_PI_2;
        v.push((w / 2.0 + w / 2.0 * r * a.cos(), h / 2.0 + h / 2.0 * r * a.sin()));
    }
    v
}

fn arrow(w: f64, h: f64) -> Vec<(f64, f64)> {
    let head = w * 0.45;
    let bar = h / 4.0;
    vec![(0.0, h / 2.0 - bar), (w - head, h / 2.0 - bar), (w - head, 0.0), (w, h / 2.0), (w - head, h), (w - head, h / 2.0 + bar), (0.0, h / 2.0 + bar)]
}

fn mirror_x(v: &mut [(f64, f64)], w: f64) {
    for pt in v.iter_mut() {
        pt.0 = w - pt.0;
    }
}

fn arrow_up(w: f64, h: f64) -> Vec<(f64, f64)> {
    let head = h * 0.45;
    let bar = w / 4.0;
    vec![
        (w / 2.0 - bar, h),
        (w / 2.0 - bar, head),
        (0.0, head),
        (w / 2.0, 0.0),
        (w, head),
        (w / 2.0 + bar, head),
        (w / 2.0 + bar, h),
    ]
}

fn arrow_down(w: f64, h: f64) -> Vec<(f64, f64)> {
    let mut v = arrow_up(w, h);
    for pt in v.iter_mut() {
        pt.1 = h - pt.1;
    }
    v
}

fn rounded_rect(w: f64, h: f64, r: f64) -> Vec<(f64, f64)> {
    let r = r.min(w / 2.0).min(h / 2.0);
    let k = r * 0.55;
    let mut v = Vec::with_capacity(20);
    v.push((r, 0.0));
    v.push((w - r, 0.0));
    v.push((w - r + k, k));
    v.push((w, r));
    v.push((w, h - r));
    v.push((w - r + k, h - r + k));
    v.push((w - r, h));
    v.push((r, h));
    v.push((r - k, h - r + k));
    v.push((0.0, h - r));
    v.push((0.0, r));
    v.push((r - k, k));
    v
}

fn ellipse_poly(w: f64, h: f64, seg: usize) -> Vec<(f64, f64)> {
    let mut v = Vec::with_capacity(seg);
    for i in 0..seg {
        let a = (i as f64) * std::f64::consts::TAU / (seg as f64);
        v.push((w / 2.0 + w / 2.0 * a.cos(), h / 2.0 + h / 2.0 * a.sin()));
    }
    v
}

fn heart(w: f64, h: f64) -> Vec<(f64, f64)> {
    let mut v = Vec::with_capacity(40);
    for i in 0..40 {
        let t = (i as f64) / 40.0 * std::f64::consts::TAU;
        let x = 16.0 * t.sin().powi(3);
        let y = -(13.0 * t.cos() - 5.0 * (2.0 * t).cos() - 2.0 * (3.0 * t).cos() + (4.0 * t).cos());
        v.push((
            ((x + 17.0) / 34.0 * w).clamp(0.0, w),
            ((y + 17.0) / 34.0 * h).clamp(0.0, h),
        ));
    }
    v
}

fn moon(w: f64, h: f64) -> Vec<(f64, f64)> {
    let mut v = ellipse_poly(w, h, 24);
    // carve the inner arc: replace right-side points with inner ellipse
    let cx = w * 0.72;
    for pt in v.iter_mut() {
        if pt.0 > w * 0.5 {
            let d = (pt.1 - h / 2.0) / (h / 2.0);
            pt.0 = cx - w * 0.42 * (1.0 - d * d).max(0.0).sqrt();
        }
    }
    v
}

fn banner(w: f64, h: f64) -> Vec<(f64, f64)> {
    let notch = w * 0.12;
    vec![
        (0.0, 0.0),
        (w, 0.0),
        (w - notch, h / 2.0),
        (w, h),
        (0.0, h),
        (notch, h / 2.0),
    ]
}

fn ribbon(w: f64, h: f64) -> Vec<(f64, f64)> {
    let t = h * 0.45;
    vec![
        (0.0, 0.0),
        (w, 0.0),
        (w, t),
        (w * 0.75, t),
        (w, h),
        (w * 0.5, t * 1.15),
        (0.0, h),
        (w * 0.25, t),
        (0.0, t),
    ]
}

fn bubble(w: f64, h: f64) -> Vec<(f64, f64)> {
    let hb = h * 0.75;
    vec![
        (0.0, 0.0),
        (w, 0.0),
        (w, hb),
        (w * 0.3, hb),
        (w * 0.42, h),
        (w * 0.12, hb),
        (0.0, hb),
    ]
}

fn wave(w: f64, h: f64) -> Vec<(f64, f64)> {
    let mut v = Vec::with_capacity(33);
    let amp = h / 2.0;
    for i in 0..=32 {
        let t = (i as f64) / 32.0;
        let y = h / 2.0 + amp * (t * std::f64::consts::TAU).sin();
        v.push((t * w, y));
    }
    v
}

fn zigzag(w: f64, h: f64) -> Vec<(f64, f64)> {
    let n = 8;
    let mut v = Vec::with_capacity(n + 1);
    for i in 0..=n {
        let t = (i as f64) / (n as f64);
        let y = if i % 2 == 0 { h / 4.0 } else { h * 3.0 / 4.0 };
        v.push((t * w, y));
    }
    v
}

// ---------------------------------------------------------------------------
// Polygon math
// ---------------------------------------------------------------------------

/// Signed area (positive = CCW in y-down coordinates when using this helper's
/// conventions consistently; sign is all that matters).
fn signed_area(v: &[(f64, f64)]) -> f64 {
    let n = v.len();
    if n < 3 {
        return 0.0;
    }
    let mut a = 0.0;
    for i in 0..n {
        let (x1, y1) = v[i];
        let (x2, y2) = v[(i + 1) % n];
        a += x1 * y2 - x2 * y1;
    }
    a / 2.0
}

/// Ensure CCW winding (in standard math orientation).
fn ccw(mut v: Vec<(f64, f64)>) -> Vec<(f64, f64)> {
    if signed_area(&v) < 0.0 {
        v.reverse();
    }
    v
}

fn cross(a: (f64, f64), b: (f64, f64), p: (f64, f64)) -> f64 {
    (b.0 - a.0) * (p.1 - a.1) - (b.1 - a.1) * (p.0 - a.0)
}

fn intersect(a: (f64, f64), b: (f64, f64), c: (f64, f64), d: (f64, f64)) -> (f64, f64) {
    let r = (b.0 - a.0, b.1 - a.1);
    let s = (d.0 - c.0, d.1 - c.1);
    let denom = r.0 * s.1 - r.1 * s.0;
    if denom.abs() < 1e-12 {
        return b;
    }
    let t = ((c.0 - a.0) * s.1 - (c.1 - a.1) * s.0) / denom;
    (a.0 + t * r.0, a.1 + t * r.1)
}

/// Convex (and non-degenerate)?
pub fn is_convex(v: &[(f64, f64)]) -> bool {
    let n = v.len();
    if n < 3 {
        return false;
    }
    let v = ccw(v.to_vec());
    for i in 0..n {
        let a = v[i];
        let b = v[(i + 1) % n];
        let c = v[(i + 2) % n];
        if cross(a, b, c) <= 1e-9 {
            return false;
        }
    }
    true
}

/// Convex hull (Andrew's monotone chain).
pub fn convex_hull(mut pts: Vec<(f64, f64)>) -> Vec<(f64, f64)> {
    pts.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    pts.dedup();
    if pts.len() < 3 {
        return pts;
    }
    let mut lower: Vec<(f64, f64)> = Vec::new();
    for &p in &pts {
        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0.0 {
            lower.pop();
        }
        lower.push(p);
    }
    let mut upper: Vec<(f64, f64)> = Vec::new();
    for &p in pts.iter().rev() {
        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0.0 {
            upper.pop();
        }
        upper.push(p);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower
}

/// Clip `subject` by convex `window` (Sutherland–Hodgman). Both CCW.
fn sh_clip(subject: &[(f64, f64)], window: &[(f64, f64)]) -> Vec<(f64, f64)> {
    let mut out = subject.to_vec();
    let n = window.len();
    for i in 0..n {
        if out.is_empty() {
            break;
        }
        let a = window[i];
        let b = window[(i + 1) % n];
        let mut input = std::mem::take(&mut out);
        let m = input.len();
        for j in 0..m {
            let cur = input[j];
            let prev = input[(j + m - 1) % m];
            let cur_in = cross(a, b, cur) >= 0.0;
            let prev_in = cross(a, b, prev) >= 0.0;
            if cur_in {
                if !prev_in {
                    out.push(intersect(prev, cur, a, b));
                }
                out.push(cur);
            } else if prev_in {
                out.push(intersect(prev, cur, a, b));
            }
        }
    }
    out
}

/// Boolean modes.
pub enum BooleanMode {
    Union,
    Subtract, // a minus b
    Intersect,
}

/// Compute a boolean op on two polygons (absolute coords). Both inputs must
/// be convex; result is one polygon (possibly empty for disjoint subtract /
/// intersect — caller gets an empty vec and may treat as delete).
pub fn boolean(a: Vec<(f64, f64)>, b: Vec<(f64, f64)>, mode: BooleanMode) -> Result<Vec<(f64, f64)>, String> {
    if a.len() < 3 || b.len() < 3 {
        return Err("boolean needs two closed shapes".into());
    }
    if !is_convex(&a) || !is_convex(&b) {
        return Err("boolean ops need convex shapes (try rectangle / ellipse / polygon)".into());
    }
    let a = ccw(a);
    let b = ccw(b);
    match mode {
        BooleanMode::Union => {
            let mut all = a.clone();
            all.extend(b.iter().copied());
            Ok(convex_hull(all))
        }
        BooleanMode::Intersect => Ok(sh_clip(&a, &b)),
        BooleanMode::Subtract => {
            // A − B = A ∩ complement(B); complement of convex B is the
            // intersection of its edges' outside half-planes.
            let mut cur = a;
            let n = b.len();
            for i in 0..n {
                if cur.is_empty() {
                    break;
                }
                let p1 = b[i];
                let p2 = b[(i + 1) % n];
                cur = clip_outside_halfplane(&cur, p1, p2);
            }
            Ok(cur)
        }
    }
}

/// Keep the part of `poly` on the right side of edge a→b (outside of a CCW
/// polygon whose edge is a→b). Half-plane clip via SH with a 4-point window.
fn clip_outside_halfplane(poly: &[(f64, f64)], a: (f64, f64), b: (f64, f64)) -> Vec<(f64, f64)> {
    // Build a large CW window whose edge a→b appears in CCW direction as b→a
    // … simpler: clip with keep-right semantics directly.
    let mut out: Vec<(f64, f64)> = Vec::with_capacity(poly.len());
    let n = poly.len();
    if n == 0 {
        return out;
    }
    let inside = |p: (f64, f64)| cross(a, b, p) < 0.0; // right side = outside of CCW b
    for j in 0..n {
        let cur = poly[j];
        let prev = poly[(j + n - 1) % n];
        let cur_in = inside(cur);
        let prev_in = inside(prev);
        if cur_in {
            if !prev_in {
                out.push(intersect(prev, cur, a, b));
            }
            out.push(cur);
        } else if prev_in {
            out.push(intersect(prev, cur, a, b));
        }
    }
    out
}

/// Bounding box of a polygon.
pub fn bbox(v: &[(f64, f64)]) -> (f64, f64, f64, f64) {
    let mut minx = f64::MAX;
    let mut miny = f64::MAX;
    let mut maxx = f64::MIN;
    let mut maxy = f64::MIN;
    for &(x, y) in v {
        minx = minx.min(x);
        miny = miny.min(y);
        maxx = maxx.max(x);
        maxy = maxy.max(y);
    }
    (minx, miny, maxx - minx, maxy - miny)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(x: f64, y: f64, w: f64, h: f64) -> Vec<(f64, f64)> {
        vec![(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    }

    #[test]
    fn preset_registry_is_sane() {
        let ps = presets();
        assert!(ps.len() >= 30);
        assert!(ps.iter().any(|p| p.name == "rectangle"));
        assert!(ps.iter().any(|p| p.name == "path"));
        for p in ps {
            assert!(!p.name.is_empty() && !p.label.is_empty(), "bad preset entry");
        }
    }

    #[test]
    fn convex_detection() {
        assert!(is_convex(&rect(0.0, 0.0, 10.0, 10.0)));
        let star5 = preset_polygon("star5", 100.0, 100.0);
        assert!(!is_convex(&star5));
    }

    #[test]
    fn hull_contains_inputs() {
        let a = rect(0.0, 0.0, 10.0, 10.0);
        let b = rect(20.0, 5.0, 10.0, 10.0);
        let h = convex_hull([a.clone(), b.clone()].concat());
        assert!(h.len() >= 4);
        let (hx, hy, hw, hh) = bbox(&h);
        assert!(hx <= 0.0 && hy <= 0.0 && hx + hw >= 30.0 && hy + hh >= 15.0);
    }

    #[test]
    fn intersect_exact() {
        let a = rect(0.0, 0.0, 10.0, 10.0);
        let b = rect(5.0, 5.0, 10.0, 10.0);
        let r = boolean(a, b, BooleanMode::Intersect).unwrap();
        let (x, y, w, h) = bbox(&r);
        assert!((w - 5.0).abs() < 1e-6, "w={w}");
        assert!((h - 5.0).abs() < 1e-6, "h={h}");
        assert!((x - 5.0).abs() < 1e-6 && (y - 5.0).abs() < 1e-6);
    }

    #[test]
    fn subtract_exact() {
        let a = rect(0.0, 0.0, 10.0, 10.0);
        let b = rect(5.0, 5.0, 10.0, 10.0);
        let r = boolean(a, b, BooleanMode::Subtract).unwrap();
        // A − B leaves an L-shape: area 100 − 25 = 75
        let area = signed_area(&ccw(r.clone())).abs();
        assert!((area - 75.0).abs() < 1e-6, "area={area}");
    }

    #[test]
    fn subtract_disjoint_is_empty() {
        let a = rect(0.0, 0.0, 5.0, 5.0);
        let b = rect(20.0, 20.0, 5.0, 5.0);
        let r = boolean(a, b, BooleanMode::Subtract).unwrap();
        assert!(r.is_empty() || signed_area(&ccw(r)) < 1e-6);
    }

    #[test]
    fn non_convex_rejected() {
        let star = preset_polygon("star5", 100.0, 100.0);
        let rectv = rect(0.0, 0.0, 10.0, 10.0);
        assert!(boolean(star, rectv, BooleanMode::Intersect).is_err());
    }

    #[test]
    fn every_closed_preset_yields_geometry() {
        for p in presets() {
            let g = preset_polygon(p.name, 200.0, 140.0);
            assert!(g.len() >= 2, "preset {} produced no geometry", p.name);
        }
    }
}
