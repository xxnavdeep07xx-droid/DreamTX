//! Minimal-but-valid .pptx writer (OOXML, any deck aspect). Pure Rust: zip +
//! hand-built XML. Text boxes carry explicit sizes from the layout solver;
//! viewers render text with local font fallback, so no font embedding is
//! required for v0.1 (M2 adds subsetting + embedding).
//!
//! Objects that carry `content` (text boxes, images, icons, media, tables)
//! export as REAL content in `slide.objects` Z-order: rich-text boxes with
//! runs/paragraph styles, images embedded into `ppt/media/*` with
//! relationships, tables as graphic frames, icons and media as clean
//! cards. A missing image asset falls back to a clean placeholder box.

use crate::dna::resolve;
use crate::export::{ExportImage, doc_paragraphs, para_anchor_at, run_pieces, utf16_slice};
use crate::fonts;
use crate::layout::{layout_slide, Element};
use crate::model::{
    ArrowHead, ChartSeries, ChartStyle, DashStyle, Deck, Fill, LinkKind, ObjectContent, Shape, TextDoc,
    SLIDE_H, deck_dims,
};
use crate::shapes;
use std::collections::BTreeMap;
use std::io::Write;

const EMU: f64 = 9525.0; // 1280x720 px -> 12192000x6858000 EMU

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            _ => out.push(c),
        }
    }
    out
}

/// Add a `<a:hlinkClick>` to a shape fragment's `<p:cNvPr …/>`, so the whole
/// object becomes clickable. `action` is the PPTX `ppaction://` verb for
/// slide jumps; web links pass `None`.
fn with_link(frag: String, rid: &str, action: Option<&str>) -> String {
    let Some(start) = frag.find("<p:cNvPr ") else { return frag };
    let Some(rel) = frag[start..].find("/>") else { return frag };
    let end = start + rel;
    let attr = action.map(|a| format!(" action=\"{a}\"")).unwrap_or_default();
    format!(
        "{}><a:hlinkClick r:id=\"{rid}\"{attr}/></p:cNvPr>{}",
        &frag[..end],
        &frag[end + 2..]
    )
}

/// The chart part (DrawingML chart) for a native chart: literal categories
/// and values, so it opens without an embedded workbook.
fn chart_xml(
    style: ChartStyle,
    title: Option<&str>,
    labels: &[String],
    series: &[ChartSeries],
    palette: &[String],
) -> String {
    let n = labels.len();
    let cat: String = {
        let pts: String = labels
            .iter()
            .enumerate()
            .map(|(i, l)| format!(r#"<c:pt idx="{i}"><c:v>{}</c:v></c:pt>"#, esc(l)))
            .collect();
        format!(r#"<c:cat><c:strLit><c:ptCount val="{n}"/>{pts}</c:strLit></c:cat>"#)
    };
    // A pie shows only its first series, one colored slice per label.
    let used: &[ChartSeries] = if style == ChartStyle::Pie { &series[..series.len().min(1)] } else { series };
    let sers: String = used
        .iter()
        .enumerate()
        .map(|(si, s)| {
            let vals: String = s
                .values
                .iter()
                .enumerate()
                .filter(|(_, v)| v.is_finite())
                .map(|(i, v)| format!(r#"<c:pt idx="{i}"><c:v>{v}</c:v></c:pt>"#))
                .collect();
            let val = format!(
                r#"<c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="{}"/>{vals}</c:numLit></c:val>"#,
                s.values.len()
            );
            let tx = format!(r#"<c:tx><c:v>{}</c:v></c:tx>"#, esc(&s.name));
            let color = s.color_at(si, palette);
            let (sp, dpts, tail) = match style {
                ChartStyle::Line => (
                    format!(
                        r#"<c:spPr><a:ln w="28575"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill></a:ln></c:spPr><c:marker><c:symbol val="circle"/><c:size val="6"/></c:marker>"#
                    ),
                    String::new(),
                    r#"<c:smooth val="0"/>"#,
                ),
                ChartStyle::Pie => (
                    String::new(),
                    (0..n)
                        .map(|i| {
                            format!(
                                r#"<c:dPt><c:idx val="{i}"/><c:bubble3D val="0"/><c:spPr><a:solidFill><a:srgbClr val="{}"/></a:solidFill></c:spPr></c:dPt>"#,
                                s.color_at(i, palette)
                            )
                        })
                        .collect(),
                    "",
                ),
                _ => (
                    format!(
                        r#"<c:spPr><a:solidFill><a:srgbClr val="{color}"/></a:solidFill></c:spPr><c:invertIfNegative val="0"/>"#
                    ),
                    String::new(),
                    "",
                ),
            };
            format!(
                r#"<c:ser><c:idx val="{si}"/><c:order val="{si}"/>{tx}{sp}{dpts}{cat}{val}{tail}</c:ser>"#
            )
        })
        .collect();
    let axis_ids = r#"<c:axId val="1001"/><c:axId val="1002"/>"#;
    let (plot, axes) = match style {
        ChartStyle::Column | ChartStyle::Bar => {
            let dir = if style == ChartStyle::Bar { "bar" } else { "col" };
            let (cat_pos, val_pos) = if style == ChartStyle::Bar { ("l", "b") } else { ("b", "l") };
            (
                format!(
                    r#"<c:barChart><c:barDir val="{dir}"/><c:grouping val="clustered"/><c:varyColors val="0"/>{sers}<c:gapWidth val="150"/>{axis_ids}</c:barChart>"#
                ),
                format!(
                    r#"<c:catAx><c:axId val="1001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="{cat_pos}"/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="low"/><c:crossAx val="1002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx><c:valAx><c:axId val="1002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="{val_pos}"/><c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="1001"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>"#
                ),
            )
        }
        ChartStyle::Line => (
            format!(
                r#"<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>{sers}<c:marker val="1"/>{axis_ids}</c:lineChart>"#
            ),
            format!(
                r#"<c:catAx><c:axId val="1001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="low"/><c:crossAx val="1002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx><c:valAx><c:axId val="1002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="1001"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>"#
            ),
        ),
        ChartStyle::Pie => (
            format!(r#"<c:pieChart><c:varyColors val="1"/>{sers}<c:firstSliceAng val="0"/></c:pieChart>"#),
            String::new(),
        ),
    };
    let title_xml = match title.filter(|t| !t.is_empty()) {
        Some(t) => format!(
            r#"<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>{}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/>"#,
            esc(t)
        ),
        None => r#"<c:autoTitleDeleted val="1"/>"#.to_string(),
    };
    let legend = if series.len() > 1 || style == ChartStyle::Pie {
        r#"<c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>"#
    } else {
        ""
    };
    format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><c:roundedCorners val="0"/><c:chart>{title_xml}<c:plotArea><c:layout/>{plot}{axes}</c:plotArea>{legend}<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>"#
    )
}

/// The slide's graphic frame that holds a chart part (relationship `rid`).
fn chart_frame_sp(o: &Shape, rid: &str, id: u32) -> String {
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    format!(
        r#"<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{id}" name="chart{id}"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="{rid}"/></a:graphicData></a:graphic></p:graphicFrame>"#
    )
}

fn pt(size_px: f64) -> i32 {
    (size_px * 0.75).round() as i32 // px -> pt at 96dpi
}

/// The app's text-box base size (kTextBoxBaseSize) — the export default
/// when a run/doc carries no explicit size.
const BASE_FONT_PX: f64 = 32.0;

/// The text box painter's design-space insets (px) — exported as real
/// bodyPr insets so PowerPoint text sits where the app paints it.
const BOX_PAD_X: f64 = 14.0;
const BOX_PAD_Y: f64 = 10.0;

fn typeface(serif: bool, bold: bool) -> &'static str {
    match (serif, bold) {
        (true, true) => "DejaVu Serif",
        (true, false) => "DejaVu Serif",
        (false, _) => "DejaVu Sans",
    }
}

fn run_typeface(family: Option<&str>) -> &'static str {
    match family {
        Some("serif") => "DejaVu Serif",
        Some("mono") => "DejaVu Sans Mono",
        _ => "DejaVu Sans",
    }
}

fn rect_sp(x: f64, y: f64, w: f64, h: f64, color: &str, radius: f64, id: u32) -> String {
    let round = if radius > 0.0 {
        format!(r#"<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val {}"/></a:avLst></a:prstGeom>"#, (radius / w.min(h) * 1000.0).clamp(0.0, 50000.0) as u32)
    } else {
        r#"<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>"#.to_string()
    };
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="rect{id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{cx}" cy="{cy}"/>{a}{fill}</p:spPr><p:txBody><a:bodyPr/><a:p/></p:txBody></p:sp>"#,
        x = (x * EMU).round() as i64,
        y = (y * EMU).round() as i64,
        cx = (w * EMU).round() as i64,
        cy = (h * EMU).round() as i64,
        a = round,
        fill = format!(r#"<a:solidFill><a:srgbClr val="{}"/></a:solidFill>"#, esc(color)),
        id = id
    )
}

fn pptx_color(color: &str, alpha: f64) -> String {
    if alpha < 0.999 {
        format!(
            r#"<a:srgbClr val="{}"><a:alpha val="{}"/></a:srgbClr>"#,
            esc(color),
            (alpha * 100000.0).round().clamp(0.0, 100000.0) as u32
        )
    } else {
        format!(r#"<a:srgbClr val="{}"/></a:srgbClr>"#, esc(color))
    }
}

fn pptx_fill(fill: &Fill, alpha: f64) -> String {
    match fill {
        Fill::None => "<a:noFill/>".into(),
        Fill::Solid { color } => format!("<a:solidFill>{}</a:solidFill>", pptx_color(color, alpha)),
        Fill::LinearGradient { angle, from, to } => format!(
            r#"<a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0">{}</a:gs><a:gs pos="100000">{}</a:gs></a:gsLst><a:lin ang="{}" scaled="0"/></a:gradFill>"#,
            pptx_color(from, alpha),
            pptx_color(to, alpha),
            ((angle.rem_euclid(360.0)) * 60000.0).round() as i64
        ),
        Fill::RadialGradient { from, to } => format!(
            r#"<a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0">{}</a:gs><a:gs pos="100000">{}</a:gs></a:gsLst><a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path></a:gradFill>"#,
            pptx_color(from, alpha),
            pptx_color(to, alpha)
        ),
    }
}

fn pptx_dash(d: &DashStyle) -> &'static str {
    match d {
        DashStyle::Solid => "solid",
        DashStyle::Dash => "dash",
        DashStyle::Dot => "sysDot",
        DashStyle::DashDot => "dashDot",
    }
}

fn pptx_arrow(a: &ArrowHead) -> &'static str {
    match a {
        ArrowHead::None => "none",
        ArrowHead::Arrow => "arrow",
        ArrowHead::Triangle => "triangle",
    }
}

/// A manual vector object (overlay layer) as an OOXML shape.
fn shape_sp(o: &Shape, id: u32) -> String {
    // geometry: preset name when mapped, else custGeom from points/polygon
    let has_points = o.points.as_ref().is_some_and(|p| !p.is_empty());
    let mapped = shapes::preset_info(&o.preset).filter(|i| !i.pptx.is_empty());
    let geom = match (&mapped, has_points) {
        (Some(info), false) => format!(r#"<a:prstGeom prst="{}"><a:avLst/></a:prstGeom>"#, info.pptx),
        _ => {
            // normalized (0..1000) path space
            let poly = crate::command::object_polygon(o);
            let (bx, by, bw, bh) = shapes::bbox(&poly);
            let (bw, bh) = (bw.max(1.0), bh.max(1.0));
            let mut paths = String::new();
            let mut pts = String::new();
            for (k, &(x, y)) in poly.iter().enumerate() {
                let px = (((x - bx) / bw).clamp(0.0, 1.0) * 1000.0).round() as i64;
                let py = (((y - by) / bh).clamp(0.0, 1.0) * 1000.0).round() as i64;
                if k == 0 {
                    pts.push_str(&format!("<a:moveTo><a:pt x=\"{px}\" y=\"{py}\"/></a:moveTo>"));
                } else {
                    pts.push_str(&format!("<a:lnTo><a:pt x=\"{px}\" y=\"{py}\"/></a:lnTo>"));
                }
            }
            let close = if o.closed { "<a:close/>" } else { "" };
            paths.push_str(&format!("<a:path w=\"1000\" h=\"1000\">{pts}{close}</a:path>"));
            // holes: reversed-winding subpaths (holes under the winding rule)
            if let Some(holes) = &o.holes {
                for h in holes {
                    let mut hp = String::new();
                    for (k, p) in h.iter().rev().enumerate() {
                        let px = (p.x.clamp(0.0, 1.0) * 1000.0).round() as i64;
                        let py = (p.y.clamp(0.0, 1.0) * 1000.0).round() as i64;
                        if k == 0 {
                            hp.push_str(&format!("<a:moveTo><a:pt x=\"{px}\" y=\"{py}\"/></a:moveTo>"));
                        } else {
                            hp.push_str(&format!("<a:lnTo><a:pt x=\"{px}\" y=\"{py}\"/></a:lnTo>"));
                        }
                    }
                    hp.push_str("<a:close/>");
                    paths.push_str(&format!("<a:path w=\"1000\" h=\"1000\">{hp}</a:path>"));
                }
            }
            format!(r#"<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:rectLst/><a:pathLst>{paths}</a:pathLst></a:custGeom>"#)
        }
    };

    let rot = ((o.rotation.rem_euclid(360.0)) * 60000.0).round() as i64;
    let rot_attr = if rot != 0 { format!(" rot=\"{rot}\"") } else { String::new() };

    // stroke / line
    let ln = if o.stroke.width > 0.0 {
        let w_emu = (o.stroke.width * EMU).round() as i64;
        let heads = if o.stroke.start_arrow != ArrowHead::None {
            format!(r#"<a:headEnd type="{}" w="med" len="med"/>"#, pptx_arrow(&o.stroke.start_arrow))
        } else {
            String::new()
        };
        let tails = if o.stroke.end_arrow != ArrowHead::None {
            format!(r#"<a:tailEnd type="{}" w="med" len="med"/>"#, pptx_arrow(&o.stroke.end_arrow))
        } else {
            String::new()
        };
        let stroke_fill = pptx_color(&o.stroke.color, o.opacity);
        let dashv = pptx_dash(&o.stroke.dash);
        format!(r#"<a:ln w="{w_emu}" cap="rnd"><a:solidFill>{stroke_fill}</a:solidFill><a:prstDash val="{dashv}"/>{heads}{tails}</a:ln>"#)
    } else {
        "<a:ln><a:noFill/></a:ln>".into()
    };

    // effects
    let mut eff = String::new();
    if let Some(sh) = &o.effects.shadow {
        let dist = (sh.dx.hypot(sh.dy) * EMU).round() as i64;
        let dir = (sh.dx.atan2(sh.dy).to_degrees().rem_euclid(360.0) * 60000.0).round() as i64;
        let blur_rad = (sh.blur * EMU).round() as i64;
        let sh_color = pptx_color(&sh.color, sh.opacity);
        eff.push_str(&format!(
            r#"<a:outerShdw blurRad="{blur_rad}" dist="{dist}" dir="{dir}" rotWithShape="0">{sh_color}</a:outerShdw>"#
        ));
    }
    if let Some(gl) = &o.effects.glow {
        let glow_rad = (gl.blur * EMU).round() as i64;
        let gl_color = pptx_color(&gl.color, 0.6 * o.opacity.max(0.0));
        eff.push_str(&format!(r#"<a:glow rad="{glow_rad}">{gl_color}</a:glow>"#));
    }
    let effects = if eff.is_empty() {
        String::new()
    } else {
        format!("<a:effectLst>{eff}</a:effectLst>")
    };

    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    let fillxml = pptx_fill(&o.fill, o.opacity);
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="shape{id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm{rot_attr}><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm>{geom}{fillxml}{ln}{effects}</p:spPr><p:txBody><a:bodyPr/><a:p/></p:txBody></p:sp>"#
    )
}

fn text_sp(el: &Element, id: u32) -> String {
    let Element::Text { x, y, w, h, lines, size, color, font, bold, align, .. } = el else { unreachable!("text_sp expects Text") };
    let serif = matches!(font, crate::dna::FontRole::Serif);
    let (x, y, w, h, size, bold, align) = (*x, *y, *w, *h, *size, *bold, *align);
    let lines: &[String] = lines;
    let color: &str = color;
    let algn = match align {
        crate::layout::Align::Left => "l",
        crate::layout::Align::Center => "ctr",
        crate::layout::Align::Right => "r",
    };
    let mut paras = String::new();
    for line in lines {
        paras.push_str(&format!(
            r#"<a:p><a:pPr algn="{algn}"/><a:r><a:rPr lang="en-US" sz="{sz}"{b}><a:solidFill><a:srgbClr val="{}"/></a:solidFill><a:latin typeface="{face}"/><a:ea typeface="Noto Sans SC"/></a:rPr><a:t>{}</a:t></a:r></a:p>"#,
            esc(color),
            esc(line),
            algn = algn,
            sz = pt(size).max(1) * 100,
            b = if bold { " b=\"1\"" } else { "" },
            face = typeface(serif, bold)
        ));
    }
    if paras.is_empty() {
        paras.push_str("<a:p/>");
    }
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="text{id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="none" anchor="t" lIns="0" tIns="0" rIns="0" bIns="0">{autosize}</a:bodyPr>{paras}</p:txBody></p:sp>"#,
        x = (x * EMU).round() as i64,
        y = (y * EMU).round() as i64,
        cx = (w * EMU).round() as i64,
        cy = (h * EMU).round() as i64,
        autosize = "", // explicit sizes; PowerPoint re-renders with its own fonts
        paras = paras,
        id = id
    )
}

// ---------------------------------------------------------------------------
// ObjectContent export — the same layered canvas the app renders
// ---------------------------------------------------------------------------

fn align_code(a: Option<crate::model::TextAlign>) -> &'static str {
    match a {
        Some(crate::model::TextAlign::Center) => "ctr",
        Some(crate::model::TextAlign::Right) => "r",
        Some(crate::model::TextAlign::Justify) => "just",
        _ => "l",
    }
}

fn valign_code(v: &crate::model::VerticalAlign) -> &'static str {
    match v {
        crate::model::VerticalAlign::Top => "t",
        crate::model::VerticalAlign::Middle => "ctr",
        crate::model::VerticalAlign::Bottom => "b",
    }
}

/// The app's list indent step (design px).
const INDENT_STEP: f64 = 36.0;

/// Autofit shrink estimate for a text box (mirrors the painter's): wrap each
/// paragraph at the base size, compare total height with the box, return the
/// scale factor (>= 0.05, 1.0 when it fits or autofit is off).
fn autofit_scale(doc: &TextDoc, w: f64, h: f64) -> f64 {
    if doc.text.is_empty() || doc.autofit != crate::model::Autofit::Shrink {
        return 1.0;
    }
    let inner = (w - BOX_PAD_X * 2.0).max(1.0);
    let mut total = 0.0;
    for (ps, pe) in doc_paragraphs(doc) {
        let para = para_anchor_at(doc, ps);
        let indent = para.and_then(|p| p.indent).unwrap_or(0) as f64;
        let line_spacing = para.and_then(|p| p.line_spacing).unwrap_or(1.15);
        let text = utf16_slice(&doc.text, ps, pe.max(ps));
        for line in fonts::wrap(&text, inner - indent * INDENT_STEP, BASE_FONT_PX, false, false) {
            total += BASE_FONT_PX * 1.28 * line_spacing;
            let _ = line;
        }
    }
    let avail = (h - BOX_PAD_Y * 2.0).max(0.0);
    if total <= avail || total <= 0.0 {
        1.0
    } else {
        (avail / total).clamp(0.05, 1.0)
    }
}

/// A rich text box object as an OOXML shape with a real txBody: runs carry
/// bold/italic/underline/strike/sub/sup, color, highlight, family and size;
/// paragraphs carry alignment, bullets/numbers, indent and line spacing;
/// the body carries vertical alignment and autofit shrink.
fn text_object_sp(o: &Shape, doc: &TextDoc, base_fg: &str, id: u32) -> String {
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;

    let k = autofit_scale(doc, o.w, o.h);
    let font_scale_pct = (k * 100000.0).round().clamp(5000.0, 100000.0) as u32;
    let fit = if doc.autofit == crate::model::Autofit::Shrink {
        format!(r#"<a:normAutofit fontScale="{font_scale_pct}" lnSpcReduction="0"/>"#)
    } else {
        String::new()
    };

    let mut paras = String::new();
    for (ps, pe) in doc_paragraphs(doc) {
        let anchor = para_anchor_at(doc, ps);
        let align = anchor.and_then(|p| p.align);
        let list_kind = anchor.and_then(|p| p.list).unwrap_or(crate::model::ListKind::None);
        let indent = anchor.and_then(|p| p.indent).unwrap_or(0);
        let line_spacing = anchor.and_then(|p| p.line_spacing).unwrap_or(1.15);

        let marl_emu = (indent as f64 * INDENT_STEP * EMU).round() as i64;
        let bullet = match list_kind {
            crate::model::ListKind::Bullet => r##"<a:buChar char="•"/>"##.to_string(),
            crate::model::ListKind::Number => r#"<a:buAutoNum type="arabicPeriod"/>"#.to_string(),
            crate::model::ListKind::None => "<a:buNone/>".to_string(),
        };
        let algn = align_code(align);
        let spc_pct = ((line_spacing - 1.0) * 100000.0).round().clamp(-100000.0, 200000.0) as i32;
        let spacing = if spc_pct != 0 {
            format!(r#"<a:spcPct val="{spc_pct}"/>"#)
        } else {
            String::new()
        };
        paras.push_str(&format!(
            r#"<a:p><a:pPr algn="{algn}" marL="{marl_emu}" indent="-{marl_emu}">{spacing}{bullet}</a:pPr>"#
        ));

        for piece in run_pieces(doc, ps, pe) {
            let text = utf16_slice(&doc.text, piece.start, piece.end);
            if text.is_empty() {
                continue;
            }
            let run = piece.run;
            let bold = run.and_then(|r| r.bold).unwrap_or(false);
            let italic = run.and_then(|r| r.italic).unwrap_or(false);
            let underline = run.and_then(|r| r.underline).unwrap_or(false);
            let strike = run.and_then(|r| r.strike).unwrap_or(false);
            let color = run
                .and_then(|r| r.color.as_deref())
                .unwrap_or(base_fg);
            let family = run.and_then(|r| r.font_family.as_deref());
            let size = run
                .and_then(|r| r.font_size)
                .map(|s| s * k)
                .unwrap_or(BASE_FONT_PX * k);
            let baseline = match (run.and_then(|r| r.subscript), run.and_then(|r| r.superscript)) {
                (Some(true), _) => r#" baseline="-25000""#,
                (_, Some(true)) => r#" baseline="30000""#,
                _ => "",
            };
            let highlight = match run.and_then(|r| r.highlight.as_deref()) {
                Some(h) => format!(r#"<a:highlight><a:srgbClr val="{}"/></a:highlight>"#, esc(h)),
                None => String::new(),
            };
            let fill = format!(r#"<a:solidFill><a:srgbClr val="{}"/></a:solidFill>"#, esc(color));
            let face = run_typeface(family);
            paras.push_str(&format!(
                r#"<a:r><a:rPr lang="en-US" sz="{sz}"{b}{i}{u}{strike_attr}{baseline} dirty="0">{fill}{highlight}<a:latin typeface="{face}"/><a:ea typeface="Noto Sans SC"/></a:rPr><a:t>{text}</a:t></a:r>"#,
                sz = (pt(size).max(1) * 100),
                b = if bold { r#" b="1""# } else { "" },
                i = if italic { r#" i="1""# } else { "" },
                u = if underline { r#" u="sng""# } else { "" },
                strike_attr = if strike { r#" strike="sngStrike""# } else { "" },
                text = esc(&text),
            ));
        }
        paras.push_str("</a:p>");
    }
    if paras.is_empty() {
        paras.push_str("<a:p/>");
    }

    let ins_x = (BOX_PAD_X * EMU).round() as i64;
    let ins_y = (BOX_PAD_Y * EMU).round() as i64;
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="textbox{id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap="square" anchor="{anchor}" lIns="{ins_x}" tIns="{ins_y}" rIns="{ins_x}" bIns="{ins_y}">{fit}</a:bodyPr>{paras}</p:txBody></p:sp>"#,
        id = id,
        x_emu = x_emu,
        y_emu = y_emu,
        cx_emu = cx_emu,
        cy_emu = cy_emu,
        anchor = valign_code(&doc.valign),
        ins_x = ins_x,
        ins_y = ins_y,
        fit = fit,
        paras = paras,
    )
}

/// A table object as an OOXML graphic frame: real grid geometry, borders
/// from the object's stroke, and the cell texts.
fn table_sp(o: &Shape, rows: u32, cols: u32, cells: &[String], base_fg: &str, id: u32) -> String {
    let rows = rows.max(1);
    let cols = cols.max(1);
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    let col_w = cx_emu / cols as i64;
    let row_h = cy_emu / rows as i64;

    let stroke = &o.stroke;
    let line = if stroke.width > 0.0 {
        let w = ((stroke.width * EMU).round() as i64).max(1);
        format!(
            r#"<a:lnL w="{w}" cap="flat"><a:solidFill><a:srgbClr val="{}"/></a:solidFill></a:lnL><a:lnR w="{w}" cap="flat"><a:solidFill><a:srgbClr val="{}"/></a:solidFill></a:lnR><a:lnT w="{w}" cap="flat"><a:solidFill><a:srgbClr val="{}"/></a:solidFill></a:lnT><a:lnB w="{w}" cap="flat"><a:solidFill><a:srgbClr val="{}"/></a:solidFill></a:lnB>"#,
            esc(&stroke.color), esc(&stroke.color), esc(&stroke.color), esc(&stroke.color)
        )
    } else {
        String::new()
    };

    // The app's table painter: fontSize min(base*0.62, cellH*0.42).
    let cell_h = o.h / rows as f64;
    let cell_px = (BASE_FONT_PX * 0.62).min(cell_h * 0.42).max(8.0);
    let sz = pt(cell_px).max(1) * 100;

    let mut grid_cols = String::new();
    for _ in 0..cols {
        grid_cols.push_str(&format!(r#"<a:gridCol w="{col_w}"/>"#));
    }
    let mut trs = String::new();
    for r in 0..rows {
        let mut tr = format!(r#"<a:tr h="{row_h}">"#);
        for c in 0..cols {
            let text = cells
                .get((r * cols + c) as usize)
                .map(|s| s.as_str())
                .unwrap_or("");
            tr.push_str(&format!(
                r#"<a:tc><a:txBody><a:bodyPr/><a:p><a:pPr algn="l"/><a:r><a:rPr lang="en-US" sz="{sz}"><a:solidFill><a:srgbClr val="{fg}"/></a:solidFill><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>{text}</a:t></a:r></a:p></a:txBody><a:tcPr>{line}</a:tcPr></a:tc>"#,
                text = esc(text),
                fg = esc(base_fg),
            ));
        }
        tr.push_str("</a:tr>");
        trs.push_str(&tr);
    }

    format!(
        r#"<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{id}" name="table{id}"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="0" bandRow="0"><a:tableStyleId>{{5940675B-B579-460E-A7B8-CF8F6F019E5B}}</a:tableStyleId></a:tblPr><a:gridColLst>{grid_cols}</a:gridColLst>{trs}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"#
    )
}

/// An icon sticker: the registry's glyphs are app-side Material icons, so
/// the export renders the object's own box (fill as declared) with the icon
/// name centered — a clean vector+text representation, never a crash.
fn icon_sp(o: &Shape, name: &str, base_fg: &str, id: u32) -> String {
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    let fill = pptx_fill(&o.fill, o.opacity);
    let label_px = (o.w.min(o.h) * 0.22).clamp(8.0, 28.0);
    let sz = pt(label_px).max(1) * 100;
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="icon{id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm><a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 8000"/></a:avLst></a:prstGeom>{fill}<a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr anchor="ctr" lIns="0" tIns="0" rIns="0" bIns="0"/><a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="{sz}" b="1"><a:solidFill><a:srgbClr val="{fg}"/></a:solidFill><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>{label}</a:t></a:r></a:p></p:txBody></p:sp>"#,
        id = id,
        x_emu = x_emu,
        y_emu = y_emu,
        cx_emu = cx_emu,
        cy_emu = cy_emu,
        fill = fill,
        sz = sz,
        fg = esc(base_fg),
        label = esc(name),
    )
}

/// A media card (video/audio import): dark rounded card, the kind glyph's
/// text label and the asset name — the app's own media view, in vectors.
fn media_sp(o: &Shape, name: &str, media_kind: Option<&str>, id: u32) -> String {
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    let is_video = media_kind.unwrap_or("video") == "video";
    let kind_label = if is_video { "VIDEO" } else { "AUDIO" };
    let title_px = (o.h * 0.09).clamp(8.0, 16.0);
    let name_px = (o.h * 0.075).clamp(7.0, 14.0);
    let kind_sz = pt(title_px).max(1) * 100;
    let name_sz = pt(name_px).max(1) * 100;
    format!(
        r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="media{id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm><a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 4000"/></a:avLst></a:prstGeom><a:solidFill><a:srgbClr val="101014"/></a:solidFill><a:ln w="{bw}" cap="rnd"><a:solidFill><a:srgbClr val="{sc}"/></a:solidFill></a:ln></p:spPr><p:txBody><a:bodyPr anchor="ctr" lIns="0" tIns="0" rIns="0" bIns="0"/><a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="{kind_sz}" b="1"><a:solidFill><a:srgbClr val="9E9EA6"/></a:solidFill><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>{kind_label}</a:t></a:r></a:p><a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="{name_sz}"><a:solidFill><a:srgbClr val="9E9EA6"/></a:solidFill><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>{name}</a:t></a:r></a:p></p:txBody></p:sp>"#,
        id = id,
        x_emu = x_emu,
        y_emu = y_emu,
        cx_emu = cx_emu,
        cy_emu = cy_emu,
        bw = ((o.stroke.width.max(0.0) * EMU).round() as i64).max(1),
        sc = esc(&o.stroke.color),
        kind_sz = kind_sz,
        name_sz = name_sz,
        kind_label = kind_label,
        name = esc(name),
    )
}

/// An image object as an OOXML picture (`ppt/media/*` + relationship), or
/// a clean placeholder box when the asset bytes are missing.
fn image_sp(
    o: &Shape,
    name: Option<&str>,
    rel_id: Option<&str>,
    id: u32,
) -> String {
    let x_emu = (o.x * EMU).round() as i64;
    let y_emu = (o.y * EMU).round() as i64;
    let cx_emu = (o.w * EMU).round() as i64;
    let cy_emu = (o.h * EMU).round() as i64;
    let rot = ((o.rotation.rem_euclid(360.0)) * 60000.0).round() as i64;
    let rot_attr = if rot != 0 { format!(" rot=\"{rot}\"") } else { String::new() };
    match rel_id {
        Some(rel) => {
            let ln = if o.stroke.width > 0.0 {
                let w = (o.stroke.width * EMU).round() as i64;
                format!(
                    r#"<a:ln w="{w}" cap="rnd"><a:solidFill><a:srgbClr val="{}"/></a:solidFill></a:ln>"#,
                    esc(&o.stroke.color)
                )
            } else {
                "<a:ln><a:noFill/></a:ln>".into()
            };
            format!(
                r#"<p:pic><p:nvPicPr><p:cNvPr id="{id}" name="image{id}"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="{rel}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm{rot_attr}><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>{ln}</p:spPr></p:pic>"#,
                id = id,
                rel = rel,
                rot_attr = rot_attr,
                x_emu = x_emu,
                y_emu = y_emu,
                cx_emu = cx_emu,
                cy_emu = cy_emu,
                ln = ln,
            )
        }
        None => {
            // clean placeholder: dark box, image glyph, asset name
            let label = name.unwrap_or("image");
            let name_px = (o.h * 0.08).clamp(7.0, 14.0);
            let sz = pt(name_px).max(1) * 100;
            format!(
                r#"<p:sp><p:nvSpPr><p:cNvPr id="{id}" name="missing{id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm{rot_attr}><a:off x="{x_emu}" y="{y_emu}"/><a:ext cx="{cx_emu}" cy="{cy_emu}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="1C1C22"/></a:solidFill><a:ln w="1" cap="rnd"><a:solidFill><a:srgbClr val="2A2A31"/></a:solidFill></a:ln></p:spPr><p:txBody><a:bodyPr anchor="ctr"/><a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="{sz}"><a:solidFill><a:srgbClr val="6C6C74"/></a:solidFill><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>{label}</a:t></a:r></a:p></p:txBody></p:sp>"#,
                id = id,
                rot_attr = rot_attr,
                x_emu = x_emu,
                y_emu = y_emu,
                cx_emu = cx_emu,
                cy_emu = cy_emu,
                sz = sz,
                label = esc(label),
            )
        }
    }
}

/// Content type for an image extension.
fn image_content_type(ext: &str) -> &'static str {
    match ext {
        "jpeg" | "jpg" => "image/jpeg",
        "gif" => "image/gif",
        _ => "image/png",
    }
}

/// Render a deck to .pptx bytes. `images` maps resource ids to resolved
/// image assets (bytes + format); missing entries export as placeholders.
pub fn to_pptx(deck: &Deck, images: &BTreeMap<String, ExportImage>) -> Vec<u8> {
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    let n = deck.slides.len();
    let r = resolve(&deck.dna);
    let base_fg = r.palette.fg.clone();
    // Slide size follows the deck's aspect: design px × EMU. Height is the
    // constant 720; width follows the ratio (16:9 → the classic 12192000).
    let (dw, _) = deck_dims(deck);
    let sld_cx = (dw * EMU).round() as i64;
    let sld_cy = (SLIDE_H * EMU).round() as i64;

    macro_rules! put {
        ($path:expr, $data:expr) => {
            {
                zip.start_file($path.to_string(), opts.clone()).ok();
                zip.write_all($data.as_bytes()).ok();
            }
        };
    }
    macro_rules! putb {
        ($path:expr, $data:expr) => {
            {
                zip.start_file($path.to_string(), opts.clone()).ok();
                zip.write_all($data).ok();
            }
        };
    }

    // ---- media inventory (deterministic ids, BTreeMap order) ----------------
    // image1.ext, image2.ext … one file per unique resource id referenced by
    // any slide; slides reference them through their own rels files.
    // ONLY image objects enter the inventory — media objects render their
    // card (media_sp) and never reference an image part: embedding a
    // video/audio file as `ppt/media/imageN.png` produces a broken part
    // no player could open, so it must not happen even when the caller
    // still carries a resolved asset for the id.
    let mut media: Vec<(String, String, Vec<u8>)> = Vec::new(); // (resource id, filename, bytes)
    let mut exts: Vec<&str> = Vec::new();
    for slide in &deck.slides {
        for o in &slide.objects {
            let rid = match &o.content {
                Some(ObjectContent::Image { resource_id, .. }) => resource_id,
                _ => continue,
            };
            if media.iter().any(|(id, _, _)| id == rid) {
                continue;
            }
            let Some(asset) = images.get(rid) else { continue };
            let ext = match asset.format.as_str() {
                "jpeg" | "jpg" => "jpeg",
                "gif" => "gif",
                _ => "png",
            };
            if !exts.contains(&ext) {
                exts.push(ext);
            }
            media.push((rid.clone(), format!("image{}.{}", media.len() + 1, ext), asset.bytes.clone()));
        }
    }
    let media_index = |rid: &str| media.iter().position(|(id, _, _)| id == rid);

    let mut ct = String::from(r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml""#);
    for ext in &exts {
        ct.push_str(&format!(
            r#"/><Default Extension="{}" ContentType="{}""#,
            ext,
            image_content_type(ext)
        ));
    }
    ct.push_str(r#"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"#);
    for i in 1..=n {
        ct.push_str(&format!(r#"<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"#));
    }
    let n_charts = deck
        .slides
        .iter()
        .flat_map(|s| s.objects.iter())
        .filter(|o| matches!(o.content, Some(ObjectContent::Chart { .. })))
        .count();
    for i in 1..=n_charts {
        ct.push_str(&format!(r#"<Override PartName="/ppt/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>"#));
    }
    ct.push_str(r#"></Types>"#);
    put!("[Content_Types].xml", ct);

    for (_, filename, bytes) in &media {
        putb!(format!("ppt/media/{filename}"), bytes);
    }

    put!(
        "_rels/.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>"#
    );

    let mut pres_rels = String::from(r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>"#);
    for i in 1..=n {
        pres_rels.push_str(&format!(
            r#"<Relationship Id="rId{}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{i}.xml"/>"#,
            i + 2
        ));
    }
    pres_rels.push_str("</Relationships>");
    put!("ppt/_rels/presentation.xml.rels", pres_rels);

    let mut sld_ids = String::new();
    for i in 1..=n {
        sld_ids.push_str(&format!(r#"<p:sldId id="{}" r:id="rId{}"/>"#, 255 + i, i + 2));
    }
    put!(
        "ppt/presentation.xml",
        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="1" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>{}</p:sldIdLst><p:sldSz cx="{sld_cx}" cy="{sld_cy}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#,
            sld_ids
        )
    );

    put!(
        "ppt/slideMasters/slideMaster1.xml",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMap bg1="dk1" tx1="lt1" bg2="dk2" tx2="lt2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>"#
    );
    put!(
        "ppt/slideMasters/_rels/slideMaster1.xml.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>"#
    );
    put!(
        "ppt/slideLayouts/slideLayout1.xml",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sldLayout>"#
    );
    put!(
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>"#
    );
    let theme = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="DreamTX"><a:themeElements><a:clrScheme name="DreamTX"><a:dk1><a:srgbClr val="{}"/></a:dk1><a:lt1><a:srgbClr val="{}"/></a:lt1><a:dk2><a:srgbClr val="{}"/></a:dk2><a:lt2><a:srgbClr val="{}"/></a:lt2><a:accent1><a:srgbClr val="{}"/></a:accent1><a:accent2><a:srgbClr val="{}"/></a:accent2><a:accent3><a:srgbClr val="{}"/></a:accent3><a:accent4><a:srgbClr val="{}"/></a:accent4><a:accent5><a:srgbClr val="{}"/></a:accent5><a:accent6><a:srgbClr val="{}"/></a:accent6><a:hlink><a:srgbClr val="{}"/></a:hlink><a:folHlink><a:srgbClr val="{}"/></a:folHlink></a:clrScheme><a:fontScheme name="DreamTX"><a:majorFont><a:latin typeface="DejaVu Sans"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="DejaVu Sans"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="DreamTX"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectLst/><a:effectLst/><a:effectLst/></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"#,
        esc(&r.palette.fg), esc(&r.palette.bg), esc(&r.palette.fg), esc(&r.palette.bg),
        esc(&r.palette.accent), esc(&r.palette.accent), esc(&r.palette.accent), esc(&r.palette.accent),
        esc(&r.palette.accent), esc(&r.palette.accent), esc(&r.palette.accent), esc(&r.palette.accent)
    );
    put!("ppt/theme/theme1.xml", theme);

    let mut chart_count = 0usize;
    for (i, slide) in deck.slides.iter().enumerate() {
        let layout = layout_slide(&deck, slide);
        let mut shapes = String::new();
        let mut id = 2u32;
        for el in &layout.elements {
            match el {
                Element::Rect { x, y, w, h, color, radius } => {
                    shapes.push_str(&rect_sp(*x, *y, *w, *h, color, *radius, id));
                }
                Element::Text { .. } => {
                    shapes.push_str(&text_sp(el, id));
                }
            }
            id += 1;
        }
        // The object layer in true Z-order: shapes and content objects
        // interleave exactly as `slide.objects` lists them (and Bring
        // Forward / Send Backward reordered them).
        let mut slide_image_rels = String::new();
        let mut link_rels = String::new();
        let mut link_n = 0usize;
        let mut chart_rels = String::new();
        for obj in &slide.objects {
            let before = shapes.len();
            match &obj.content {
                Some(ObjectContent::Text { doc }) => {
                    shapes.push_str(&text_object_sp(obj, doc, &base_fg, id));
                }
                Some(ObjectContent::Table { rows, cols, cells }) => {
                    shapes.push_str(&table_sp(obj, *rows, *cols, cells, &base_fg, id));
                }
                Some(ObjectContent::Icon { name }) => {
                    shapes.push_str(&icon_sp(obj, name, &base_fg, id));
                }
                Some(ObjectContent::Media { name, media_kind, .. }) => {
                    // The media card — always. It never references an image
                    // part (the inventory holds images only), so a resolved
                    // video/audio asset can never leak its raw bytes into
                    // ppt/media as a fake image.
                    shapes.push_str(&media_sp(obj, name.as_deref().unwrap_or("media"), media_kind.as_deref(), id));
                }
                Some(ObjectContent::Image { resource_id, name, .. }) => {
                    match media_index(resource_id).map(|idx| (idx, format!("rId{}", idx + 2))) {
                        Some((idx, rel)) => {
                            slide_image_rels.push_str(&format!(
                                r#"<Relationship Id="{rel}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/{}"/>"#,
                                media[idx].1
                            ));
                            shapes.push_str(&image_sp(obj, name.as_deref(), Some(&rel), id));
                        }
                        None => {
                            shapes.push_str(&image_sp(obj, name.as_deref(), None, id));
                        }
                    }
                }
                Some(ObjectContent::Chart { style, title, labels, series }) => {
                    chart_count += 1;
                    let n = chart_count;
                    put!(&format!("ppt/charts/chart{n}.xml"), chart_xml(*style, title.as_deref(), labels, series, &r.chart_palette));
                    let rid = format!("rIdC{n}");
                    chart_rels.push_str(&format!(
                        r#"<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart{n}.xml"/>"#
                    ));
                    shapes.push_str(&chart_frame_sp(obj, &rid, id));
                }
                None => {
                    shapes.push_str(&shape_sp(obj, id));
                }
            }
            // Tap-action: wrap the object's own fragment in a hyperlink.
            // Web links use an External relationship; slide jumps use a
            // slide relationship plus the hlinksldjump action.
            let link = match obj.link.as_ref() {
                Some(l) => match l.kind {
                    LinkKind::Url => l.safe_url().map(|u| {
                        link_n += 1;
                        let rid = format!("rIdK{link_n}");
                        link_rels.push_str(&format!(
                            r#"<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="{}" TargetMode="External"/>"#,
                            esc(u)
                        ));
                        (rid, None)
                    }),
                    LinkKind::Slide => deck
                        .slides
                        .iter()
                        .position(|s| s.id == l.target)
                        .map(|j| {
                            link_n += 1;
                            let rid = format!("rIdK{link_n}");
                            link_rels.push_str(&format!(
                                r#"<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slide{}.xml"/>"#,
                                j + 1
                            ));
                            (rid, Some("ppaction://hlinksldjump"))
                        }),
                },
                None => None,
            };
            if let Some((rid, action)) = link {
                let frag = shapes.split_off(before);
                shapes.push_str(&with_link(frag, &rid, action));
            }
            id += 1;
        }
        let xml = format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>{shapes}</p:spTree></p:cSld></p:sld>"#
        );
        put!(&format!("ppt/slides/slide{}.xml", i + 1), xml);
        put!(
            &format!("ppt/slides/_rels/slide{}.xml.rels", i + 1),
            format!(
                r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>{slide_image_rels}{link_rels}{chart_rels}</Relationships>"#
            )
        );
    }

    match zip.finish() {
        Ok(cursor) => cursor.into_inner(),
        Err(_) => Vec::new(),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::model::*;

    #[test]
    fn chart_objects_export_as_native_charts() {
        use std::io::Read;
        let chart: Shape = serde_json::from_value(serde_json::json!({
            "id": "c1", "preset": "rectangle", "x": 100, "y": 100, "w": 400, "h": 300,
            "content": {"kind": "chart", "style": "column", "title": "Sales",
                        "labels": ["Q1", "Q2"],
                        "series": [{"name": "2025", "values": [3, 5.5]}]}
        }))
        .unwrap();
        let mut d = deck();
        d.slides[0].objects.push(chart);
        let bytes = to_pptx(&d, &BTreeMap::new());
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(bytes)).expect("zip readable");
        let mut part = String::new();
        zip.by_name("ppt/charts/chart1.xml").expect("chart part").read_to_string(&mut part).unwrap();
        assert!(part.contains("<c:barChart>") && part.contains("<c:barDir val=\"col\"/>"));
        assert!(part.contains("<c:v>Q2</c:v>") && part.contains("<c:v>5.5</c:v>"));
        assert!(part.contains("<c:v>Sales</c:v>") || part.contains("<a:t>Sales</a:t>"));
        let mut ct = String::new();
        zip.by_name("[Content_Types].xml").expect("ct").read_to_string(&mut ct).unwrap();
        assert!(ct.contains("/ppt/charts/chart1.xml"), "chart content type missing");
        let mut rels = String::new();
        zip.by_name("ppt/slides/_rels/slide1.xml.rels").expect("rels").read_to_string(&mut rels).unwrap();
        assert!(rels.contains(r#"Id="rIdC1""#) && rels.contains(r#"Target="../charts/chart1.xml""#));
        let mut slide = String::new();
        zip.by_name("ppt/slides/slide1.xml").expect("slide").read_to_string(&mut slide).unwrap();
        assert!(slide.contains(r#"r:id="rIdC1""#), "chart frame missing from slide");
    }

    #[test]
    fn with_link_wraps_cnvpr() {
        let frag = r#"<p:sp><p:nvSpPr><p:cNvPr id="3" name="rect3"/><p:cNvSpPr/></p:nvSpPr></p:sp>"#.to_string();
        let out = with_link(frag, "rIdK1", Some("ppaction://hlinksldjump"));
        assert!(out.contains(
            r#"<p:cNvPr id="3" name="rect3"><a:hlinkClick r:id="rIdK1" action="ppaction://hlinksldjump"/></p:cNvPr><p:cNvSpPr/>"#
        ));
    }

    /// The content-deck fixture, shared with the PDF export tests.
    pub(crate) fn content_deck_for_pdf() -> Deck {
        content_deck()
    }

    fn deck() -> Deck {
        Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 3 },
            aspect: "16:9".into(),
            slides: vec![Slide {
                hide_graphics: false,
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Hello".into(), subtitle: None },
                objects: vec![Shape {
                    id: "o1".into(),
                    link: None,
                    preset: "rectangle".into(),
                    x: 100.0,
                    y: 100.0,
                    w: 240.0,
                    h: 120.0,
                    rotation: 15.0,
                    opacity: 1.0,
                    locked: false,
                    group: None,
                    component: None,
                    fill: Fill::LinearGradient { angle: 90.0, from: "D03028".into(), to: "F7F6F3".into() },
                    stroke: Stroke::default(),
                    effects: Effects::default(),
                    points: None,
                    holes: None,
                    closed: true,
                    content: None,
                }],
            }],
            components: Vec::new(),
        }
    }

    /// A deck exercising every ObjectContent kind, in a deliberate
    /// interleaved Z-order (shape, text, image, table, icon, media).
    fn content_deck() -> Deck {
        let text_doc = TextDoc {
            text: "Hello world\nSecond para".into(),
            runs: vec![TextRun {
                start: 0,
                end: 5,
                bold: Some(true),
                italic: None,
                underline: None,
                strike: None,
                subscript: None,
                superscript: None,
                color: Some("D03028".into()),
                highlight: None,
                font_family: None,
                font_size: None,
            }],
            paras: vec![crate::model::ParaStyle {
                start: 0,
                align: Some(TextAlign::Center),
                list: Some(ListKind::Bullet),
                indent: None,
                line_spacing: None,
            }],
            valign: VerticalAlign::Middle,
            autofit: Autofit::None,
        };
        let mut deck = deck();
        deck.slides[0].objects = vec![
            Shape {
                id: "shape".into(),
                link: None,
                preset: "rectangle".into(),
                x: 10.0, y: 10.0, w: 100.0, h: 60.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::Solid { color: "0F62FE".into() },
                stroke: Stroke::default(), effects: Effects::default(),
                points: None, holes: None, closed: true, content: None,
            },
            Shape {
                id: "txt".into(),
                link: None,
                preset: "rectangle".into(),
                x: 200.0, y: 100.0, w: 500.0, h: 200.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::None, stroke: Stroke::default(), effects: Effects::default(),
                points: None, holes: None, closed: true,
                content: Some(ObjectContent::Text { doc: text_doc }),
            },
            Shape {
                id: "img".into(),
                link: None,
                preset: "rectangle".into(),
                x: 700.0, y: 100.0, w: 300.0, h: 200.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::None,
                stroke: Stroke { color: "17181A".into(), width: 2.0, ..Default::default() },
                effects: Effects::default(),
                points: None, holes: None, closed: true,
                content: Some(ObjectContent::Image { resource_id: "r1".into(), brand: false, name: Some("logo.png".into()) }),
            },
            Shape {
                id: "tbl".into(),
                link: None,
                preset: "rectangle".into(),
                x: 100.0, y: 400.0, w: 400.0, h: 150.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::None,
                stroke: Stroke { color: "17181A".into(), width: 1.5, ..Default::default() },
                effects: Effects::default(),
                points: None, holes: None, closed: true,
                content: Some(ObjectContent::Table {
                    rows: 2,
                    cols: 2,
                    cells: vec!["A".into(), "B".into(), "C".into(), "D".into()],
                }),
            },
            Shape {
                id: "ic".into(),
                link: None,
                preset: "rectangle".into(),
                x: 550.0, y: 400.0, w: 80.0, h: 80.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::Solid { color: "A855F7".into() },
                stroke: Stroke::default(), effects: Effects::default(),
                points: None, holes: None, closed: true,
                content: Some(ObjectContent::Icon { name: "star".into() }),
            },
            Shape {
                id: "med".into(),
                link: None,
                preset: "rectangle".into(),
                x: 650.0, y: 400.0, w: 200.0, h: 120.0,
                rotation: 0.0, opacity: 1.0, locked: false, group: None, component: None,
                fill: Fill::None, stroke: Stroke::default(), effects: Effects::default(),
                points: None, holes: None, closed: true,
                content: Some(ObjectContent::Media {
                    resource_id: "r_missing".into(),
                    brand: false,
                    name: Some("clip.mp4".into()),
                    media_kind: Some("video".into()),
                }),
            },
        ];
        deck
    }

    /// A 2×1 pixel red PNG with one fully-opaque red pixel and one
    /// half-transparent green pixel.
    fn test_images() -> BTreeMap<String, ExportImage> {
        let png = crate::export::tests_support::tiny_png();
        let mut m = BTreeMap::new();
        m.insert(
            "r1".into(),
            ExportImage {
                format: "png".into(),
                width: 2,
                height: 1,
                bytes: png,
                rgba: None,
            },
        );
        m
    }

    #[test]
    fn produces_zip_magic() {
        let b = to_pptx(&deck(), &BTreeMap::new());
        assert!(b.starts_with(b"PK"), "not a zip");
        assert!(b.len() > 800);
    }

    #[test]
    fn shapes_export_with_geometry_and_gradient() {
        use std::io::Read;
        let b = to_pptx(&deck(), &BTreeMap::new());
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(b)).expect("zip readable");
        let mut xml = String::new();
        zip.by_name("ppt/slides/slide1.xml").expect("slide1 present").read_to_string(&mut xml).unwrap();
        assert!(xml.contains("gradFill"), "gradient fill missing");
        assert!(xml.contains("rot=\"900000\""), "rotation missing");
        assert!(xml.contains("prst=\"rect\""), "preset geometry missing");
    }

    #[test]
    fn content_objects_export_with_text_table_and_images() {
        use std::io::Read;
        let b = to_pptx(&content_deck(), &test_images());
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(b)).expect("zip readable");

        let mut xml = String::new();
        zip.by_name("ppt/slides/slide1.xml").expect("slide1 present").read_to_string(&mut xml).unwrap();
        // Text box: real txBody with runs + paragraph style. The bold run
        // splits "Hello" from " world" across <a:r> elements — matching the
        // run marks exactly — so assert the pieces.
        assert!(xml.contains("Hello"), "text box text missing");
        assert!(xml.contains(" world"), "text box tail missing");
        assert!(xml.contains("Second para"), "second paragraph missing");
        assert!(xml.contains("b=\"1\""), "bold run missing");
        assert!(xml.contains("D03028"), "run color missing");
        assert!(xml.contains("buChar"), "bullet missing");
        assert!(xml.contains("anchor=\"ctr\""), "vertical alignment missing");
        // Table: graphic frame with grid + cell text.
        assert!(xml.contains("<p:graphicFrame>"), "table frame missing");
        assert!(xml.contains("<a:gridCol"), "table grid missing");
        assert!(xml.contains(">A</a:t>"), "table cell text missing");
        // Icon + media cards.
        assert!(xml.contains("star"), "icon name missing");
        assert!(xml.contains("clip.mp4"), "media name missing");
        // Image with a relationship.
        assert!(xml.contains("<p:pic>"), "picture missing");
        assert!(xml.contains("r:embed=\"rId2\""), "image relationship missing");
        // Z-order: shape before text before image (list order).
        let shape_at = xml.find("<a:srgbClr val=\"0F62FE\"").expect("shape fill");
        let text_at = xml.find(" world").expect("text");
        let pic_at = xml.find("<p:pic>").expect("pic");
        assert!(shape_at < text_at && text_at < pic_at, "object z-order broken");

        // The slide rels carries the image relationship; media exists.
        let mut rels = String::new();
        zip.by_name("ppt/slides/_rels/slide1.xml.rels").expect("rels present").read_to_string(&mut rels).unwrap();
        assert!(rels.contains("Target=\"../media/image1.png\""), "image rel target missing");
        {
            let media = zip.by_name("ppt/media/image1.png").expect("media present");
            assert!(media.size() > 0, "media bytes empty");
        }
        // Content types know the extension.
        let mut ct = String::new();
        zip.by_name("[Content_Types].xml").expect("ct present").read_to_string(&mut ct).unwrap();
        assert!(ct.contains("Extension=\"png\""), "png content type missing");

        // A missing image asset exports a clean placeholder, never a hole.
        assert!(xml.contains("clip.mp4"), "placeholder fallback");
    }

    #[test]
    fn media_objects_export_as_cards_not_embedded_bytes() {
        use std::io::Read;
        // A PRESENT asset for the media resource id: the exporter must
        // STILL render the media card (media_sp) — media objects never
        // enter the ppt/media inventory, so raw video/audio bytes can
        // never land in the package as a fake imageN.png part that no
        // player could open (the old code embedded them whenever the
        // caller carried a resolved asset for the id).
        let mut images = BTreeMap::new();
        // The deck's REAL image asset (r1 → the tiny png) AND a staged
        // asset for the media object's own resource id.
        images.insert(
            "r1".into(),
            ExportImage {
                format: "png".into(),
                width: 2,
                height: 1,
                bytes: crate::export::tests_support::tiny_png(),
                rgba: None,
            },
        );
        images.insert(
            "r_missing".into(),
            ExportImage {
                format: "png".into(),
                width: 2,
                height: 1,
                bytes: b"these-are-not-image-bytes".to_vec(),
                rgba: None,
            },
        );
        let b = to_pptx(&content_deck(), &images);
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(b)).expect("zip readable");

        let mut xml = String::new();
        zip.by_name("ppt/slides/slide1.xml").expect("slide1 present").read_to_string(&mut xml).unwrap();
        // The media object is a CARD (name + kind label + roundRect body),
        // never a <p:pic> — only the real image object is a picture.
        assert!(xml.contains("clip.mp4"), "the media card carries the name");
        assert!(xml.contains("VIDEO"), "the media card carries its kind label");
        assert_eq!(xml.matches("<p:pic>").count(), 1,
            "exactly one picture part: the image object only");
        // The slide's rels reference exactly the image's media file (plus
        // the slide's own layout rel) — the media object adds no
        // relationship of any kind.
        let mut rels = String::new();
        zip.by_name("ppt/slides/_rels/slide1.xml.rels").expect("rels present").read_to_string(&mut rels).unwrap();
        assert_eq!(rels.matches("relationships/image").count(), 1,
            "only the image's relationship exists");
        assert_eq!(rels.matches("<Relationship ").count(), 2,
            "the slide rels: the layout rel + the image rel, nothing else");
        assert!(rels.contains("Target=\"../media/image1.png\""));
        // The package carries exactly ONE media part — the real image.
        // The staged video bytes must never appear anywhere.
        let media_parts: Vec<String> = zip
            .file_names()
            .filter(|n| n.starts_with("ppt/media/"))
            .map(String::from)
            .collect();
        assert_eq!(media_parts, vec!["ppt/media/image1.png".to_string()],
            "no second media part ever carries the video bytes");
    }

    #[test]
    fn utf16_slices_surrogate_pairs() {
        // "a𝕏b": 𝕏 is a surrogate pair (2 UTF-16 units).
        let s = "a𝕏b";
        assert_eq!(utf16_slice(s, 0, 1), "a");
        assert_eq!(utf16_slice(s, 1, 3), "𝕏");
        assert_eq!(utf16_slice(s, 3, 4), "b");
        assert_eq!(utf16_slice(s, 0, 4), s);
        assert_eq!(utf16_slice(s, 2, 4), "b");
    }
}
