//! Renders the project icon (`assets/icon.svg`) with ditherkit itself: a
//! Bayer-dithered sun setting over water, an OKLCH hue sweep from gold to
//! magenta, bloom, and sparkle stars. Each horizontal run becomes a `<rect>`.
//!
//! `zig build icon -- assets/icon.svg`

const std = @import("std");
const dk = @import("ditherkit");

const size = 32;
const bg = dk.Rgba.hex(0x0b0b0f);

// Sun center and radius, in pixels; rows from `horizon` down are water.
const cx: f32 = 16.0;
const cy: f32 = 14.5;
const r: f32 = 9.5;
const horizon = 21;

pub fn render(gpa: std.mem.Allocator) !dk.PixelGrid {
    var g = try dk.PixelGrid.init(gpa, size, size);
    errdefer g.deinit(gpa);

    // Sun: hue sweeps gold → pink → magenta, and density thins toward the
    // horizon so the Bayer pattern shows through.
    for (0..horizon) |yu| for (0..size) |xu| {
        const x: i32 = @intCast(xu);
        const y: i32 = @intCast(yu);
        const fx = center(x) - cx;
        const fy = center(y) - cy;
        if (fx * fx + fy * fy > r * r) continue;
        const t = std.math.clamp((fy + r) / (r + horizon - cy), 0.0, 1.0);
        if (!dk.Matrix.bayer8.on(x, y, 1.2 - 0.85 * t)) continue;
        g.set(x, y, (dk.Tone{ .hue = 85.0 - 125.0 * t }).shade(0.82 - 0.22 * t));
    };
    try g.bloom(gpa, .high);
    // Keep the glow above the waterline so the horizon reads crisply.
    for (horizon..size) |yu| for (0..size) |xu| g.plot(@intCast(xu), @intCast(yu), null);

    // Reflection: every other row is a streak that narrows and fades with
    // distance, nudged sideways by a stable per-row ripple.
    var y: i32 = horizon + 1;
    while (y < size) : (y += 2) {
        const d = @as(f32, @floatFromInt(y - horizon)) / @as(f32, size - horizon);
        const ripple = 2.0 * (dk.dither.hash01(y, 11) - 0.5);
        const half = r * (1.0 - 0.7 * d) * (0.7 + 0.3 * dk.dither.hash01(y, 23));
        var x: i32 = 0;
        while (x < size) : (x += 1) {
            if (@abs(center(x) - cx - ripple) > half) continue;
            if (!dk.Matrix.bayer4.on(x, y, 0.85 - 0.5 * d)) continue;
            g.set(x, y, (dk.Tone{ .hue = 20.0 - 70.0 * d }).shade(0.7 - 0.25 * d));
        }
    }

    // Stars: one frame of `sparkle`, kept only in open sky.
    var sky = try dk.PixelGrid.init(gpa, size, size);
    defer sky.deinit(gpa);
    sky.sparkle(1.7, 0.12, (dk.Tone{ .hue = 280.0 }).shade(0.95), true);
    for (0..horizon - 2) |yu| for (0..size) |xu| {
        const fx = center(@intCast(xu)) - cx;
        const fy = center(@intCast(yu)) - cy;
        if (fx * fx + fy * fy < (r + 3.0) * (r + 3.0)) continue;
        if (sky.get(xu, yu)) |c| g.set(@intCast(xu), @intCast(yu), c);
    };
    return g;
}

fn center(v: i32) f32 {
    return @as(f32, @floatFromInt(v)) + 0.5;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len > 1) args[1] else "icon.svg";

    var grid = try render(gpa);
    defer grid.deinit(gpa);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa,
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {d} {d}" shape-rendering="crispEdges">
        \\<clipPath id="c"><rect width="{d}" height="{d}" rx="7"/></clipPath>
        \\<g clip-path="url(#c)">
        \\<rect width="{d}" height="{d}" fill="#{x:0>6}"/>
        \\
    , .{ size, size, size, size, size, size, hex(bg) });
    var it = grid.runs();
    while (it.next()) |run| {
        try out.print(gpa, "<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"1\" fill=\"#{x:0>6}\"/>\n", .{
            run.x, run.y, run.len, hex(run.color.over(bg)),
        });
    }
    try out.appendSlice(gpa, "</g>\n</svg>\n");

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = out.items });
    std.debug.print("wrote {s}\n", .{path});
}

fn hex(c: dk.Rgba) u24 {
    return (@as(u24, c.r) << 16) | (@as(u24, c.g) << 8) | c.b;
}
