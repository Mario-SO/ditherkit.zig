//! Chart layout, native labels, and hit testing for ANSI cell buffers.

const std = @import("std");
const dk = @import("ditherkit");
const cells = @import("buffer.zig");
const widgets = @import("widgets.zig");
const Theme = @import("theme.zig").Theme;
const Allocator = std.mem.Allocator;
const Buffer = cells.Buffer;
const Rect = cells.Rect;

pub const Chart = struct {
    spec: dk.Cartesian,
    labels: []const []const u8 = &.{},
    theme: Theme = .dark,
    legend: bool = true,
    y_axis: bool = true,
    tooltip: bool = true,

    pub fn legendArea(self: Chart, area: Rect) ?Rect {
        return if (self.legend and area.height > 3)
            .{ .x = area.x, .y = area.y, .width = area.width, .height = 1 }
        else
            null;
    }

    pub fn plotArea(self: Chart, gpa: Allocator, area: Rect) Allocator.Error!Rect {
        if (!self.y_axis) return self.layout(area, 0);
        var scale = try self.spec.scale(gpa);
        defer scale.deinit(gpa);
        return self.layout(area, axisWidth(scale));
    }

    fn layout(self: Chart, area: Rect, axis_width: usize) Rect {
        var plot = area;
        if (self.legendArea(area) != null) {
            plot.y +|= 2;
            plot.height -= 2;
        }
        if (self.labels.len != 0) plot.height -|= 1;
        plot.x +|= @min(plot.width, axis_width);
        plot.width -|= axis_width;
        return plot;
    }

    fn axisWidth(scale: dk.Scale) usize {
        var width: usize = 1;
        for (scale.ticks) |tick| {
            var scratch: [32]u8 = undefined;
            width = @max(width, valueText(&scratch, tick).len);
        }
        return width + 1;
    }

    pub fn indexAt(self: Chart, gpa: Allocator, area: Rect, col: usize, row: usize) Allocator.Error!?usize {
        const plot = try self.plotArea(gpa, area);
        if (!plot.contains(col, row)) return null;
        return self.spec.indexAt(float(col - plot.x), plot.width);
    }

    pub fn legendHit(self: Chart, gpa: Allocator, area: Rect, col: usize, row: usize) Allocator.Error!?usize {
        const rect = self.legendArea(area) orelse return null;
        if (!rect.contains(col, row)) return null;
        const items = try seriesLegend(gpa, self.spec.series, self.spec.selected);
        defer gpa.free(items);
        const legend: widgets.Legend = .{ .items = items, .centered = true, .theme = self.theme };
        return legend.hit(rect, col, row);
    }

    pub fn render(self: Chart, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        if (area.width < 6 or area.height < 3) return;
        var scale = if (self.y_axis) try self.spec.scale(gpa) else null;
        defer if (scale) |*s| s.deinit(gpa);
        const plot = self.layout(area, if (scale) |s| axisWidth(s) else 0);
        if (self.legendArea(area)) |rect| {
            const items = try seriesLegend(gpa, self.spec.series, self.spec.selected);
            defer gpa.free(items);
            const legend: widgets.Legend = .{ .items = items, .centered = true, .theme = self.theme };
            legend.render(buf, rect);
        }
        if (plot.width == 0 or plot.height == 0) return;
        const height = plot.height *| 2;
        var pixels = try self.spec.render(gpa, plot.width, height);
        defer pixels.deinit(gpa);
        buf.raster(plot, pixels, self.theme.background);

        const muted: cells.Style = .{ .foreground = self.theme.muted };
        if (scale) |s| {
            for (s.ticks) |tick| {
                var scratch: [32]u8 = undefined;
                const label = valueText(&scratch, tick);
                const row = plot.y +| @min(plot.height - 1, coord(@floor(s.y(tick, height) / 2.0)));
                buf.text(plot.x -| (label.len + 1), row, label.len, label, muted);
            }
        }
        const len = self.spec.len();
        var next_free = plot.x;
        const right = plot.x +| plot.width;
        for (self.labels[0..@min(self.labels.len, len)], 0..) |label, i| {
            const cx = float(plot.x) + self.spec.columnX(i, plot.width);
            const width = cells.textWidth(label);
            if (width > plot.width) continue;
            const x = @min(right - width, @max(plot.x, coord(@round(cx - float(width) / 2.0))));
            if (x < next_free) continue;
            const style: cells.Style = if (self.spec.hover == i) .{ .foreground = self.theme.foreground, .bold = true } else muted;
            buf.text(x, plot.y +| plot.height, width, label, style);
            next_free = x +| width +| 1;
        }
        if (self.tooltip) {
            if (self.spec.hover) |i| {
                if (i < len) self.renderTooltip(buf, plot, i);
            }
        }
    }

    fn renderTooltip(self: Chart, buf: Buffer, plot: Rect, index: usize) void {
        const title = if (index < self.labels.len) self.labels[index] else null;
        var count: usize = 0;
        var label_width: usize = 0;
        var value_width: usize = 0;
        for (self.spec.series) |s| {
            if (s.hidden or index >= s.values.len) continue;
            var scratch: [32]u8 = undefined;
            label_width = @max(label_width, cells.textWidth(s.label));
            value_width = @max(value_width, valueText(&scratch, s.values[index]).len);
            count += 1;
        }
        const inner = @max(label_width +| value_width +| 5, if (title) |t| cells.textWidth(t) else 0);
        const w = inner +| 2;
        const h = count +| 2 +| @as(usize, @intFromBool(title != null));
        if (plot.width < w +| 2 or plot.height < h) return;
        const anchor = plot.x +| coord(@round(self.spec.columnX(index, plot.width)));
        const x = if (anchor +| 2 +| w <= plot.x +| plot.width) anchor +| 2 else @max(plot.x, anchor -| (w + 1));
        const rect: Rect = .{ .x = x, .y = plot.y, .width = w, .height = h };
        buf.fill(rect, self.theme.popover);
        const border: cells.Style = .{ .foreground = self.theme.border };
        const bottom = plot.y + h - 1;
        buf.text(x, plot.y, 1, "╭", border);
        buf.text(x, bottom, 1, "╰", border);
        for (1..w - 1) |i| {
            buf.text(x + i, plot.y, 1, "─", border);
            buf.text(x + i, bottom, 1, "─", border);
        }
        buf.text(x + w - 1, plot.y, 1, "╮", border);
        buf.text(x + w - 1, bottom, 1, "╯", border);
        for (plot.y + 1..bottom) |y| {
            buf.text(x, y, 1, "│", border);
            buf.text(x + w - 1, y, 1, "│", border);
        }
        var row = plot.y + 1;
        if (title) |label| {
            buf.text(x + 1, row, inner, label, .{ .foreground = self.theme.foreground, .bold = true });
            row += 1;
        }
        for (self.spec.series) |s| {
            if (s.hidden or index >= s.values.len) continue;
            var scratch: [32]u8 = undefined;
            const value = valueText(&scratch, s.values[index]);
            buf.text(x + 1, row, 1, "■", .{ .foreground = s.tone.base() });
            buf.text(x + 3, row, label_width, s.label, .{ .foreground = self.theme.muted });
            const value_x = x + 4 + label_width + value_width - value.len;
            buf.text(value_x, row, value.len, value, .{ .foreground = self.theme.foreground });
            row += 1;
        }
    }
};

pub const PieChart = struct {
    spec: dk.Pie,
    theme: Theme = .dark,
    legend: bool = true,

    pub fn plotArea(self: PieChart, area: Rect) Rect {
        const h = area.height -| if (self.legend) @as(usize, 2) else 0;
        return square(area, 0, area.width, h);
    }

    pub fn indexAt(self: PieChart, gpa: Allocator, area: Rect, col: usize, row: usize) Allocator.Error!?usize {
        const plot = self.plotArea(area);
        if (!plot.contains(col, row)) return null;
        var geo = try self.spec.geometry(gpa, plot.width, plot.height *| 2);
        defer geo.deinit(gpa);
        return geo.indexAt(float(col - plot.x) + 0.5, 2.0 * float(row - plot.y) + 1.0);
    }

    pub fn render(self: PieChart, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        const plot = self.plotArea(area);
        if (plot.height == 0) return;
        var pixels = try self.spec.render(gpa, plot.width, plot.height *| 2);
        defer pixels.deinit(gpa);
        buf.raster(plot, pixels, self.theme.background);

        if (self.spec.inner_radius >= 0.45 and plot.height >= 2) {
            var label: []const u8 = "Total";
            var value: f64 = 0;
            for (self.spec.slices) |s| value += s.value;
            if (self.spec.hover) |i| {
                if (i < self.spec.slices.len) {
                    label = self.spec.slices[i].label;
                    value = self.spec.slices[i].value;
                }
            }
            const row = plot.y +| plot.height / 2;
            var scratch: [32]u8 = undefined;
            center(buf, plot, row - 1, valueText(&scratch, value), .{ .foreground = self.theme.foreground, .bold = true });
            center(buf, plot, row, label, .{ .foreground = self.theme.muted });
        }
        if (self.legend and area.height -| plot.height >= 2) {
            const items = try gpa.alloc(widgets.LegendItem, self.spec.slices.len);
            defer gpa.free(items);
            for (items, self.spec.slices, 0..) |*item, s, i| {
                item.* = .{ .label = s.label, .tone = s.tone, .selected = self.spec.hover == i };
            }
            const legend: widgets.Legend = .{ .items = items, .centered = true, .theme = self.theme };
            legend.render(buf, .{ .x = area.x, .y = plot.y +| plot.height +| 1, .width = area.width, .height = 1 });
        }
    }
};

pub const RadarChart = struct {
    spec: dk.Radar,
    axes: []const []const u8,
    theme: Theme = .dark,
    legend: bool = true,

    pub fn plotArea(self: RadarChart, area: Rect) Rect {
        var max_label: usize = 0;
        for (self.axes) |label| max_label = @max(max_label, cells.textWidth(label));
        const w = area.width -| ((max_label +| 1) *| 2);
        const h = area.height -| if (self.legend) @as(usize, 4) else 2;
        return square(area, 1, w, h);
    }

    pub fn render(self: RadarChart, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        const plot = self.plotArea(area);
        if (plot.height == 0) return;
        const height = plot.height *| 2;
        var pixels = try self.spec.render(gpa, plot.width, height);
        defer pixels.deinit(gpa);
        buf.raster(plot, pixels, self.theme.background);

        var geo = try self.spec.geometry(gpa, plot.width, height);
        defer geo.deinit(gpa);
        for (self.axes[0..@min(self.axes.len, geo.axis_tips.len)], geo.axis_tips[0..@min(self.axes.len, geo.axis_tips.len)]) |label, tip| {
            const dx = tip.x - geo.center.x;
            const dy = tip.y - geo.center.y;
            const len = float(cells.textWidth(label));
            const offset = if (@abs(dx) < 2) len / 2 else if (dx < 0) len else 0;
            const col = float(plot.x) + tip.x + std.math.copysign(@as(f32, 1.5), dx) - offset;
            const row = float(plot.y) + tip.y / 2 + (if (dy < -2) @as(f32, -1) else if (dy > 2) 0.5 else 0);
            const x = @max(area.x, coord(@round(col)));
            const y = @max(area.y, coord(@round(row)));
            if (area.contains(x, y)) buf.text(x, y, area.x +| area.width -| x, label, .{ .foreground = self.theme.muted });
        }
        if (self.legend) {
            const items = try seriesLegend(gpa, self.spec.series, self.spec.selected);
            defer gpa.free(items);
            const legend: widgets.Legend = .{ .items = items, .centered = true, .theme = self.theme };
            legend.render(buf, .{ .x = area.x, .y = area.y +| (area.height - 1), .width = area.width, .height = 1 });
        }
    }
};

pub const Sparkline = struct {
    values: []const f64,
    tone: dk.Tone,
    hovered: bool = false,
    progress: f32 = 1,
    theme: Theme = .dark,

    pub fn render(self: Sparkline, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        var pixels = try dk.sparkline(gpa, self.values, self.tone, area.width, area.height *| 2, self.hovered, self.progress);
        defer pixels.deinit(gpa);
        buf.raster(area, pixels, self.theme.background);
    }
};

fn seriesLegend(gpa: Allocator, series: []const dk.Series, selected: ?usize) Allocator.Error![]widgets.LegendItem {
    const items = try gpa.alloc(widgets.LegendItem, series.len);
    for (items, series, 0..) |*item, s, i| {
        item.* = .{ .label = s.label, .tone = s.tone, .hidden = s.hidden, .selected = selected == i };
    }
    return items;
}

fn square(area: Rect, top: usize, width: usize, height: usize) Rect {
    const side = @min(width, height *| 2);
    return .{ .x = area.x +| (area.width - side) / 2, .y = area.y +| top, .width = side, .height = side / 2 };
}

fn center(buf: Buffer, area: Rect, row: usize, label: []const u8, style: cells.Style) void {
    const x = (area.width -| cells.textWidth(label)) / 2;
    buf.text(area.x +| x, row, area.width - x, label, style);
}

fn valueText(scratch: []u8, value: f64) []const u8 {
    return dk.formatValue(scratch, value) catch "";
}

fn float(n: usize) f32 {
    return @floatFromInt(n);
}

fn coord(x: f32) usize {
    return dk.fmath.saturatingInt(usize, x);
}

test "cartesian hits the same plot used for rendering" {
    const gpa = std.testing.allocator;
    var buf = try Buffer.init(gpa, 40, 12);
    defer buf.deinit(gpa);
    const chart: Chart = .{
        .spec = .{ .series = &.{.{ .label = "Traffic", .tone = .blue, .values = &.{ 2, 5, 3 } }}, .hover = 0 },
        .labels = &.{ "Mon", "Tue", "Wed" },
    };
    try chart.render(gpa, buf, buf.area);
    const plot = try chart.plotArea(gpa, buf.area);
    try std.testing.expectEqual(@as(?usize, 0), try chart.indexAt(gpa, buf.area, plot.x, plot.y));
    try std.testing.expectEqual(@as(?usize, null), try chart.indexAt(gpa, buf.area, plot.x, 0));
    try std.testing.expectEqual(@as(u21, '╭'), buf.get(plot.x + 2, plot.y).?.glyph);
    try std.testing.expectEqual(@as(?usize, 0), try chart.legendHit(gpa, buf.area, 15, 0));
}
