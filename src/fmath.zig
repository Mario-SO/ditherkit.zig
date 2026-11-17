//! Floating-point operations shared with the Rust port. Use Zig intrinsics
//! for operations the compiler can lower directly. Other libm calls have
//! Zig fallbacks for freestanding and other libc-free targets.

const std = @import("std");
const builtin = @import("builtin");

const libm = struct {
    extern "c" fn expf(f32) f32;
    extern "c" fn atan2f(f32, f32) f32;
    extern "c" fn log10(f64) f64;
    extern "c" fn pow(f64, f64) f64;
    extern "c" fn powf(f32, f32) f32;
};

/// Rust `f32::powf`.
pub inline fn powf(x: f32, y: f32) f32 {
    return if (builtin.link_libc) libm.powf(x, y) else std.math.pow(f32, x, y);
}

pub inline fn sinf(x: f32) f32 {
    return @sin(x);
}

pub inline fn expf(x: f32) f32 {
    return if (builtin.link_libc) libm.expf(x) else @exp(x);
}

pub inline fn cosf(x: f32) f32 {
    return @cos(x);
}

pub inline fn atan2f(y: f32, x: f32) f32 {
    return if (builtin.link_libc) libm.atan2f(y, x) else std.math.atan2(y, x);
}

pub inline fn log10(x: f64) f64 {
    return if (builtin.link_libc) libm.log10(x) else @log10(x);
}

pub inline fn pow(x: f64, y: f64) f64 {
    return if (builtin.link_libc) libm.pow(x, y) else std.math.pow(f64, x, y);
}

/// Rust float clamp retains NaN inputs.
pub inline fn clamp(x: anytype, low: @TypeOf(x), high: @TypeOf(x)) @TypeOf(x) {
    return if (x < low) low else if (x > high) high else x;
}

/// Convert using Rust's saturating float-to-integer cast (NaN becomes zero).
pub inline fn saturatingInt(comptime Int: type, x: anytype) Int {
    if (std.math.isNan(x)) return 0;
    if (x >= @as(@TypeOf(x), @floatFromInt(std.math.maxInt(Int)))) return std.math.maxInt(Int);
    if (x <= @as(@TypeOf(x), @floatFromInt(std.math.minInt(Int)))) return std.math.minInt(Int);
    return @intFromFloat(x);
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
