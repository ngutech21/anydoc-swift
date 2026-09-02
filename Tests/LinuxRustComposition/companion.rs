use std::panic;

#[unsafe(no_mangle)]
pub extern "C" fn anydoc_unwind_companion_value(value: u32) -> u32 {
    panic::catch_unwind(|| {
        if value == 0 {
            panic!("exercise unwind support");
        }
        value
    })
    .unwrap_or(0)
}
