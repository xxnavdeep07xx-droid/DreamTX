//! End-to-end smoke: the same command protocol the app/worker speak.

use serde_json::{json, Value};

fn run(v: Value) -> Value {
    let s = serde_json::to_string(&v).unwrap();
    serde_json::from_str(&deck_core::run(&s)).unwrap()
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
    assert_eq!(r["next_suggested"], json!("Split text + visual"));

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
    assert_eq!(b64_decode_prefix(b64), b"PK");

    r = run(json!({ "op": "export_pdf", "deck": deck }));
    assert_eq!(r["ok"], json!(true));
    let b64 = r["base64"].as_str().unwrap();
    assert_eq!(b64_decode_prefix(b64), b"%PD");
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

fn placeholder_deck() -> Value {
    r#"{ "id": "d1", "title": "T", "version": 1, "dna": { "family": "swiss_editorial", "seed": 5 }, "slides": [ { "id": "s1", "archetype": "cover", "kind": "cover", "title": "Hi" } ] }"#
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
