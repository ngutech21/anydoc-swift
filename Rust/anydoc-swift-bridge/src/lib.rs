//! Handwritten C ABI bridge for AnyDocSwift.
//!
//! ABI exports will be added together with their ownership and panic-safety
//! tests. The bootstrap crate intentionally exposes no placeholder symbols.

#![deny(unsafe_op_in_unsafe_fn)]
