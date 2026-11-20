//! End-to-end smoke: the same command protocol the app/worker speak.

use serde_json::{json, Value};

fn run(v: Value) -> Value {
    let s = serde_json::to_string(&v).unwrap();
    serde_json::from_str(&dreamtx::run(&s)).unwrap()
}

#[test]
fn full_flow() {
    // create deck
    let mut r = run(json!({ "op": "new_deck", "title": "Launch plan", "family": "swiss_editorial" }));
    assert_eq!(r["ok"], json!(true), "{r}");
    let mut deck = r["deck"].clone();
    assert_eq!(deck["slides"].as_array().unwrap().len(), 1);

    // add a stat wall
    r = run(json!({
        "op": "add_slide",
        "deck": deck,
        "archetype": "stat_wall",
        "content": {
            "kind": "stat_wall",
            "title": "Traction",
            "stats": [
                { "value": "3.4x", "label": "YoY growth" },
                { "value": "82%", "label": "retention" },
                { "value": "17k", "label": "users" }
            ]
        }
    }));
    assert_eq!(r["ok"], json!(true), "{r}");
    deck = r["deck"].clone();
    assert_eq!(deck["slides"].as_array().unwrap().len(), 2);
    assert_eq!(deck["version"], json!(2));
    assert_eq!(r["next_suggested"], json!("statement"));

    // layout of slide 1 is drawable
    r = run(json!({ "op": "get_layout", "deck": deck, "slide_index": 1 }));
    assert_eq!(r["ok"], json!(true));
    let els = r["layout"]["elements"].as_array().unwrap();
    assert!(els.len() > 3, "stat wall should have bg + tiles + text");
    assert!(els.iter().all(|e| e.get("x").is_some()));

    // pacing sees something
    r = run(json!({ "op": "pacing", "deck": deck }));
    assert_eq!(r["ok"], json!(true));

    // exports produce real files
    r = run(json!({ "op": "export_pptx", "deck": deck }));
    assert_eq!(r["ok"], json!(true));
    let b64 = r["base64"].as_str().unwrap();
    assert!(!b64.is_empty());
    let p = b64_decode_prefix(b64);
    assert_eq!((p[0], p[1]), (b'P', b'K'));

    r = run(json!({ "op": "export_pdf", "deck": deck }));
    assert_eq!(r["ok"], json!(true));
    let b64 = r["base64"].as_str().unwrap();
    let p = b64_decode_prefix(b64);
    assert_eq!((p[0], p[1], p[2]), (b'%', b'P', b'D'));
}

#[test]
fn bad_input_gets_clean_errors() {
    let r = run(json!({ "op": "add_slide", "deck": { "bogus": true }, "archetype": "stat_wall" }));
    assert_eq!(r["ok"], json!(false));
    let r = run(json!({ "op": "add_slide", "deck": placeholder_deck(), "archetype": "holodeck" }));
    assert_eq!(r["ok"], json!(false));
    assert!(r["error"].as_str().unwrap().contains("archetype"));
}

#[test]
fn dna_variation_flows() {
    let mut r = run(json!({ "op": "new_deck", "title": "V", "family": "cinematic" }));
    let deck = r["deck"].clone();
    r = run(json!({ "op": "apply_dna", "deck": deck, "change": "next_variant" }));
    assert_eq!(r["ok"], json!(true));
    r = run(json!({ "op": "apply_dna", "deck": r["deck"], "change": "next_family" }));
    assert_eq!(r["ok"], json!(true));
    assert_eq!(r["deck"]["dna"]["family"], json!("magazine_serif"));
}

#[test]
fn resolve_dna_reads_the_palette_without_mutating() {
    let mut r = run(json!({ "op": "new_deck", "title": "P", "family": "swiss_editorial" }));
    let deck = r["deck"].clone();
    r = run(json!({ "op": "resolve_dna", "deck": deck }));
    assert_eq!(r["ok"], json!(true), "{r}");
    let dna = &r["dna"];
    assert!(dna["palette"]["bg"].is_string(), "palette bg: {dna}");
    assert!(dna["palette"]["fg"].is_string());
    assert!(dna["palette"]["accent"].is_string());
    // A read, not a mutation: nothing but the palette comes back, and the
    // same deck value still drives a real op afterwards.
    assert_eq!(r["deck"].as_object(), None, "resolve_dna returns no deck");
    let resolved = r["dna"].clone();
    r = run(json!({ "op": "get_layout", "deck": deck, "slide_index": 0 }));
    assert_eq!(r["ok"], json!(true), "the deck is still usable verbatim");
    // Deterministic: the same DNA resolves to the same palette.
    let again = run(json!({ "op": "resolve_dna", "deck": deck }));
    assert_eq!(again["dna"], resolved, "deterministic resolution");
}

#[test]
fn object_content_round_trips_through_the_engine() {
    let mut r = run(json!({ "op": "new_deck", "title": "C", "family": "swiss_editorial" }));
    let deck = r["deck"].clone();
    let slide_id = deck["slides"][0]["id"].as_str().unwrap().to_string();

    // A rich text box: every character/paragraph/box attribute survives an
    // add → update → export path verbatim (the app reads them right back).
    let text_doc = json!({
        "text": "Hello\nworld",
        "runs": [
            { "start": 0, "end": 5, "bold": true, "color": "FF0099", "highlight": "FFE08A", "font_size": 40.0 },
            { "start": 6, "end": 11, "italic": true, "underline": true, "strike": true, "subscript": true, "superscript": true, "font_family": "serif" }
        ],
        "paras": [ { "start": 0, "align": "center", "list": "bullet", "indent": 1, "line_spacing": 1.5 } ],
        "valign": "middle",
        "autofit": "shrink"
    });
    r = run(json!({
        "op": "add_object",
        "deck": deck,
        "slide_id": slide_id,
        "shape": {
            "id": "o1", "preset": "rectangle", "x": 100.0, "y": 200.0, "w": 400.0, "h": 120.0,
            "content": { "kind": "text", "doc": text_doc }
        }
    }));
    assert_eq!(r["ok"], json!(true), "{r}");
    let obj = &r["deck"]["slides"][0]["objects"][0];
    assert_eq!(obj["content"]["kind"], json!("text"));
    assert_eq!(obj["content"]["doc"], text_doc, "doc survives add verbatim");

    // An update that only touches geometry keeps the content byte-stable.
    let mut shape = obj.clone();
    shape["x"] = json!(120.0);
    r = run(json!({ "op": "update_object", "deck": r["deck"], "slide_id": slide_id, "object_id": "o1", "shape": shape }));
    assert_eq!(r["ok"], json!(true), "{r}");
    assert_eq!(r["deck"]["slides"][0]["objects"][0]["content"]["doc"], text_doc);

    // The other payload kinds round-trip too (fields, defaults and all).
    for content in [
        json!({ "kind": "image", "resource_id": "r9", "brand": true, "name": "logo.png" }),
        json!({ "kind": "icon", "name": "favorite" }),
        json!({ "kind": "media", "resource_id": "r10", "brand": false, "name": "clip.mp4", "media_kind": "video" }),
        json!({ "kind": "table", "rows": 3, "cols": 3, "cells": ["a", "b", "c", "d", "e", "f", "g", "h", "i"] }),
    ] {
        r = run(json!({
            "op": "add_object",
            "deck": r["deck"],
            "slide_id": slide_id,
            "shape": { "id": "oz", "preset": "rectangle", "x": 10.0, "y": 10.0, "w": 50.0, "h": 50.0, "content": content }
        }));
        assert_eq!(r["ok"], json!(true), "{content} -> {r}");
        let objs = r["deck"]["slides"][0]["objects"].as_array().unwrap();
        assert_eq!(objs.last().unwrap()["content"], content, "{content} survives verbatim");
        r = run(json!({ "op": "delete_object", "deck": r["deck"], "slide_id": slide_id, "object_id": "oz" }));
        assert_eq!(r["ok"], json!(true));
    }

    // Content objects do not break export (the box renders as its vector
    // silhouette; the payload itself is inert to the core).
    let with_text = r["deck"].clone();
    r = run(json!({ "op": "export_pptx", "deck": with_text }));
    assert_eq!(r["ok"], json!(true), "{r}");
    r = run(json!({ "op": "export_pdf", "deck": with_text }));
    assert_eq!(r["ok"], json!(true), "{r}");
}

#[test]
fn legacy_shapes_stay_byte_stable_without_content() {
    let mut r = run(json!({ "op": "new_deck", "title": "L", "family": "swiss_editorial" }));
    let deck = r["deck"].clone();
    let slide_id = deck["slides"][0]["id"].as_str().unwrap().to_string();
    r = run(json!({
        "op": "add_object",
        "deck": deck,
        "slide_id": slide_id,
        "shape": { "id": "o1", "preset": "ellipse", "x": 0.0, "y": 0.0, "w": 100.0, "h": 100.0,
                   "fill": { "type": "solid", "color": "D03028" } }
    }));
    assert_eq!(r["ok"], json!(true), "{r}");
    let obj = &r["deck"]["slides"][0]["objects"][0];
    assert!(obj.get("content").is_none(), "no content key on legacy shapes");
}

fn placeholder_deck() -> Value {
    r#"{ "id": "d1", "title": "T", "version": 1, "dna": { "family": "swiss_editorial", "seed": 5 }, "slides": [ { "id": "s1", "archetype": "cover", "content": { "kind": "cover", "kicker": null, "title": "Hi", "subtitle": null } } ] }"#
        .parse()
        .unwrap()
}

fn b64_decode_prefix(s: &str) -> [u8; 3] {
    let mut out = [0u8; 3];
    for (i, ch) in s.chars().take(4).enumerate() {
        let v = match ch {
            'A'..='Z' => ch as u8 - b'A',
            'a'..='z' => ch as u8 - b'a' + 26,
            '0'..='9' => ch as u8 - b'0' + 52,
            '+' => 62,
            '/' => 63,
            _ => continue,
        };
        match i {
            0 => out[0] |= v << 2,
            1 => {
                out[0] |= v >> 4;
                out[1] |= v << 4;
            }
            2 => {
                out[1] |= v >> 2;
                out[2] |= v << 6;
            }
            _ => out[2] |= v,
        }
    }
    out
}
