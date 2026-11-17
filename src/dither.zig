//! Threshold matrices and fill styles.
//! Port of `dither-core/src/dither.rs`.
//!
//! Everything in dither-kit is *ordered* dithering: a continuous intensity
//! (0..1) becomes on/off pixels by comparing it against a position-dependent
//! threshold. Ordered dithering is stateless per pixel, so it is cheap,
//! deterministic, stable across frames (no shimmer while animating), and
//! identical in every backend.

const std = @import("std");

/// Classic recursive Bayer matrices, built at comptime.
const bayer2 = [4]u8{ 0, 2, 3, 1 };

const bayer4: [16]u8 = blk: {
    var m: [16]u8 = undefined;
    for (0..4) |y| for (0..4) |x| {
        const inner = bayer2[(y % 2) * 2 + (x % 2)];
        const outer = bayer2[(y / 2) * 2 + (x / 2)];
        m[y * 4 + x] = 4 * inner + outer;
    };
    break :blk m;
};

const bayer8: [64]u8 = blk: {
    var m: [64]u8 = undefined;
    for (0..8) |y| for (0..8) |x| {
        const inner = bayer4[(y % 4) * 4 + (x % 4)];
        const outer = bayer2[((y / 4) % 2) * 2 + ((x / 4) % 2)];
        m[y * 8 + x] = 4 * inner + outer;
    };
    break :blk m;
};

/// A clustered-dot (halftone) 4x4 threshold order.
const halftone4 = [16]u8{ 12, 5, 6, 13, 4, 0, 1, 7, 11, 3, 2, 8, 15, 10, 9, 14 };

/// A threshold matrix.
pub const Matrix = enum {
    bayer2,
    bayer4,
    bayer8,
    /// Clustered dots, like newspaper halftone.
    halftone,
    /// Hash-based white noise (stable per pixel).
    noise,

    pub const default: Matrix = .bayer8;

    /// Threshold in the open interval (0, 1) for pixel `(x, y)`.
    pub inline fn threshold(self: Matrix, x: i32, y: i32) f32 {
        const xu: usize = @intCast(@mod(x, 8));
        const yu: usize = @intCast(@mod(y, 8));
        return switch (self) {
            .bayer2 => (f(bayer2[(yu % 2) * 2 + xu % 2]) + 0.5) / 4.0,
            .bayer4 => (f(bayer4[(yu % 4) * 4 + xu % 4]) + 0.5) / 16.0,
            .bayer8 => (f(bayer8[yu * 8 + xu]) + 0.5) / 64.0,
            .halftone => (f(halftone4[(yu % 4) * 4 + xu % 4]) + 0.5) / 16.0,
            .noise => (@as(f32, @floatFromInt(hash2(x, y))) + 0.5) / (u32_max_f32 + 1.0),
        };
    }

    /// Whether a pixel of the given intensity is lit.
    pub inline fn on(self: Matrix, x: i32, y: i32, intensity: f32) bool {
        return intensity > self.threshold(x, y);
    }
};

/// Rust's `u32::MAX as f32`, which rounds up to 2^32.
const u32_max_f32: f32 = 4294967296.0;

inline fn f(v: u8) f32 {
    return @floatFromInt(v);
}

/// How a shape's interior is textured; mirrors dither-kit's `variant`.
pub const Fill = enum {
    /// Ordered Bayer gradient: density follows intensity.
    gradient,
    /// Sparse, evenly spaced dots.
    dotted,
    /// Diagonal hatching.
    hatched,
    /// Every covered pixel is lit.
    solid,

    pub const default: Fill = .gradient;
    pub const all = [_]Fill{ .gradient, .dotted, .hatched, .solid };

    pub fn name(self: Fill) []const u8 {
        return @tagName(self);
    }

    /// Whether a covered pixel with `intensity` (0..1) is lit.
    pub inline fn covers(self: Fill, x: i32, y: i32, intensity: f32) bool {
        return switch (self) {
            .gradient => Matrix.bayer8.on(x, y, intensity),
            // Rust's `/` on i32 truncates toward zero, hence `@divTrunc`.
            .dotted => @mod(x, 2) == 0 and
                @mod(y + @mod(@divTrunc(x, 2), 2), 2) == 0 and
                Matrix.bayer4.on(@divTrunc(x, 2), @divTrunc(y, 2), intensity * 1.4),
            .hatched => @mod(x + y, 3) == 0 and Matrix.bayer4.on(x, y, 0.25 + intensity),
            .solid => intensity > 0.02,
        };
    }
};

/// A fast, well-mixed 32-bit hash of a pixel coordinate.
pub inline fn hash2(x: i32, y: i32) u32 {
    const ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);
    var h = (ux *% 0x9E37_79B1) ^ (uy *% 0x85EB_CA77);
    h ^= h >> 15;
    h *%= 0x2C1B_3C6D;
    h ^= h >> 12;
    h *%= 0x297A_2D39;
    return h ^ (h >> 15);
}

/// Hash of a coordinate as a float in 0..1.
pub inline fn hash01(x: i32, y: i32) f32 {
    return @as(f32, @floatFromInt(hash2(x, y))) / u32_max_f32;
}

const testing = std.testing;

test "bayer8 is a permutation" {
    var seen: [64]bool = @splat(false);
    for (bayer8) |v| {
        try testing.expect(!seen[v]);
        seen[v] = true;
    }
}

test "density tracks intensity" {
    for ([_]Matrix{ .bayer2, .bayer4, .bayer8, .halftone }) |m| {
        var half: usize = 0;
        var none: usize = 0;
        var full: usize = 0;
        for (0..64) |i| {
            const x: i32 = @intCast(i % 8);
            const y: i32 = @intCast(i / 8);
            half += @intFromBool(m.on(x, y, 0.5));
            none += @intFromBool(m.on(x, y, 0.0));
            full += @intFromBool(m.on(x, y, 1.0));
        }
        try testing.expectEqual(32, half);
        try testing.expectEqual(0, none);
        try testing.expectEqual(64, full);
    }
}
