//! Performance benchmarks. Same workloads and report as the Rust twin in
//! the external Rust reference harness for line-by-line comparison.
//! See PORTING.md for the reference command.
//!
//!   zig build bench        # optimized for speed

const std = @import("std");
const dk = @import("ditherkit");
const scenes = @import("scenes");
const Io = std.Io;

const budget_ns: i96 = 400 * std.time.ns_per_ms;

/// Best time over repeated runs until the time budget (min 5 runs) is spent.
fn measure(io: Io, w: *Io.Writer, name: []const u8, ctx: anytype, comptime f: anytype) !void {
    var best: i96 = std.math.maxInt(i96);
    var n: u32 = 0;
    const start = Io.Timestamp.now(io, .awake);
    while (n < 5 or start.untilNow(io, .awake).nanoseconds < budget_ns) : (n += 1) {
        const t = Io.Timestamp.now(io, .awake);
        std.mem.doNotOptimizeAway(try f(ctx));
        best = @min(best, t.untilNow(io, .awake).nanoseconds);
    }
    try w.print("{s:<14} {d:>12.1} us\n", .{ name, @as(f64, @floatFromInt(best)) / 1000.0 });
}

fn shade(_: void) !u64 {
    var acc: u64 = 0;
    for (0..100_000) |i| {
        const tone = dk.Tone.all[i % 7];
        acc += tone.shade(@as(f32, @floatFromInt(i % 1001)) / 1000.0).r;
    }
    return acc;
}

fn matrixFill(_: void) !u64 {
    var acc: u64 = 0;
    var y: i32 = 0;
    while (y < 512) : (y += 1) {
        var x: i32 = 0;
        while (x < 512) : (x += 1) {
            const t = @as(f32, @floatFromInt(x)) / 511.0;
            acc += @intFromBool(dk.Matrix.bayer8.on(x, y, t)) + @intFromBool(dk.Fill.dotted.covers(x, y, t));
        }
    }
    return acc;
}

fn bloomAura(gpa: std.mem.Allocator) !u64 {
    var g = try scenes.seed(gpa, 256, 256);
    defer g.deinit(gpa);
    try g.bloom(gpa, .aura);
    return g.litCount();
}

fn sparkle(gpa: std.mem.Allocator) !u64 {
    var g = try dk.PixelGrid.init(gpa, 256, 256);
    defer g.deinit(gpa);
    const c = @as(dk.Tone, .pink).base();
    for (0..256) |y| for (0..256) |x| {
        if ((x + y) % 3 == 0) g.set(@intCast(x), @intCast(y), c);
    };
    g.sparkle(1.7, 0.3, dk.Rgba.white, false);
    return g.litCount();
}

fn runs(g: *const dk.PixelGrid) !u64 {
    var sum: u64 = 0;
    var it = g.runs();
    while (it.next()) |r| sum += r.len;
    return sum;
}

fn renderScene(comptime render: fn (std.mem.Allocator) anyerror!dk.PixelGrid) fn (std.mem.Allocator) anyerror!u64 {
    return struct {
        fn run(gpa: std.mem.Allocator) !u64 {
            var g = try render(gpa);
            defer g.deinit(gpa);
            return g.litCount();
        }
    }.run;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Same allocator class as Rust's global allocator (libc malloc).
    const gpa = std.heap.c_allocator;

    var buf: [1024]u8 = undefined;
    var fw: Io.File.Writer = .init(.stdout(), io, &buf);
    const w = &fw.interface;

    try w.writeAll("zig (ditherkit)\n");
    try measure(io, w, "shade", {}, shade);
    try measure(io, w, "matrix_fill", {}, matrixFill);
    try measure(io, w, "bloom_aura", gpa, bloomAura);
    try measure(io, w, "sparkle", gpa, sparkle);
    var g = try scenes.seed(gpa, 512, 512);
    defer g.deinit(gpa);
    try measure(io, w, "runs", @as(*const dk.PixelGrid, &g), runs);
    try measure(io, w, "gradient", gpa, renderScene(scenes.gradient));
    try measure(io, w, "background", gpa, renderScene(scenes.background));
    try measure(io, w, "button", gpa, renderScene(scenes.button));
    try measure(io, w, "avatar", gpa, renderScene(scenes.avatar));
    try measure(io, w, "meter", gpa, renderScene(scenes.meter));
    try measure(io, w, "cartesian", gpa, renderScene(scenes.cartesian));
    try measure(io, w, "sparkline", gpa, renderScene(scenes.sparkline));
    try measure(io, w, "pie", gpa, renderScene(scenes.pie));
    try measure(io, w, "radar", gpa, renderScene(scenes.radar));
    try w.flush();
}
