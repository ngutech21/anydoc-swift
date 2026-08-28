#![deny(warnings)]

use std::panic::{catch_unwind, AssertUnwindSafe};

#[unsafe(no_mangle)]
pub extern "C" fn rust_staticlib_probe(value: i32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        assert!(value >= 0, "probe value must not be negative");
        value.saturating_add(1)
    }))
    .unwrap_or(-1)
}
