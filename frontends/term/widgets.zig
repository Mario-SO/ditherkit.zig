//! Terminal surfaces and legend, drawn into the shared cell buffer.

const std = @import("std");
const dk = @import("ditherkit");
const cells = @import("buffer.zig");
const Buffer = cells.Buffer;
const Rect = cells.Rect;
const Theme = @import("theme.zig").Theme;
const Allocator = std.mem.Allocator;

pub const Gradient = struct {
    spec: dk.Gradient,
    theme: Theme = .dark,

    pub fn render(self: Gradient, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        var pixels = try self.spec.render(gpa, area.width, area.height *| 2);
        defer pixels.deinit(gpa);
        buf.raster(area, pixels, self.theme.background);
    }
};

pub const Background = struct {
    spec: dk.Background,
    time: f32 = 0,
    theme: Theme = .dark,

    pub fn render(self: Background, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        var pixels = try self.spec.render(gpa, area.width, area.height *| 2, self.time);
        defer pixels.deinit(gpa);
        buf.raster(area, pixels, self.theme.background);
    }
};

pub const ButtonState = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    animated_density: ?f32 = null,

    pub fn tick(self: *ButtonState, style: dk.ButtonStyle, dt: f32) void {
        const target = style.density(self.hovered or self.focused, self.pressed);
        self.animated_density = dk.ease.approach(self.animated_density orelse target, target, dt, 0.08);
    }

    pub fn density(self: ButtonState, style: dk.ButtonStyle) f32 {
        return self.animated_density orelse style.density(self.hovered or self.focused, self.pressed);
    }

    pub fn hit(area: Rect, col: usize, row: usize) bool {
        return area.contains(col, row);
    }
};

pub const Button = struct {
    label: []const u8,
    tone: dk.Tone,
    style: dk.ButtonStyle = .solid,
    state: ButtonState = .{},
    time: f32 = 0,
    disabled: bool = false,
    theme: Theme = .dark,

    pub fn render(self: Button, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        if (area.width == 0 or area.height == 0) return;
        const tone: dk.Tone = if (self.disabled) .grey else self.tone;
        const density = if (self.disabled) 0.15 else self.state.density(self.style);
        var pixels = try dk.buttonTexture(gpa, area.width, area.height *| 2, tone, self.style, density, self.time);
        defer pixels.deinit(gpa);
        if (self.style.surface(tone)) |surface| buf.fill(area, surface);
        const label_w = cells.textWidth(self.label) +| 2;
        const lx = (area.width -| label_w) / 2;
        const ly = area.height / 2;
        const end = @min(area.width, lx +| label_w);
        for (ly * 2..ly * 2 + 2) |y| @memset(pixels.cells[y * area.width + lx .. y * area.width + end], null);
        buf.raster(area, pixels, self.theme.background);
        buf.text(area.x +| lx +| 1, area.y +| ly, area.width -| (lx + 1), self.label, .{
            .foreground = if (self.disabled) self.theme.muted else self.theme.foreground,
            .bold = true,
            .underline = self.state.focused and !self.disabled,
        });
    }
};

pub const Avatar = struct {
    name: []const u8,
    hue: ?f32 = null,
    scale: usize = 1,
    theme: Theme = .dark,

    pub fn size(self: Avatar) struct { usize, usize } {
        const scale = @max(self.scale, 1);
        return .{ 8 *| scale, 4 *| scale };
    }

    pub fn render(self: Avatar, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        var pixels = try dk.avatar(gpa, self.name, self.hue);
        defer pixels.deinit(gpa);
        buf.rasterScaled(area, pixels, self.scale, self.theme.background);
    }
};

pub const Meter = struct {
    value: f32,
    tone: dk.Tone,
    fill: dk.Fill = .gradient,
    theme: Theme = .dark,

    pub fn render(self: Meter, gpa: Allocator, buf: Buffer, area: Rect) Allocator.Error!void {
        var pixels = try dk.meter(gpa, area.width, area.height *| 2, self.value, self.tone, self.fill);
        defer pixels.deinit(gpa);
        buf.raster(area, pixels, self.theme.background);
    }
};

pub const LegendItem = struct {
    label: []const u8,
    tone: dk.Tone,
    hidden: bool = false,
    selected: bool = false,
};

pub const Legend = struct {
    items: []const LegendItem,
    theme: Theme = .dark,
    centered: bool = false,

    pub fn layout(self: Legend, area: Rect) Layout {
        var width: usize = self.items.len -| 1;
        for (self.items) |item| width +|= itemWidth(item);
        const inset = if (self.centered) (area.width -| width) / 2 else 0;
        return .{ .items = self.items, .area = area, .offset = inset };
    }

    fn itemWidth(item: LegendItem) usize {
        return cells.textWidth(item.label) +| 4;
    }

    pub const Layout = struct {
        items: []const LegendItem,
        area: Rect,
        offset: usize,
        index: usize = 0,

        pub fn next(self: *Layout) ?Rect {
            if (self.index == self.items.len or self.offset >= self.area.width or self.area.height == 0) return null;
            const width = itemWidth(self.items[self.index]);
            const rect: Rect = .{
                .x = self.area.x +| self.offset,
                .y = self.area.y,
                .width = @min(width, self.area.width - self.offset),
                .height = 1,
            };
            self.offset +|= width +| 1;
            self.index += 1;
            return rect;
        }
    };

    pub fn hit(self: Legend, area: Rect, col: usize, row: usize) ?usize {
        var iter = self.layout(area);
        while (iter.next()) |rect| if (rect.contains(col, row)) return iter.index - 1;
        return null;
    }

    pub fn render(self: Legend, buf: Buffer, area: Rect) void {
        var iter = self.layout(area);
        while (iter.next()) |rect| {
            if (rect.width < 3) break;
            const item = self.items[iter.index - 1];
            const swatch = if (item.hidden) @as(dk.Tone, .grey).shade(0.35) else item.tone.base();
            buf.text(rect.x, rect.y, 2, "▚▚", .{ .foreground = swatch });
            buf.text(rect.x +| 3, rect.y, rect.width - 3, item.label, .{
                .foreground = if (item.hidden) self.theme.muted else self.theme.foreground,
                .bold = item.selected,
                .crossed_out = item.hidden,
            });
        }
    }
};

pub fn labelColor(tone: dk.Tone) dk.Rgba {
    return if (tone.base().luminance() > 0.45) .black else .white;
}

test "button draws centered native text and legend hit uses its layout" {
    const gpa = std.testing.allocator;
    var buffer = try Buffer.init(gpa, 19, 5);
    defer buffer.deinit(gpa);
    const button: Button = .{ .label = "Run", .tone = .green, .state = .{ .focused = true } };
    try button.render(gpa, buffer, buffer.area);
    try std.testing.expectEqual(@as(u21, 'R'), buffer.get(8, 2).?.glyph);
    try std.testing.expect(buffer.get(8, 2).?.style.underline);
    const legend: Legend = .{ .items = &.{ .{ .label = "One", .tone = .blue }, .{ .label = "Two", .tone = .pink } } };
    try std.testing.expectEqual(@as(?usize, 1), legend.hit(buffer.area, 8, 0));
    try std.testing.expectEqual(@as(?usize, null), legend.hit(buffer.area, 7, 0));
}
