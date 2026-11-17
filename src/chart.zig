//! Chart rasterizers and geometry for frontend labels and hit testing.

const std = @import("std");
const fmath = @import("fmath.zig");
const color = @import("color.zig");
const grid = @import("grid.zig");
const Fill = @import("dither.zig").Fill;
const Tone = color.Tone;
const Rgba = color.Rgba;
const PixelGrid = grid.PixelGrid;
const Bloom = grid.Bloom;
const Allocator = std.mem.Allocator;

pub const Point = struct { x: f32, y: f32 };
pub const Pixel = struct { x: i32, y: i32 };

/// Labels and samples are borrowed from the caller.
pub const Series = struct {
    label: []const u8 = "",
    tone: Tone,
    values: []const f64,
    fill: Fill = .gradient,
    hidden: bool = false,
};

pub const Scale = struct {
    max: f64,
    ticks: []const f64,

    pub fn nice(gpa: Allocator, max: f64, count: usize) Allocator.Error!Scale {
        const bounds = niceBounds(max, count);
        const intervals = fmath.saturatingInt(usize, @round(bounds.max / bounds.step));
        const ticks = try gpa.alloc(f64, std.math.add(usize, intervals, 1) catch return error.OutOfMemory);
        for (ticks, 0..) |*tick, i| tick.* = float64(i) * bounds.step;
        return .{ .max = bounds.max, .ticks = ticks };
    }

    pub fn deinit(self: *Scale, gpa: Allocator) void {
        gpa.free(self.ticks);
        self.* = undefined;
    }

    pub fn y(self: Scale, value: f64, h: usize) f32 {
        const span = float(h -| 1);
        return span - @as(f32, @floatCast(fmath.clamp(value / self.max, 0, 1))) * span;
    }
};

fn niceBounds(max: f64, count: usize) struct { max: f64, step: f64 } {
    const finite_max = if (std.math.isFinite(max) and max > 0) max else 1.0;
    const raw = finite_max / float64(@max(count, 1));
    const mag = fmath.pow(10, @floor(fmath.log10(raw)));
    var step = 10.0 * mag;
    for ([_]f64{ 1, 2, 2.5, 5 }) |factor| {
        const candidate = factor * mag;
        if (candidate >= raw) {
            step = candidate;
            break;
        }
    }
    return .{ .max = @ceil(finite_max / step) * step, .step = step };
}

/// Writes a compact value such as 950, 1.2k or 3.4M to a caller-owned buffer.
pub fn formatValue(buf: []u8, value: f64) error{NoSpaceLeft}![]u8 {
    if (std.math.isNan(value)) return std.fmt.bufPrint(buf, "NaN", .{});
    const a = @abs(value);
    const n = if (a >= 1e9) value / 1e9 else if (a >= 1e6) value / 1e6 else if (a >= 1e3) value / 1e3 else value;
    const suffix = if (a >= 1e9) "B" else if (a >= 1e6) "M" else if (a >= 1e3) "k" else "";
    if (@abs(n - @round(n)) < 0.05) {
        return std.fmt.bufPrint(buf, "{d}{s}", .{ fmath.saturatingInt(i64, @round(n)), suffix });
    }
    return std.fmt.bufPrint(buf, "{d:.1}{s}", .{ n, suffix });
}

/// Overshoot-free interpolation at a fractional sample index.
pub fn interpolate(values: []const f64, index: f32) f64 {
    const n = values.len;
    if (n == 0) return 0;
    if (n == 1) return values[0];
    const f = fmath.clamp(index, 0, float(n - 1));
    const i = @min(fmath.saturatingInt(usize, @floor(f)), n - 2);
    const t: f64 = f - float(i);
    const p0 = values[i -| 1];
    const p1 = values[i];
    const p2 = values[i + 1];
    const p3 = values[@min(i + 2, n - 1)];
    const v = 0.5 * (2.0 * p1 + (-p0 + p2) * t +
        (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t +
        (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
    return fmath.clamp(v, @min(p1, p2), @max(p1, p2));
}

/// Bresenham line. A dash greater than one draws every nth pixel.
pub fn line(g: *PixelGrid, from: Pixel, to: Pixel, c: Rgba, dash: u32) void {
    const dx: i64 = @intCast(@abs(@as(i64, to.x) - from.x));
    const dy: i64 = -@as(i64, @intCast(@abs(@as(i64, to.y) - from.y)));
    const sx: i32 = if (from.x < to.x) 1 else -1;
    const sy: i32 = if (from.y < to.y) 1 else -1;
    var p = from;
    var err = dx + dy;
    var step: u32 = 0;
    while (true) : (step += 1) {
        if (dash <= 1 or step % dash == 0) g.set(p.x, p.y, c);
        if (p.x == to.x and p.y == to.y) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            p.x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            p.y += sy;
        }
    }
}

fn dot(g: *PixelGrid, p: Pixel, ring: Rgba, center: Rgba) void {
    for ([_]i32{ -1, 0, 1 }) |oy| {
        for ([_]i32{ -1, 0, 1 }) |ox| {
            g.set(p.x +% ox, p.y +% oy, if (ox == 0 and oy == 0) center else ring);
        }
    }
}

pub fn guide() Rgba {
    return @as(Tone, .grey).shade(0.55).fade(0.45);
}

fn float(n: anytype) f32 {
    return @floatFromInt(n);
}

fn float64(n: usize) f64 {
    return @floatFromInt(n);
}

fn pixel(n: f32) i32 {
    return fmath.saturatingInt(i32, n);
}

fn maxLen(series: []const Series) usize {
    var n: usize = 0;
    for (series) |s| n = @max(n, s.values.len);
    return n;
}

fn valueAt(values: []const f64, i: usize) f64 {
    return if (i < values.len) values[i] else 0.0;
}

fn alphaFor(selected: ?usize, i: usize) f32 {
    return if (selected != null and selected.? != i) 0.3 else 1.0;
}

pub const CartesianKind = enum { area, line, bar };

pub const Cartesian = struct {
    kind: CartesianKind = .area,
    series: []const Series,
    stacked: bool = false,
    progress: f32 = 1,
    hover: ?usize = null,
    selected: ?usize = null,
    bloom: Bloom = .off,
    y_max: ?f64 = null,
    grid_lines: bool = true,
    tick_count: usize = 4,

    pub fn len(self: Cartesian) usize {
        return maxLen(self.series);
    }

    pub fn isEmpty(self: Cartesian) bool {
        return self.len() == 0;
    }

    pub fn scale(self: Cartesian, gpa: Allocator) Allocator.Error!Scale {
        return Scale.nice(gpa, self.dataMax(), self.tick_count);
    }

    fn dataMax(self: Cartesian) f64 {
        if (self.y_max) |max| return max;
        var max: f64 = 0;
        if (self.stacked) {
            for (0..self.len()) |i| max = @max(max, self.stackBelow(self.series.len, i));
        } else {
            for (self.series) |s| {
                if (s.hidden) continue;
                for (s.values) |v| max = @max(max, v);
            }
        }
        return max;
    }

    pub fn columnX(self: Cartesian, i: usize, w: usize) f32 {
        return self.columnAt(i, w, @max(1, self.len()));
    }

    fn columnAt(self: Cartesian, i: usize, w: usize, n: usize) f32 {
        return switch (self.kind) {
            .bar => (float(i) + 0.5) * float(w) / float(n),
            else => if (n == 1) float(w) / 2.0 else float(i) * float(w -| 1) / float(n - 1),
        };
    }

    pub fn indexAt(self: Cartesian, x: f32, w: usize) ?usize {
        const n = self.len();
        if (n == 0 or w == 0) return null;
        const i = switch (self.kind) {
            .bar => @floor(x / float(w) * float(n)),
            else => @round(x / float(@max(w, 2) - 1) * float(n - 1)),
        };
        return @min(fmath.saturatingInt(usize, i), n - 1);
    }

    pub fn render(self: Cartesian, gpa: Allocator, w: usize, h: usize) Allocator.Error!PixelGrid {
        var g = try PixelGrid.init(gpa, w, h);
        errdefer g.deinit(gpa);
        if (w < 2 or h < 2) return g;
        var s = if (self.grid_lines)
            try self.scale(gpa)
        else
            Scale{ .max = niceBounds(self.dataMax(), self.tick_count).max, .ticks = &.{} };
        defer if (self.grid_lines) s.deinit(gpa);
        const width: i32 = @intCast(w - 1);
        const bottom: i32 = @intCast(h - 1);
        const guide_color = guide();
        for (s.ticks[@min(s.ticks.len, 1)..]) |tick| {
            const y = pixel(@round(s.y(tick, h)));
            line(&g, .{ .x = 0, .y = y }, .{ .x = width, .y = y }, guide_color, 3);
        }
        line(&g, .{ .x = 0, .y = bottom }, .{ .x = width, .y = bottom }, guide_color, 2);
        switch (self.kind) {
            .area, .line => try self.renderCurves(gpa, &g, s),
            .bar => self.renderBars(&g, s),
        }
        try g.bloom(gpa, self.bloom);
        if (self.kind != .bar) self.renderHover(&g, s);
        return g;
    }

    fn renderCurves(self: Cartesian, gpa: Allocator, g: *PixelGrid, scale_: Scale) Allocator.Error!void {
        const w = g.width;
        const h = g.height;
        const n = self.len();
        const progress = fmath.clamp(self.progress, 0, 1);
        const reveal = progress * float(w);
        const grow = 0.6 + 0.4 * @as(f64, progress);
        const columns = if (reveal < float(w)) @min(w, fmath.saturatingInt(usize, @floor(reveal)) +| 1) else w;
        // Store only the visible columns for each visible series. Bodies are
        // drawn first so another series cannot obscure a stroke.
        var visible: usize = 0;
        for (self.series) |s| visible += @intFromBool(!s.hidden);
        const Column = struct { top: f32, bottom: f32 };
        const geometry = try gpa.alloc(Column, std.math.mul(usize, visible, columns) catch return error.OutOfMemory);
        defer gpa.free(geometry);
        for (0..columns) |x| {
            const index = if (n > 1) float(x) / float(w - 1) * float(n - 1) else 0.0;
            var base: f64 = 0;
            var slot: usize = 0;
            for (self.series) |s| {
                if (s.hidden) continue;
                const v = interpolate(s.values, index) * grow;
                geometry[slot * columns + x] = .{ .top = scale_.y(base + v, h), .bottom = scale_.y(base, h) };
                slot += 1;
                if (self.stacked) base += v;
            }
        }
        const body_strength: f32 = if (self.kind == .area) 1 else 0.28;
        var slot: usize = 0;
        for (self.series, 0..) |s, si| {
            if (s.hidden) continue;
            const alpha = alphaFor(self.selected, si);
            for (geometry[slot * columns ..][0..columns], 0..) |col, x| {
                const xi: i32 = @intCast(x);
                const span = @max(float(h - 1) - col.top, 1.0);
                const end = pixel(col.bottom);
                var y = pixel(@ceil(col.top)) +| 1;
                while (y <= end) : (y += 1) {
                    const t = 1.0 - (float(y) - col.top) / span;
                    if (s.fill.covers(xi, y, (0.1 + 0.9 * t) * body_strength)) {
                        g.set(xi, y, s.tone.shade(0.32 + 0.4 * t).fade(alpha));
                    }
                }
            }
            slot += 1;
        }
        slot = 0;
        for (self.series, 0..) |s, si| {
            if (s.hidden) continue;
            const stroke = s.tone.shade(0.78).fade(alphaFor(self.selected, si));
            var prev: ?i32 = null;
            for (geometry[slot * columns ..][0..columns], 0..) |col, x| {
                const ty = pixel(@round(col.top));
                const from = prev orelse ty;
                var y = @min(from, ty);
                while (y <= @max(from, ty)) : (y += 1) g.set(@intCast(x), y, stroke);
                prev = ty;
            }
            slot += 1;
        }
        if (self.kind == .line and w / @max(1, n) >= 6) {
            for (self.series, 0..) |s, si| {
                if (s.hidden) continue;
                const c = s.tone.shade(0.78).fade(alphaFor(self.selected, si));
                for (s.values, 0..) |v, i| {
                    const x = self.columnAt(i, w, @max(1, n));
                    if (x > reveal) break;
                    const base = if (self.stacked) self.stackBelow(si, i) else 0;
                    const y = scale_.y((base + v) * grow, h);
                    dot(g, .{ .x = pixel(@round(x)), .y = pixel(@round(y)) }, c, c);
                }
            }
        }
    }

    fn stackBelow(self: Cartesian, series: usize, i: usize) f64 {
        var base: f64 = 0;
        for (self.series[0..series]) |s| {
            if (!s.hidden) base += valueAt(s.values, i);
        }
        return base;
    }

    fn renderHover(self: Cartesian, g: *PixelGrid, scale_: Scale) void {
        const i = self.hover orelse return;
        const n = self.len();
        if (i >= n) return;
        const x = pixel(@round(self.columnAt(i, g.width, n)));
        const c = @as(Tone, .grey).shade(0.75).fade(0.7);
        line(g, .{ .x = x, .y = 0 }, .{ .x = x, .y = @intCast(g.height - 1) }, c, 2);
        for (self.series, 0..) |s, si| {
            if (s.hidden or i >= s.values.len) continue;
            const base = if (self.stacked) self.stackBelow(si, i) else 0;
            const y = pixel(@round(scale_.y(base + s.values[i], g.height)));
            dot(g, .{ .x = x, .y = y }, s.tone.shade(0.7), s.tone.shade(0.98));
        }
    }

    fn renderBars(self: Cartesian, g: *PixelGrid, scale_: Scale) void {
        const n = self.len();
        if (n == 0) return;
        var visible: usize = 0;
        for (self.series) |s| visible += @intFromBool(!s.hidden);
        const k = if (self.stacked) 1 else @max(visible, 1);
        const band = float(g.width) / float(n);
        const group = @max(band * 0.72, 1.0);
        const gap: f32 = if (group / float(k) > 3.0) 1 else 0;
        const bar_w = @max((group - gap * (float(k) - 1.0)) / float(k), 1.0);
        const progress: f64 = fmath.clamp(self.progress, 0, 1);
        for (0..n) |i| {
            const x0 = float(i) * band + (band - group) / 2.0;
            const band_alpha: f32 = if (self.hover != null and self.hover.? != i) 0.45 else 1.0;
            var base: f64 = 0;
            var slot: usize = 0;
            for (self.series, 0..) |s, si| {
                if (s.hidden) continue;
                const v = valueAt(s.values, i) * progress;
                const left = if (self.stacked) x0 else x0 + float(slot) * (bar_w + gap);
                slot += 1;
                const bx0 = pixel(@round(left));
                const bx1 = @max(bx0, pixel(@round(left + bar_w)) -| 1);
                const top = scale_.y(base + v, g.height);
                const bottom = pixel(scale_.y(base, g.height));
                const alpha = alphaFor(self.selected, si) * band_alpha;
                const ty = pixel(@round(top));
                const span = @max(float(g.height - 1) - top, 1.0);
                var y = ty;
                while (y <= bottom) : (y += 1) {
                    const t = 1.0 - (float(y) - top) / span;
                    const level = if (y == ty) 0.82 else 0.32 + 0.38 * t;
                    const c = s.tone.shade(level).fade(alpha);
                    var x = bx0;
                    while (x <= bx1) : (x += 1) {
                        if (y == ty or s.fill.covers(x, y, 0.3 + 0.7 * t)) g.set(x, y, c);
                    }
                }
                if (self.stacked) base += v;
            }
        }
    }
};

pub fn sparkline(gpa: Allocator, values: []const f64, tone: Tone, w: usize, h: usize, hovered: bool, progress: f32) Allocator.Error!PixelGrid {
    var lo = std.math.inf(f64);
    var hi: f64 = 0;
    for (values) |v| {
        lo = @min(lo, v);
        hi = @max(hi, v);
    }
    const chart: Cartesian = .{
        .series = &.{.{ .tone = tone, .values = values }},
        .grid_lines = false,
        .progress = progress,
        .bloom = if (hovered) .low else .off,
        .y_max = @max(hi * 1.1, lo + 1e-9),
    };
    const g = try chart.render(gpa, w, h);
    if (h != 0) {
        const c = guide();
        for (g.cells[(h - 1) * w ..]) |*cell| {
            if (cell.*) |p| {
                if (p.eql(c)) cell.* = null;
            }
        }
    }
    return g;
}

pub const Slice = struct {
    label: []const u8 = "",
    value: f64,
    tone: Tone,
    fill: Fill = .gradient,
};

pub const PieGeometry = struct {
    center: Point,
    radius: f32,
    inner: f32,
    angles: []const Angle,

    pub const Angle = struct { start: f32, end: f32 };

    pub fn deinit(self: *PieGeometry, gpa: Allocator) void {
        gpa.free(self.angles);
        self.* = undefined;
    }

    pub fn indexAt(self: PieGeometry, x: f32, y: f32) ?usize {
        const dx = x - self.center.x;
        const dy = y - self.center.y;
        const r = @sqrt(dx * dx + dy * dy);
        if (r < self.inner or r > self.radius + 2.0) return null;
        return self.sliceAt(clockwiseAngle(dx, dy));
    }

    fn sliceAt(self: PieGeometry, a: f32) ?usize {
        for (self.angles, 0..) |arc, i| {
            if (a >= arc.start and a < arc.end) return i;
        }
        return null;
    }
};

const tau: f32 = 2.0 * std.math.pi;

fn clockwiseAngle(dx: f32, dy: f32) f32 {
    const angle = fmath.atan2f(dx, -dy);
    return if (angle < 0) angle + tau else angle;
}

pub const Pie = struct {
    slices: []const Slice,
    inner_radius: f32 = 0,
    progress: f32 = 1,
    hover: ?usize = null,
    bloom: Bloom = .off,

    pub fn geometry(self: Pie, gpa: Allocator, w: usize, h: usize) Allocator.Error!PieGeometry {
        var total: f64 = 0;
        for (self.slices) |s| total += @max(s.value, 0.0);
        const sweep = tau * fmath.clamp(self.progress, 0, 1);
        const angles = try gpa.alloc(PieGeometry.Angle, self.slices.len);
        var acc: f32 = 0;
        for (angles, self.slices) |*arc, s| {
            const a = if (total > 0) @as(f32, @floatCast(@max(s.value, 0.0) / total)) * sweep else 0.0;
            arc.* = .{ .start = acc, .end = acc + a };
            acc += a;
        }
        const radius = @max(float(@min(w, h)) / 2.0 - 2.5, 1.0);
        return .{
            .center = .{ .x = float(w) / 2.0, .y = float(h) / 2.0 },
            .radius = radius,
            .inner = radius * fmath.clamp(self.inner_radius, 0, 0.95),
            .angles = angles,
        };
    }

    pub fn render(self: Pie, gpa: Allocator, w: usize, h: usize) Allocator.Error!PixelGrid {
        var g = try PixelGrid.init(gpa, w, h);
        errdefer g.deinit(gpa);
        var geo = try self.geometry(gpa, w, h);
        defer geo.deinit(gpa);
        const multi = self.slices.len > 1;
        const max_outer = geo.radius - (if (self.hover == null) @as(f32, 2.0) else 0.0);
        for (0..h) |y| {
            const dy = float(y) + 0.5 - geo.center.y;
            for (g.cells[y * w ..][0..w], 0..) |*cell, x| {
                const dx = float(x) + 0.5 - geo.center.x;
                const r = @sqrt(dx * dx + dy * dy);
                if (r < geo.inner or r > max_outer) continue;
                const a = clockwiseAngle(dx, dy);
                const i = geo.sliceAt(a) orelse continue;
                const outer = geo.radius - 2.0 + (if (self.hover == i) @as(f32, 2.0) else 0.0);
                if (r > outer) continue;
                const arc = geo.angles[i];
                if (multi and @min(a - arc.start, arc.end - a) * r < 0.9) continue;
                const s = self.slices[i];
                const dim: f32 = if (self.hover != null and self.hover.? != i) 0.5 else 1.0;
                const t = fmath.clamp((r - geo.inner) / @max(outer - geo.inner, 1.0), 0, 1);
                const rim = outer - r < 1.2;
                if (rim or s.fill.covers(@intCast(x), @intCast(y), 0.3 + 0.7 * t)) {
                    cell.* = s.tone.shade(if (rim) 0.8 else 0.3 + 0.4 * t).fade(dim);
                }
            }
        }
        try g.bloom(gpa, self.bloom);
        return g;
    }
};

pub const RadarGeometry = struct {
    center: Point,
    radius: f32,
    axis_tips: []const Point,

    pub fn deinit(self: *RadarGeometry, gpa: Allocator) void {
        gpa.free(self.axis_tips);
        self.* = undefined;
    }

    fn along(self: RadarGeometry, i: usize, fraction: f32) Point {
        const tip = self.axis_tips[i % self.axis_tips.len];
        return .{
            .x = self.center.x + (tip.x - self.center.x) * fraction,
            .y = self.center.y + (tip.y - self.center.y) * fraction,
        };
    }
};

fn roundPoint(p: Point) Pixel {
    return .{ .x = pixel(@round(p.x)), .y = pixel(@round(p.y)) };
}

pub const Radar = struct {
    series: []const Series,
    max: ?f64 = null,
    progress: f32 = 1,
    selected: ?usize = null,
    rings: usize = 4,
    bloom: Bloom = .off,

    pub fn geometry(self: Radar, gpa: Allocator, w: usize, h: usize) Allocator.Error!RadarGeometry {
        const n = @max(maxLen(self.series), 1);
        const center: Point = .{ .x = float(w) / 2.0, .y = float(h) / 2.0 };
        const radius = @max(float(@min(w, h)) / 2.0 - 2.0, 1.0);
        const tips = try gpa.alloc(Point, n);
        for (tips, 0..) |*tip, i| {
            const a = -@as(f32, std.math.pi / 2.0) + tau * float(i) / float(n);
            tip.* = .{
                .x = center.x + fmath.cosf(a) * radius,
                .y = center.y + fmath.sinf(a) * radius,
            };
        }
        return .{ .center = center, .radius = radius, .axis_tips = tips };
    }

    pub fn render(self: Radar, gpa: Allocator, w: usize, h: usize) Allocator.Error!PixelGrid {
        var g = try PixelGrid.init(gpa, w, h);
        errdefer g.deinit(gpa);
        const n = maxLen(self.series);
        if (n < 3 or g.isEmpty()) return g;
        var geo = try self.geometry(gpa, w, h);
        defer geo.deinit(gpa);
        const points = try gpa.alloc(Point, n);
        defer gpa.free(points);
        const crossings = try gpa.alloc(f32, n);
        defer gpa.free(crossings);

        const c = guide();
        const center = roundPoint(geo.center);
        const rings = @max(self.rings, 1);
        for (0..rings) |ring| {
            const f = float(ring + 1) / float(rings);
            for (0..n) |i| line(&g, roundPoint(geo.along(i, f)), roundPoint(geo.along(i + 1, f)), c, 2);
        }
        for (0..n) |i| line(&g, center, roundPoint(geo.along(i, 1.0)), c, 3);

        const max = self.max orelse blk: {
            var hi: f64 = 0;
            for (self.series) |s| {
                for (s.values) |v| hi = @max(hi, v);
            }
            break :blk niceBounds(hi, self.rings).max;
        };
        const p = fmath.clamp(self.progress, 0, 1);
        for (self.series, 0..) |s, si| {
            if (s.hidden) continue;
            const alpha = alphaFor(self.selected, si);
            for (points, 0..) |*point, i| {
                const f: f32 = @floatCast(fmath.clamp(valueAt(s.values, i) / max, 0, 1));
                point.* = geo.along(i, f * p);
            }
            fillPolygon(&g, geo, points, crossings, s, alpha);
            const stroke = s.tone.shade(0.8).fade(alpha);
            for (points, 0..) |point, i| {
                line(&g, roundPoint(point), roundPoint(points[(i + 1) % n]), stroke, 1);
            }
            const marker = s.tone.shade(0.97).fade(alpha);
            for (points) |point| dot(&g, roundPoint(point), stroke, marker);
        }
        try g.bloom(gpa, self.bloom);
        return g;
    }

    fn fillPolygon(g: *PixelGrid, geo: RadarGeometry, points: []const Point, crossings: []f32, s: Series, alpha: f32) void {
        for (0..g.height) |y| {
            const py = float(y) + 0.5;
            var count: usize = 0;
            var prev = points[points.len - 1];
            // Calculate each edge crossing once per row. Pair the sorted
            // crossings using the upstream even-odd rule at pixel centres.
            for (points) |point| {
                if ((point.y > py) != (prev.y > py)) {
                    const x = (prev.x - point.x) * (py - point.y) / (prev.y - point.y) + point.x;
                    if (!std.math.isNan(x)) {
                        crossings[count] = x;
                        count += 1;
                    }
                }
                prev = point;
            }
            const sorted = crossings[0..count];
            std.mem.sort(f32, sorted, {}, std.sort.asc(f32));
            var start: usize = 0;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const end = @min(g.width, fmath.saturatingInt(usize, @ceil(@as(f64, sorted[i]) - 0.5)));
                if ((count - i) % 2 != 0) {
                    for (start..end) |x| {
                        const dx = float(x) + 0.5 - geo.center.x;
                        const dy = py - geo.center.y;
                        const d = @sqrt(dx * dx + dy * dy) / geo.radius;
                        if (s.fill.covers(@intCast(x), @intCast(y), 0.2 + 0.55 * d)) {
                            g.cells[y * g.width + x] = s.tone.shade(0.32 + 0.35 * d).fade(alpha);
                        }
                    }
                }
                start = end;
            }
        }
    }
};

test "scale and compact values" {
    const gpa = std.testing.allocator;
    var s = try Scale.nice(gpa, 87.0, 4);
    defer s.deinit(gpa);
    try std.testing.expectEqual(100.0, s.max);
    try std.testing.expectEqualSlices(f64, &.{ 0, 25, 50, 75, 100 }, s.ticks);
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("950", try formatValue(&buf, 950));
    try std.testing.expectEqualStrings("1.2k", try formatValue(&buf, 1200));
    try std.testing.expectEqualStrings("3M", try formatValue(&buf, 3_000_000));
}

test "interpolation and cartesian hit testing" {
    const values = [_]f64{ 0, 10, 0, 5 };
    for (values, 0..) |v, i| try std.testing.expectEqual(v, interpolate(&values, float(i)));
    for (0..30) |i| {
        const y = interpolate(&values, float(i) / 10.0);
        try std.testing.expect(y >= 0 and y <= 10);
    }
    for ([_]CartesianKind{ .area, .bar }) |kind| {
        const c: Cartesian = .{ .kind = kind, .series = &.{.{ .tone = .blue, .values = &values }} };
        for (0..values.len) |i| try std.testing.expectEqual(i, c.indexAt(c.columnX(i, 120), 120).?);
    }
}
