//! Scenes mirrored by the external Rust reference harness. Keep their
//! inputs in sync as described in PORTING.md.

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

pub fn gradient(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, 37, 23 * 5);
    errdefer g.deinit(gpa);
    for ([_]dk.Direction{ .up, .down, .left, .right, .radial }, 0..) |dir, i| {
        var tile = try (dk.Gradient{
            .from = .blue,
            .to = if (i % 2 == 0) .pink else null,
            .direction = dir,
            .density = 0.82,
        }).render(gpa, 37, 23);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 23));
    }
    return g;
}

pub fn background(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, 53, 33 * dk.Field.all.len);
    errdefer g.deinit(gpa);
    for (dk.Field.all, 0..) |field, i| {
        var tile = try (dk.Background{
            .field = field,
            .tone = .blue,
            .accent = .purple,
        }).render(gpa, 53, 33, -2.37);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 33));
    }
    return g;
}

pub fn button(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, 41, 11 * 3);
    errdefer g.deinit(gpa);
    for ([_]dk.ButtonStyle{ .solid, .outline, .ghost }, 0..) |style, i| {
        var tile = try dk.buttonTexture(gpa, 41, 11, .orange, style, style.density(i == 1, i == 2), 1.7);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 11));
    }
    return g;
}

pub fn avatar(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, 24, 8);
    errdefer g.deinit(gpa);
    for ([_][]const u8{ "Ada Lovelace", "Grace Hopper", "山田" }, 0..) |name, i| {
        var tile = try dk.avatar(gpa, name, if (i == 2) 303.5 else null);
        defer tile.deinit(gpa);
        g.overlay(tile, @intCast(i * 8), 0);
    }
    return g;
}

pub fn meter(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, 51, 9 * dk.Fill.all.len);
    errdefer g.deinit(gpa);
    for (dk.Fill.all, 0..) |fill, i| {
        const value: f32 = @as(f32, @floatFromInt(i)) / 3.0;
        var tile = try dk.meter(gpa, 51, 9, value, .green, fill);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 9));
    }
    return g;
}

const chart_series = [_]dk.Series{
    .{ .label = "a", .tone = .blue, .values = &.{ 3, 8, 5, 9, 7 } },
    .{ .label = "b", .tone = .pink, .values = &.{ 2, 4, 6, 3 }, .fill = .hatched },
    .{ .label = "hidden", .tone = .red, .values = &.{ 11, 0, 8, 0, 0, 10 }, .hidden = true },
};

pub fn cartesian(gpa: Allocator) !PixelGrid {
    var g = try PixelGrid.init(gpa, 81, 37 * 6);
    errdefer g.deinit(gpa);
    for ([_]dk.CartesianKind{ .area, .line, .bar }, 0..) |kind, i| {
        for ([_]bool{ false, true }, 0..) |stacked, j| {
            const c: dk.Cartesian = .{
                .kind = kind,
                .series = &chart_series,
                .stacked = stacked,
                .progress = if (stacked) 0.73 else 1,
                .hover = if (stacked) 3 else null,
                .selected = if (stacked) 1 else null,
                .bloom = if (stacked) .low else .off,
            };
            var tile = try c.render(gpa, 81, 37);
            defer tile.deinit(gpa);
            g.overlay(tile, 0, @intCast((i * 2 + j) * 37));
        }
    }
    return g;
}

pub fn sparkline(gpa: Allocator) !PixelGrid {
    var g = try PixelGrid.init(gpa, 71, 18 * 2);
    errdefer g.deinit(gpa);
    for ([_]bool{ false, true }, 0..) |hovered, i| {
        var tile = try dk.sparkline(gpa, &.{ 3, 5, 2, 7, 6, 9 }, .green, 71, 18, hovered, if (hovered) 0.78 else 1);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 18));
    }
    return g;
}

pub fn pie(gpa: Allocator) !PixelGrid {
    const slices = [_]dk.Slice{
        .{ .value = 3, .tone = .orange },
        .{ .value = 1, .tone = .green, .fill = .dotted },
        .{ .value = -1, .tone = .red },
        .{ .value = 2, .tone = .purple, .fill = .solid },
    };
    var g = try PixelGrid.init(gpa, 53, 49 * 2);
    errdefer g.deinit(gpa);
    for ([_]bool{ false, true }, 0..) |donut, i| {
        const p: dk.Pie = .{
            .slices = &slices,
            .inner_radius = if (donut) 0.51 else 0,
            .progress = if (donut) 0.86 else 1,
            .hover = if (donut) 1 else null,
        };
        var tile = try p.render(gpa, 53, 49);
        defer tile.deinit(gpa);
        g.overlay(tile, 0, @intCast(i * 49));
    }
    return g;
}

pub fn radar(gpa: Allocator) !PixelGrid {
    const r: dk.Radar = .{
        .series = &chart_series,
        .progress = 0.91,
        .selected = 1,
        .rings = 5,
        .bloom = .low,
    };
    return r.render(gpa, 61, 47);
}
