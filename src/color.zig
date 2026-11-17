//! Colors, named tones, and perceptual (OKLCH) shade ramps.
//! Port of `dither-core/src/color.rs`.

const std = @import("std");
const math = std.math;
const fmath = @import("fmath.zig");

/// An 8-bit sRGB color with straight (non-premultiplied) alpha.
pub const Rgba = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub const transparent: Rgba = .{};
    pub const black: Rgba = rgb(0, 0, 0);
    pub const white: Rgba = rgb(255, 255, 255);

    pub fn init(r: u8, g: u8, b: u8, a: u8) Rgba {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Rgba {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    /// Parses `0xRRGGBB`.
    pub fn hex(v: u24) Rgba {
        return rgb(@truncate(v >> 16), @truncate(v >> 8), @truncate(v));
    }

    pub fn withAlpha(self: Rgba, a: u8) Rgba {
        var c = self;
        c.a = a;
        return c;
    }

    pub fn eql(self: Rgba, other: Rgba) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }

    /// Multiplies the alpha channel by `factor` (0..=1).
    pub fn fade(self: Rgba, factor: f32) Rgba {
        return self.withAlpha(toU8(@as(f32, @floatFromInt(self.a)) * math.clamp(factor, 0.0, 1.0)));
    }

    /// Linear interpolation in sRGB space (`t = 0` is `self`).
    pub fn mix(self: Rgba, other: Rgba, t: f32) Rgba {
        const tc = math.clamp(t, 0.0, 1.0);
        const l = struct {
            fn f(a: u8, b: u8, k: f32) u8 {
                const af: f32 = @floatFromInt(a);
                const bf: f32 = @floatFromInt(b);
                return toU8(af + (bf - af) * k);
            }
        }.f;
        return init(l(self.r, other.r, tc), l(self.g, other.g, tc), l(self.b, other.b, tc), l(self.a, other.a, tc));
    }

    /// Composites `self` over an opaque `background`, returning an opaque color.
    pub fn over(self: Rgba, background: Rgba) Rgba {
        return background.withAlpha(255).mix(self.withAlpha(255), @as(f32, @floatFromInt(self.a)) / 255.0);
    }

    /// Relative luminance (WCAG), used to choose legible label colors.
    pub fn luminance(self: Rgba) f32 {
        const lin = struct {
            fn f(c: u8) f32 {
                const v = @as(f32, @floatFromInt(c)) / 255.0;
                return if (v <= 0.04045) v / 12.92 else fmath.powf((v + 0.055) / 1.055, 2.4);
            }
        }.f;
        return 0.2126 * lin(self.r) + 0.7152 * lin(self.g) + 0.0722 * lin(self.b);
    }

    /// Converts an OKLCH color (`l` 0..1, `c` ~0..0.37, `h` degrees) to sRGB,
    /// reducing chroma until the color fits inside the sRGB gamut.
    pub fn oklch(l: f32, c: f32, h: f32) Rgba {
        var cc = @max(c, 0.0);
        while (true) {
            if (oklchToSrgb(l, cc, h)) |v| return v;
            cc -= 0.005;
            if (cc <= 0.0) return oklchToSrgb(l, 0.0, h) orelse black;
        }
    }
};

/// Rounds and saturates like Rust's `f32 as u8`.
fn toU8(v: f32) u8 {
    return @intFromFloat(math.clamp(@round(v), 0.0, 255.0));
}

fn oklchToSrgb(l: f32, c: f32, h: f32) ?Rgba {
    const hr = math.degreesToRadians(h);
    const a = c * @cos(hr);
    const b = c * @sin(hr);
    const l_ = l + 0.39633778 * a + 0.21580376 * b;
    const m_ = l - 0.105561346 * a - 0.06385417 * b;
    const s_ = l - 0.08948418 * a - 1.2914855 * b;
    const l3 = l_ * l_ * l_;
    const m3 = m_ * m_ * m_;
    const s3 = s_ * s_ * s_;
    const r = 4.0767417 * l3 - 3.3077116 * m3 + 0.23096994 * s3;
    const g = -1.268438 * l3 + 2.6097574 * m3 - 0.34131938 * s3;
    const bb = -0.0041960863 * l3 - 0.7034186 * m3 + 1.7076147 * s3;
    const eps = 1e-4;
    for ([_]f32{ r, g, bb }) |v| {
        if (v < -eps or v > 1.0 + eps) return null;
    }
    const enc = struct {
        fn f(v: f32) u8 {
            const x = math.clamp(v, 0.0, 1.0);
            const s = if (x <= 0.0031308) 12.92 * x else 1.055 * fmath.powf(x, 1.0 / 2.4) - 0.055;
            return toU8(s * 255.0);
        }
    }.f;
    return Rgba.rgb(enc(r), enc(g), enc(bb));
}

/// A named dither color, or any hue in degrees.
///
/// Each tone expands into a perceptual shade ramp via `shade`, so every
/// component gets matching dark, mid, and highlight colors.
pub const Tone = union(enum) {
    green,
    blue,
    purple,
    pink,
    orange,
    red,
    grey,
    /// Any hue, 0..360 degrees.
    hue: f32,

    /// The named tones, in legend order.
    pub const all = [_]Tone{ .green, .blue, .purple, .pink, .orange, .red, .grey };

    pub fn name(self: Tone) []const u8 {
        return @tagName(self);
    }

    /// Parses a tone name (`"blue"`) or a hue number (`"210"`).
    pub fn parse(s: []const u8) ?Tone {
        const t = std.mem.trim(u8, s, &std.ascii.whitespace);
        const names = [_]struct { []const u8, Tone }{
            .{ "green", .green },   .{ "blue", .blue },
            .{ "purple", .purple }, .{ "violet", .purple },
            .{ "pink", .pink },     .{ "orange", .orange },
            .{ "red", .red },       .{ "grey", .grey },
            .{ "gray", .grey },
        };
        for (names) |n| if (std.ascii.eqlIgnoreCase(t, n[0])) return n[1];
        const h = std.fmt.parseFloat(f32, t) catch return null;
        return .{ .hue = @mod(h, 360.0) };
    }

    pub fn hueDegrees(self: Tone) f32 {
        return switch (self) {
            .green => 150.0,
            .blue => 250.0,
            .purple => 300.0,
            .pink => 350.0,
            .orange => 55.0,
            .red => 25.0,
            .grey => 260.0,
            .hue => |h| @mod(h, 360.0),
        };
    }

    fn chroma(self: Tone) f32 {
        return switch (self) {
            .grey => 0.012,
            else => 0.19,
        };
    }

    /// A color along this tone's ramp: `0.0` is near-black, `0.5` is the
    /// signature color, `1.0` is a pale highlight.
    pub fn shade(self: Tone, level: f32) Rgba {
        const lv = math.clamp(level, 0.0, 1.0);
        const l = 0.22 + lv * 0.72;
        // Chroma peaks around the middle of the ramp and tapers at both ends.
        const c = self.chroma() * math.clamp(1.0 - @abs(lv - 0.55) * 1.3, 0.25, 1.0);
        return Rgba.oklch(l, c, self.hueDegrees());
    }

    /// The tone's signature color.
    pub fn base(self: Tone) Rgba {
        return self.shade(0.55);
    }
};

const testing = std.testing;

test "white and black round trip" {
    try testing.expectEqual(Rgba.white, Rgba.oklch(1.0, 0.0, 0.0));
    try testing.expectEqual(Rgba.black, Rgba.oklch(0.0, 0.0, 0.0));
}

test "shades get brighter" {
    for (Tone.all) |tone| {
        var prev: f32 = -1.0;
        for (0..11) |i| {
            const lum = tone.shade(@as(f32, @floatFromInt(i)) / 10.0).luminance();
            try testing.expect(lum >= prev);
            prev = lum;
        }
    }
}

test "parse tones" {
    try testing.expectEqual(Tone.grey, Tone.parse("Gray").?);
    try testing.expectEqual(Tone{ .hue = 40.0 }, Tone.parse("400").?);
    try testing.expectEqual(null, Tone.parse("nope"));
}
