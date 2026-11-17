//! Zig twins of the scenes in `tools/golden-gen/src/main.rs`. Each function
//! must draw exactly what its Rust counterpart draws; keep them in sync.

const std = @import("std");
const dk = @import("ditherkit");
const Allocator = std.mem.Allocator;
const PixelGrid = dk.PixelGrid;
const Rgba = dk.Rgba;
const Tone = dk.Tone;

const matrices_list = [_]dk.Matrix{ .bayer2, .bayer4, .bayer8, .halftone, .noise };

fn int(v: usize) i32 {
    return @intCast(v);
}

fn ramp(x: usize) f32 {
    return @as(f32, @floatFromInt(x)) / 63.0;
}

pub fn shades(gpa: Allocator) !PixelGrid {
    const tones = Tone.all ++ [_]Tone{ .{ .hue = 42.5 }, .{ .hue = -30.0 } };
    var g = try PixelGrid.init(gpa, 101, tones.len);
    for (tones, 0..) |tone, t| {
        for (0..101) |i| g.set(int(i), int(t), tone.shade(@as(f32, @floatFromInt(i)) / 100.0));
    }
    return g;
}

/// Ramps through each matrix, in coordinates centred on 0 to cover negatives.
pub fn matrices(gpa: Allocator) !PixelGrid {
    var g = try PixelGrid.init(gpa, 64, 64 * matrices_list.len);
    for (matrices_list, 0..) |m, k| {
        for (0..64) |y| for (0..64) |x| {
            if (m.on(int(x) - 32, int(y) - 32, ramp(x))) g.set(int(x), int(k * 64 + y), Rgba.white);
        };
    }
    return g;
}

pub fn fills(gpa: Allocator) !PixelGrid {
    var g = try PixelGrid.init(gpa, 64, 64 * dk.Fill.all.len);
    for (dk.Fill.all, 0..) |f, k| {
        for (0..64) |y| for (0..64) |x| {
            if (f.covers(int(x) - 32, int(y) - 32, ramp(x))) g.set(int(x), int(k * 64 + y), Rgba.white);
        };
    }
    return g;
}

pub fn seed(gpa: Allocator, w: usize, h: usize) !PixelGrid {
    var g = try PixelGrid.init(gpa, w, h);
    const c = @as(Tone, .blue).shade(0.6);
    for (0..h) |y| for (0..w) |x| {
        switch (dk.dither.hash2(int(x), int(y)) % 23) {
            0 => g.set(int(x), int(y), c),
            1 => g.set(int(x), int(y), c.withAlpha(100)),
            else => {},
        }
    };
    return g;
}

pub fn bloom(gpa: Allocator) !PixelGrid {
    var out = try PixelGrid.init(gpa, 32, 32 * dk.Bloom.all.len);
    errdefer out.deinit(gpa);
    for (dk.Bloom.all, 0..) |b, k| {
        var g = try seed(gpa, 32, 32);
        defer g.deinit(gpa);
        try g.bloom(gpa, b);
        out.overlay(g, 0, int(k * 32));
    }
    return out;
}

pub fn sparkle(gpa: Allocator) !PixelGrid {
    var out = try PixelGrid.init(gpa, 48, 96);
    errdefer out.deinit(gpa);
    const runs = [_]struct { f32, bool }{ .{ 1.7, false }, .{ 4.2, true } };
    for (runs, 0..) |r, k| {
        var g = try PixelGrid.init(gpa, 48, 48);
        defer g.deinit(gpa);
        for (0..48) |y| for (0..48) |x| {
            if ((x + y) % 3 == 0) g.set(int(x), int(y), @as(Tone, .pink).base());
        };
        g.sparkle(r[0], 0.3, Rgba.white, r[1]);
        g.fade(0.8);
        out.overlay(g, 0, int(k * 48));
    }
    return out;
}
