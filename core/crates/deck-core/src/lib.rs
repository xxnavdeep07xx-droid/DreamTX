//! deck-core — DreamTX presentation engine.
//!
//! One crate, every target:
//! - native cdylib linked into Flutter via FFI (`dreamtx_command`)
//! - wasm32 module executed inside the Cloudflare Worker (`command` via wasm-bindgen)
//! - lib for cargo tests

pub mod command;
pub mod dna;
pub mod export;
pub mod fonts;
pub mod layout;
pub mod model;
pub mod pacing;
pub mod shapes;

use std::ffi::{c_char, CStr, CString};

/// Safe entry: JSON in → JSON out. Used by tests, FFI and wasm glue.
pub fn run(req: &str) -> String {
    serde_json::to_string(&command::execute(req)).unwrap_or_else(|e| format!("{{\"ok\":false,\"error\":\"serialize: {e}\"}}"))
}

/// C ABI for Flutter (dart:ffi). Caller must free the result with
/// `dreamtx_free`. Returns 0 on success; nonzero when parsing the request
/// failed entirely (out stays untouched).
///
/// # Safety
/// `req` must be a valid NUL-terminated UTF-8 C string; `out` must be a valid,
/// writable pointer slot.
#[no_mangle]
pub unsafe extern "C" fn dreamtx_command(req: *const c_char, out: *mut *mut c_char) -> i32 {
    if req.is_null() || out.is_null() {
        return -1;
    }
    let cstr = match CStr::from_ptr(req).to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };
    let resp = run(cstr);
    let boxed = match CString::new(resp) {
        Ok(b) => b,
        Err(_) => return -3, // response contained NUL — impossible from serde_json
    };
    *out = boxed.into_raw();
    0
}

/// Free a string produced by `dreamtx_command`.
///
/// # Safety
/// `ptr` must originate from `dreamtx_command` and not have been freed already.
#[no_mangle]
pub unsafe extern "C" fn dreamtx_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(feature = "wasm")]
mod wasm_glue {
    use wasm_bindgen::prelude::*;

    #[wasm_bindgen]
    pub fn command(req: String) -> String {
        crate::run(&req)
    }
}
