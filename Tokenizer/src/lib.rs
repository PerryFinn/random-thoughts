use std::{panic::catch_unwind, slice, str};
use tiktoken_rs::{cl100k_base_singleton, o200k_base_singleton};

/// All pointers belong to the caller. No allocation or panic crosses the C ABI.
/// Returns 0 on success, 1 for invalid pointers/UTF-8, 2 for initialization/count failure.
#[no_mangle]
pub unsafe extern "C" fn report_tokenizer_count(
    input: *const u8, length: usize, cl100k: *mut usize, o200k: *mut usize,
) -> i32 {
    if cl100k.is_null() || o200k.is_null() || (input.is_null() && length != 0) {
        return 1;
    }
    let result = catch_unwind(|| {
        static QUIET_PANICS: std::sync::Once = std::sync::Once::new();
        QUIET_PANICS.call_once(|| std::panic::set_hook(Box::new(|_| {})));
        let bytes = if length == 0 { &[][..] } else { slice::from_raw_parts(input, length) };
        let text = str::from_utf8(bytes).map_err(|_| 1)?;
        Ok::<_, i32>((cl100k_base_singleton().encode_ordinary(text).len(),
                      o200k_base_singleton().encode_ordinary(text).len()))
    });
    match result {
        Ok(Ok((a, b))) => { *cl100k = a; *o200k = b; 0 },
        Ok(Err(code)) => code,
        Err(_) => 2,
    }
}
