//! Float helpers that reproduce Rust's `f32` semantics, in one place so the
//! backend can be tuned without touching rasterizers.
//!
//! Rust lowers `f32::powf` to the platform libm `powf`. When libc is linked we
//! call that same function (identical results, ~30% faster than
//! `std.math.pow`); otherwise (freestanding, wasm, no-libc builds) we fall back
//! to `std.math.pow`. Parity tests run against both paths.

const std = @import("std");
const builtin = @import("builtin");

const libm = struct {
    extern "c" fn powf(f32, f32) f32;
};

/// Rust `f32::powf`.
pub inline fn powf(x: f32, y: f32) f32 {
    return if (builtin.link_libc) libm.powf(x, y) else std.math.pow(f32, x, y);
}

/// Rust `f32::powi`: binary exponentiation by squaring, the same algorithm
/// as LLVM's `llvm.powi` lowering / compiler-rt `__powisf2`.
pub inline fn powi(x: f32, comptime n: i32) f32 {
    var a = x;
    var b: u32 = @abs(n);
    var r: f32 = 1.0;
    while (true) {
        if (b & 1 != 0) r *= a;
        b /= 2;
        if (b == 0) break;
        a *= a;
    }
    return if (n < 0) 1.0 / r else r;
}

test "powi matches repeated multiplication" {
    try std.testing.expectEqual(@as(f32, 4096.0), powi(2.0, 12));
    try std.testing.expectEqual(@as(f32, 0.125), powi(2.0, -3));
    try std.testing.expectEqual(@as(f32, 1.0), powi(7.5, 0));
}
