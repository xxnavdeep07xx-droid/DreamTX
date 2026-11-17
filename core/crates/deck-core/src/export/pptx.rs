//! Minimal-but-valid .pptx writer (OOXML 16:9). Pure Rust: zip + hand-built
//! XML. Text boxes carry explicit sizes from the layout solver; viewers render
//! text with local font fallback, so no font embedding is required for v0.1
//! (M2 adds subsetting + embedding).

use crate::dna::resolve;
use crate::layout::{layout_slide, Element};
use crate::model::{ArrowHead, DashStyle, Deck, Fill, Shape, SLIDE_H, SLIDE_W};
use crate::shapes;
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

fn pt(size_px: f64) -> i32 {
    (size_px * 0.75).round() as i32 // px -> pt at 96dpi
}

fn typeface(serif: bool, bold: bool) -> &'static str {
    match (serif, bold) {
        (true, true) => "DejaVu Serif",
        (true, false) => "DejaVu Serif",
        (false, _) => "DejaVu Sans",
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

/// Render a deck to .pptx bytes.
pub fn to_pptx(deck: &Deck) -> Vec<u8> {
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    let n = deck.slides.len();
    let r = resolve(&deck.dna);

    macro_rules! put {
        ($path:expr, $data:expr) => {
            zip.start_file($path.to_string(), opts.clone()).ok();
            zip.write_all($data.as_bytes()).ok();
        };
    }

    let mut ct = String::from(r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml""#);
    ct.push_str(r#"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>"#);
    ct.push_str(r#"<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"#);
    for i in 1..=n {
        ct.push_str(&format!(r#"<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"#));
    }
    ct.push_str(r#"</Types>"#);
    put!("[Content_Types].xml", ct);

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
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="1" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>{}</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#,
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

    for (i, slide) in deck.slides.iter().enumerate() {
        let layout = layout_slide(&deck.dna, slide);
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
        // manual vector overlay sits on top of the archetype layout
        for obj in &slide.objects {
            shapes.push_str(&shape_sp(obj, id));
            id += 1;
        }
        let xml = format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>{shapes}</p:spTree></p:cSld></p:sld>"#
        );
        put!(&format!("ppt/slides/slide{}.xml", i + 1), xml);
        put!(
            &format!("ppt/slides/_rels/slide{}.xml.rels", i + 1),
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>"#
        );
    }

    let _ = SLIDE_W * SLIDE_H; // scale is handled by the EMU constant
    match zip.finish() {
        Ok(cursor) => cursor.into_inner(),
        Err(_) => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::*;

    fn deck() -> Deck {
        Deck {
            id: "d".into(),
            title: "T".into(),
            version: 1,
            dna: Dna { family: DnaFamily::SwissEditorial, seed: 3 },
            slides: vec![Slide {
                id: "s1".into(),
                archetype: Archetype::Cover,
                content: SlideContent::Cover { kicker: None, title: "Hello".into(), subtitle: None },
                objects: vec![Shape {
                    id: "o1".into(),
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
                }],
            }],
            components: Vec::new(),
        }
    }

    #[test]
    fn produces_zip_magic() {
        let b = to_pptx(&deck());
        assert!(b.starts_with(b"PK"), "not a zip");
        assert!(b.len() > 800);
    }

    #[test]
    fn shapes_export_with_geometry_and_gradient() {
        use std::io::Read;
        let b = to_pptx(&deck());
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(b)).expect("zip readable");
        let mut xml = String::new();
        zip.by_name("ppt/slides/slide1.xml").expect("slide1 present").read_to_string(&mut xml).unwrap();
        assert!(xml.contains("gradFill"), "gradient fill missing");
        assert!(xml.contains("rot=\"900000\""), "rotation missing");
        assert!(xml.contains("prst=\"rect\""), "preset geometry missing");
    }
}
