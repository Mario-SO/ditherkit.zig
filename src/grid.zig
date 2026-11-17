//! The renderer-neutral pixel buffer every component draws into.
//! Port of `dither-core/src/grid.rs`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Rgba = @import("color.zig").Rgba;
const dither = @import("dither.zig");
const Matrix = dither.Matrix;
const hash01 = dither.hash01;
const powi = @import("fmath.zig").powi;

/// A width x height buffer of optional pixels. `null` is transparent.
///
/// Frontends only need to paint this: GPU backends paint one quad per
/// horizontal run of equal pixels (`runs`); the terminal frontend packs two
/// pixel rows into each cell with half-block glyphs.
pub const PixelGrid = struct {
    width: usize,
    height: usize,
    cells: []?Rgba,

    pub fn init(gpa: Allocator, width: usize, height: usize) Allocator.Error!PixelGrid {
        const cells = try gpa.alloc(?Rgba, width * height);
        @memset(cells, null);
        return .{ .width = width, .height = height, .cells = cells };
    }

    pub fn deinit(self: *PixelGrid, gpa: Allocator) void {
        gpa.free(self.cells);
        self.* = undefined;
    }

    pub fn clone(self: PixelGrid, gpa: Allocator) Allocator.Error!PixelGrid {
        return .{ .width = self.width, .height = self.height, .cells = try gpa.dupe(?Rgba, self.cells) };
    }

    pub fn isEmpty(self: PixelGrid) bool {
        return self.width == 0 or self.height == 0;
    }

    pub inline fn get(self: PixelGrid, x: usize, y: usize) ?Rgba {
        return if (x < self.width and y < self.height) self.cells[y * self.width + x] else null;
    }

    /// Signed, bounds-checked get.
    pub inline fn at(self: PixelGrid, x: i32, y: i32) ?Rgba {
        if (x < 0 or y < 0) return null;
        return self.get(@intCast(x), @intCast(y));
    }

    /// Signed, bounds-checked write; out-of-bounds writes are ignored.
    pub inline fn plot(self: *PixelGrid, x: i32, y: i32, c: ?Rgba) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux < self.width and uy < self.height) self.cells[uy * self.width + ux] = c;
    }

    /// Lights a pixel with `c`.
    pub inline fn set(self: *PixelGrid, x: i32, y: i32, c: Rgba) void {
        self.plot(x, y, c);
    }

    pub fn clear(self: *PixelGrid) void {
        @memset(self.cells, null);
    }

    pub fn litCount(self: PixelGrid) usize {
        var n: usize = 0;
        for (self.cells) |c| n += @intFromBool(c != null);
        return n;
    }

    /// Draws `other` on top of `self` at offset `(dx, dy)`.
    pub fn overlay(self: *PixelGrid, other: PixelGrid, dx: i32, dy: i32) void {
        for (0..other.height) |y| for (0..other.width) |x| {
            if (other.get(x, y)) |c| self.set(@as(i32, @intCast(x)) + dx, @as(i32, @intCast(y)) + dy, c);
        };
    }

    /// Multiplies every pixel's alpha.
    pub fn fade(self: *PixelGrid, factor: f32) void {
        for (self.cells) |*cell| {
            if (cell.*) |c| cell.* = c.fade(factor);
        }
    }

    /// Horizontal runs of identical lit pixels, row by row.
    pub fn runs(self: *const PixelGrid) RunIterator {
        return .{ .grid = self };
    }

    /// Adds a dithered glow around lit pixels (dither-kit's `bloom`).
    /// Needs a scratch copy of the grid, hence the allocator.
    pub fn bloom(self: *PixelGrid, gpa: Allocator, mode: Bloom) Allocator.Error!void {
        const radius: i32, const strength: f32 = switch (mode) {
            .off => return,
            .low => .{ 1, 0.45 },
            .high => .{ 2, 0.6 },
            .aura => .{ 4, 0.7 },
        };
        var src = try self.clone(gpa);
        defer src.deinit(gpa);

        const h: i32 = @intCast(self.height);
        const w: i32 = @intCast(self.width);
        var y: i32 = 0;
        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                if (src.at(x, y) != null) continue;
                // Nearest lit neighbour within the radius (Chebyshev distance).
                const best: ?struct { i32, Rgba } = search: {
                    var d: i32 = 1;
                    while (d <= radius) : (d += 1) {
                        var oy: i32 = -d;
                        while (oy <= d) : (oy += 1) {
                            var ox: i32 = -d;
                            while (ox <= d) : (ox += 1) {
                                if (@abs(ox) != d and @abs(oy) != d) continue;
                                if (src.at(x + ox, y + oy)) |c| {
                                    if (c.a > 160) break :search .{ d, c };
                                }
                            }
                        }
                    }
                    break :search null;
                };
                if (best) |b| {
                    const d: f32 = @floatFromInt(b[0]);
                    const glow = strength * (1.0 - (d - 1.0) / @as(f32, @floatFromInt(radius)));
                    if (Matrix.bayer4.on(x, y, glow)) self.set(x, y, b[1].fade(0.35 + 0.25 * glow));
                }
            }
        }
    }

    /// Sprinkles twinkling highlight pixels ("sparkles wink").
    ///
    /// `density` is the fraction of pixels that can sparkle; `time` is in
    /// seconds. Sparkles only land on already-lit pixels unless `anywhere`.
    pub fn sparkle(self: *PixelGrid, time: f32, density: f32, c: Rgba, anywhere: bool) void {
        const h: i32 = @intCast(self.height);
        const w: i32 = @intCast(self.width);
        var y: i32 = 0;
        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                if (hash01(x, y ^ 0x5bd1) >= density) continue;
                if (!anywhere and self.at(x, y) == null) continue;
                const phase = hash01(y, x ^ 0x1b56) * std.math.tau;
                const speed = 1.5 + 2.5 * hash01(x ^ 0x77, y);
                const wink = powi(@max(@sin(time * speed + phase), 0.0), 12);
                if (wink > 0.35) self.set(x, y, c.fade(wink));
            }
        }
    }
};

/// A horizontal run of identical pixels.
pub const Run = struct {
    x: usize,
    y: usize,
    len: usize,
    color: Rgba,
};

pub const RunIterator = struct {
    grid: *const PixelGrid,
    x: usize = 0,
    y: usize = 0,

    pub fn next(it: *RunIterator) ?Run {
        const g = it.grid;
        while (it.y < g.height) : ({
            it.y += 1;
            it.x = 0;
        }) {
            const row = g.cells[it.y * g.width ..][0..g.width];
            while (it.x < row.len) {
                const c = row[it.x] orelse {
                    it.x += 1;
                    continue;
                };
                const start = it.x;
                while (it.x < row.len and row[it.x] != null and row[it.x].?.eql(c)) it.x += 1;
                return .{ .x = start, .y = it.y, .len = it.x - start, .color = c };
            }
        }
        return null;
    }
};

/// Glow strength around lit pixels.
pub const Bloom = enum {
    off,
    low,
    high,
    aura,

    pub const default: Bloom = .off;
    pub const all = [_]Bloom{ .off, .low, .high, .aura };

    pub fn name(self: Bloom) []const u8 {
        return @tagName(self);
    }

    pub fn next(self: Bloom) Bloom {
        return switch (self) {
            .off => .low,
            .low => .high,
            .high => .aura,
            .aura => .off,
        };
    }
};

const testing = std.testing;

test "runs merge equal pixels" {
    var g = try PixelGrid.init(testing.allocator, 6, 2);
    defer g.deinit(testing.allocator);
    const a = Rgba.hex(0xff0000);
    const b = Rgba.hex(0x00ff00);
    for (0..3) |x| g.set(@intCast(x), 0, a);
    g.set(4, 0, b);
    g.set(5, 1, a);

    const expected = [_]Run{
        .{ .x = 0, .y = 0, .len = 3, .color = a },
        .{ .x = 4, .y = 0, .len = 1, .color = b },
        .{ .x = 5, .y = 1, .len = 1, .color = a },
    };
    var it = g.runs();
    for (expected) |want| try testing.expectEqual(want, it.next().?);
    try testing.expectEqual(null, it.next());
}

test "bloom only adds pixels" {
    var g = try PixelGrid.init(testing.allocator, 9, 9);
    defer g.deinit(testing.allocator);
    g.set(4, 4, Rgba.white);
    const before = g.litCount();
    try g.bloom(testing.allocator, .aura);
    try testing.expect(g.litCount() > before);
    try testing.expectEqual(Rgba.white, g.get(4, 4).?);
}
