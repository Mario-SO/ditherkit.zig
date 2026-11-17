//! Standalone dithered surfaces.

const std = @import("std");
const fmath = @import("fmath.zig");
const dither = @import("dither.zig");
const Matrix = dither.Matrix;
const Fill = dither.Fill;
const Rgba = @import("color.zig").Rgba;
const Tone = @import("color.zig").Tone;
const PixelGrid = @import("grid.zig").PixelGrid;
const Allocator = std.mem.Allocator;

pub const Direction = enum {
    up,
    down,
    left,
    right,
    radial,

    pub fn position(self: Direction, x: usize, y: usize, w: usize, h: usize) f32 {
        const fx = fraction(x, w);
        const fy = fraction(y, h);
        return switch (self) {
            .up => 1.0 - fy,
            .down => fy,
            .left => 1.0 - fx,
            .right => fx,
            .radial => blk: {
                const dx = fx - 0.5;
                const dy = fy - 0.5;
                break :blk @min(@sqrt(dx * dx + dy * dy) / @as(f32, 1.0 / @sqrt(2.0)), 1.0);
            },
        };
    }
};

fn fraction(i: usize, len: usize) f32 {
    return if (len > 1) float(i) / float(len - 1) else 0.5;
}

fn float(n: usize) f32 {
    return @floatFromInt(n);
}

pub const Gradient = struct {
    from: Tone,
    to: ?Tone = null,
    direction: Direction = .up,
    matrix: Matrix = .bayer8,
    density: f32 = 1,

    pub fn render(self: Gradient, gpa: Allocator, w: usize, h: usize) Allocator.Error!PixelGrid {
        var g = try PixelGrid.init(gpa, w, h);
        const density = unit(self.density);
        switch (self.direction) {
            .up, .down => for (0..h) |y| {
                const p = self.direction.position(0, y, w, h);
                const shades = self.shadesAt(p);
                for (0..w) |x| {
                    g.cells[y * w + x] = self.pixel(x, y, p, density, shades);
                }
            },
            .left, .right => for (0..w) |x| {
                const p = self.direction.position(x, 0, w, h);
                const shades = self.shadesAt(p);
                for (0..h) |y| {
                    g.cells[y * w + x] = self.pixel(x, y, p, density, shades);
                }
            },
            .radial => for (0..h) |y| {
                for (0..w) |x| {
                    const p = self.direction.position(x, y, w, h);
                    g.cells[y * w + x] = self.pixel(x, y, p, density, null);
                }
            },
        }
        return g;
    }

    const Shades = struct { from: Rgba, to: ?Rgba };

    fn shadesAt(self: Gradient, p: f32) Shades {
        if (self.to) |to| {
            const level = 0.35 + 0.35 * p;
            return .{ .from = self.from.shade(level), .to = to.shade(level) };
        }
        return .{ .from = self.from.shade(0.3 + 0.4 * (1.0 - p)), .to = null };
    }

    inline fn pixel(self: Gradient, x: usize, y: usize, p: f32, density: f32, shades: ?Shades) ?Rgba {
        const xi: i32 = @intCast(x);
        const yi: i32 = @intCast(y);
        if (self.to) |to| {
            if (!self.matrix.on(xi +% 3, yi +% 5, density * (0.55 + 0.45 * p))) return null;
            const use_to = self.matrix.on(xi, yi, p);
            if (shades) |s| return if (use_to) s.to.? else s.from;
            const tone = if (use_to) to else self.from;
            return tone.shade(0.35 + 0.35 * p);
        }
        if (!self.matrix.on(xi, yi, (1.0 - p) * density)) return null;
        return if (shades) |s| s.from else self.from.shade(0.3 + 0.4 * (1.0 - p));
    }
};

pub const Field = enum {
    plasma,
    waves,
    ripple,
    noise,
    aurora,

    pub const all = [_]Field{ .plasma, .waves, .ripple, .noise, .aurora };

    pub fn name(self: Field) []const u8 {
        return @tagName(self);
    }

    pub fn sample(self: Field, u: f32, v: f32, t: f32) f32 {
        return switch (self) {
            inline else => |field| sampleField(field, u, v, t),
        };
    }

    inline fn sampleField(comptime field: Field, u: f32, v: f32, t: f32) f32 {
        const sin = fmath.sinf;
        return unit(switch (field) {
            .plasma => blk: {
                const a = sin(u * 7.0 + t * 0.9);
                const b = sin(v * 6.0 - t * 0.7);
                const c = sin((u + v) * 5.0 + t * 0.5);
                const d = sin(radius(u, v) * 12.0 - t * 1.2);
                break :blk (a + b + c + d) / 8.0 + 0.5;
            },
            .waves => blk: {
                const crest = 0.5 + 0.18 * sin(u * 6.0 + t * 1.1) + 0.08 * sin(u * 15.0 - t * 1.7);
                break :blk unit(1.0 - @abs(v - crest) * 2.6) * 0.9 + v * 0.15;
            },
            .ripple => blk: {
                const d = radius(u, v);
                break :blk 0.5 + 0.5 * sin(d * 30.0 - t * 3.0) * @max(1.0 - d * 1.2, 0.0);
            },
            .noise => valueNoise(u * 6.0 + t * 0.35, v * 4.0 - t * 0.2) * 0.7 +
                valueNoise(u * 13.0 - t * 0.5, v * 9.0) * 0.3,
            .aurora => blk: {
                const curtain = valueNoise(u * 5.0 + t * 0.25, t * 0.15) * 0.6 + 0.4 * @abs(sin(u * 9.0 + t * 0.6));
                break :blk curtain * unit(1.0 - @max(v - 0.35 * curtain, 0.0) * 1.6);
            },
        });
    }
};

inline fn unit(x: f32) f32 {
    return fmath.clamp(x, 0, 1);
}

inline fn radius(u: f32, v: f32) f32 {
    const x = u - 0.5;
    const y = v - 0.5;
    return @sqrt(x * x + y * y);
}

inline fn smooth(t: f32) f32 {
    return t * t * (3.0 - 2.0 * t);
}

inline fn valueNoise(x: f32, y: f32) f32 {
    const floor_x = @floor(x);
    const floor_y = @floor(y);
    const xi = fmath.saturatingInt(i32, floor_x);
    const yi = fmath.saturatingInt(i32, floor_y);
    const sx = smooth(x - floor_x);
    const sy = smooth(y - floor_y);
    const a = dither.hash01(xi, yi);
    const b = dither.hash01(xi, yi +% 1);
    const top = a + (dither.hash01(xi +% 1, yi) - a) * sx;
    const bottom = b + (dither.hash01(xi +% 1, yi +% 1) - b) * sx;
    return top + (bottom - top) * sy;
}

pub const Background = struct {
    field: Field,
    tone: Tone,
    accent: ?Tone = null,
    matrix: Matrix = .bayer8,
    density: f32 = 0.6,

    pub fn render(self: Background, gpa: Allocator, w: usize, h: usize, time: f32) Allocator.Error!PixelGrid {
        var g = try PixelGrid.init(gpa, w, h);
        switch (self.field) {
            inline else => |field| self.renderField(field, &g, time),
        }
        return g;
    }

    fn renderField(self: Background, comptime field: Field, g: *PixelGrid, time: f32) void {
        const w = g.width;
        const fw = float(@max(w, 1));
        const fh = float(@max(g.height, 1));
        const density = unit(self.density);
        for (0..g.height) |y| {
            const v = float(y) / fh;
            const yi: i32 = @intCast(y);
            for (g.cells[y * w ..][0..w], 0..) |*cell, x| {
                const xi: i32 = @intCast(x);
                const sampled = Field.sampleField(field, float(x) / fw, v, time);
                const intensity = smooth(unit((sampled - 0.18) / (0.82 - @as(f32, 0.18))));
                if (!self.matrix.on(xi, yi, intensity * density)) continue;
                const tone = if (self.accent) |accent| blk: {
                    break :blk if (Matrix.bayer4.on(xi +% 1, yi +% 2, (intensity - 0.62) * 2.2)) accent else self.tone;
                } else self.tone;
                cell.* = tone.shade(0.3 + 0.5 * intensity);
            }
        }
    }
};

pub const ButtonStyle = enum {
    solid,
    outline,
    ghost,

    pub fn density(self: ButtonStyle, hovered: bool, pressed: bool) f32 {
        return switch (self) {
            .solid => if (pressed) 0.85 else if (hovered) 0.55 else 0.32,
            .outline => if (pressed) 0.6 else if (hovered) 0.3 else 0,
            .ghost => if (pressed) 0.5 else if (hovered) 0.25 else 0,
        };
    }

    pub fn surface(self: ButtonStyle, tone: Tone) ?Rgba {
        return if (self == .solid) tone.shade(0.22) else null;
    }
};

pub fn buttonTexture(gpa: Allocator, w: usize, h: usize, tone: Tone, style: ButtonStyle, density: f32, time: f32) Allocator.Error!PixelGrid {
    var g = try PixelGrid.init(gpa, w, h);
    const frame = tone.shade(0.6);
    for (0..h) |y| {
        const fy = fraction(y, h);
        const intensity = density * (1.05 - 0.45 * fy);
        const color = tone.shade(0.45 + 0.25 * (1.0 - fy));
        for (g.cells[y * w ..][0..w], 0..) |*cell, x| {
            const edge = x == 0 or y == 0 or x + 1 == w or y + 1 == h;
            if (edge and style != .ghost) {
                if ((x + y) % 2 == 0 or style == .solid) cell.* = frame;
                continue;
            }
            if (Fill.gradient.covers(@intCast(x), @intCast(y), intensity)) cell.* = color;
        }
    }
    if (density > 0.4) g.sparkle(time, 0.04 * density, tone.shade(0.97), false);
    return g;
}

/// A deterministic 8×8 identicon, mirrored horizontally or vertically.
pub fn avatar(gpa: Allocator, name: []const u8, hue: ?f32) Allocator.Error!PixelGrid {
    const hash = fnv1a(name);
    const bits: u32 = @truncate(hash);
    const mirror_x = (hash >> 32) & 1 == 0;
    const tone: Tone = .{ .hue = hue orelse @as(f32, @floatFromInt((hash >> 33) % 180)) * 2.0 };
    const accent_bits: u32 = @intCast(hash >> 41);
    const colors = [_]Rgba{ tone.shade(0.16), tone.shade(0.62), tone.shade(0.92) };
    var g = try PixelGrid.init(gpa, 8, 8);
    for (0..32) |i| {
        const x = if (mirror_x) i % 4 else i % 8;
        const y = if (mirror_x) i / 4 else i / 8;
        const mx = if (mirror_x) 7 - x else x;
        const my = if (mirror_x) y else 7 - y;
        const on = (bits >> @as(u5, @intCast(i))) & 1 == 1;
        const accent = (accent_bits >> @as(u5, @intCast(i % 23))) &
            (accent_bits >> @as(u5, @intCast((i + 7) % 23))) & 1 == 1;
        const c = colors[if (!on) 0 else if (accent) 2 else 1];
        g.cells[y * 8 + x] = c;
        g.cells[my * 8 + mx] = c;
    }
    return g;
}

/// 64-bit FNV-1a over the name's bytes.
pub fn fnv1a(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (bytes) |b| hash = (hash ^ b) *% 0x0000_0100_0000_01b3;
    return hash;
}

pub fn meter(gpa: Allocator, w: usize, h: usize, value: f32, tone: Tone, fill: Fill) Allocator.Error!PixelGrid {
    var g = try PixelGrid.init(gpa, w, h);
    const filled = @min(w, fmath.saturatingInt(usize, @round(unit(value) * float(w))));
    const track = @as(Tone, .grey).shade(0.35).fade(0.6);
    for (0..filled) |x| {
        const i = 0.35 + 0.65 * (float(x) + 1.0) / float(filled);
        const color = tone.shade(0.4 + 0.35 * i);
        for (0..h) |y| {
            if (fill.covers(@intCast(x), @intCast(y), i) or x + 1 == filled) g.cells[y * w + x] = color;
        }
    }
    for (0..h) |y| {
        var x = filled + ((0 -% (filled +% y)) & 3);
        while (x < w) : (x += 4) g.cells[y * w + x] = track;
    }
    return g;
}

test "fields stay in range" {
    for (Field.all) |field| {
        for (0..50) |i| {
            const value = field.sample(float(i) / 50.0, float(i * 7 % 50) / 50.0, float(i) * 0.3);
            try std.testing.expect(value >= 0 and value <= 1);
        }
    }
}
