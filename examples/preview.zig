//! Renders the upstream dither-core contact sheet as a PPM image.
//! zig build preview -- out.ppm

const std = @import("std");
const dk = @import("ditherkit");

const bg = dk.Rgba.hex(0x0b0b0f);
const scale = 3;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len > 1) args[1] else "preview.ppm";

    var grid = try render(init.gpa);
    defer grid.deinit(init.gpa);

    const w = grid.width * scale;
    const h = grid.height * scale;
    const file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
    defer file.close(init.io);
    var buf: [4096]u8 = undefined;
    var writer = file.writer(init.io, &buf);
    const out = &writer.interface;
    try out.print("P6\n{d} {d}\n255\n", .{ w, h });
    var row: [400 * scale * 3]u8 = undefined;
    for (0..grid.height) |y| {
        for (0..grid.width) |x| {
            const c = (grid.get(x, y) orelse dk.Rgba.transparent).over(bg);
            for (0..scale) |i| row[(x * scale + i) * 3 ..][0..3].* = .{ c.r, c.g, c.b };
        }
        for (0..scale) |_| try out.writeAll(&row);
    }
    try out.flush();
    std.debug.print("wrote {s} ({d}x{d})\n", .{ path, w, h });
}

pub fn render(gpa: std.mem.Allocator) !dk.PixelGrid {
    var sheet: Sheet = .{ .gpa = gpa, .grid = try dk.PixelGrid.init(gpa, 400, 330) };
    errdefer sheet.grid.deinit(gpa);

    var traffic = [_]dk.Series{
        .{ .label = "Desktop", .tone = .blue, .values = &.{ 186, 305, 237, 173, 209, 214, 280, 320, 260, 290, 340, 310 } },
        .{ .label = "Mobile", .tone = .pink, .values = &.{ 80, 200, 120, 190, 130, 140, 160, 150, 210, 180, 220, 260 } },
        .{ .label = "Tablet", .tone = .orange, .values = &.{ 40, 60, 55, 70, 65, 90, 85, 70, 95, 100, 90, 120 } },
    };
    const area: dk.Cartesian = .{ .series = &traffic, .hover = 7, .bloom = .low };
    sheet.put(try area.render(gpa, 250, 90), 6, 6);

    const slices = [_]dk.Slice{
        .{ .label = "Chrome", .value = 275, .tone = .blue },
        .{ .label = "Safari", .value = 200, .tone = .pink },
        .{ .label = "Firefox", .value = 187, .tone = .orange, .fill = .dotted },
        .{ .label = "Edge", .value = 173, .tone = .green },
        .{ .label = "Other", .value = 90, .tone = .grey },
    };
    const pie: dk.Pie = .{ .slices = &slices, .inner_radius = 0.55, .hover = 1 };
    sheet.put(try pie.render(gpa, 96, 96), 290, 3);

    const bars: dk.Cartesian = .{ .kind = .bar, .series = traffic[0..2], .stacked = true, .hover = 4 };
    sheet.put(try bars.render(gpa, 120, 70), 6, 108);

    traffic[1].fill = .hatched;
    const lines: dk.Cartesian = .{ .kind = .line, .series = traffic[0..2] };
    sheet.put(try lines.render(gpa, 120, 70), 134, 108);

    const radar: dk.Radar = .{ .series = &.{
        .{ .label = "Rook", .tone = .purple, .values = &.{ 80, 95, 60, 70, 85, 65 } },
        .{ .label = "Knight", .tone = .green, .values = &.{ 65, 60, 90, 85, 55, 80 } },
    } };
    sheet.put(try radar.render(gpa, 84, 84), 290, 106);

    const buttons = [_]struct { dk.Tone, dk.ButtonStyle, f32 }{
        .{ .green, .solid, 0.32 },
        .{ .green, .solid, 0.85 },
        .{ .blue, .outline, 0.3 },
        .{ .pink, .ghost, 0.5 },
    };
    for (buttons, 0..) |button, i| {
        const tone, const style, const density = button;
        const tile = try dk.buttonTexture(gpa, 56, 14, tone, style, density, 1.3);
        if (style.surface(tone)) |surface| {
            for (tile.cells) |*cell| if (cell.* == null) {
                cell.* = surface;
            };
        }
        sheet.put(tile, @intCast(6 + i * 62), 190);
    }

    for ([_][]const u8{ "Ada Lovelace", "Grace Hopper", "Alan Turing", "Linus", "Margaret H.", "Ken Thompson" }, 0..) |name, i| {
        var icon = try dk.avatar(gpa, name, null);
        defer icon.deinit(gpa);
        const big = try dk.PixelGrid.init(gpa, 24, 24);
        for (big.cells, 0..) |*cell, j| cell.* = icon.get((j % 24) / 3, (j / 24) / 3);
        sheet.put(big, @intCast(256 + (i % 3) * 30), @intCast(186 + (i / 3) * 30));
    }

    for (dk.Fill.all, 0..) |fill, i| {
        const value = 0.35 + 0.18 * @as(f32, @floatFromInt(i));
        sheet.put(try dk.meter(gpa, 120, 4, value, dk.Tone.all[i], fill), @intCast(6 + (i % 2) * 125), @intCast(212 + (i / 2) * 8));
    }

    const gradients = [_]dk.Gradient{
        .{ .from = .blue, .to = .purple },
        .{ .from = .orange, .to = .pink, .direction = .right },
        .{ .from = .green },
        .{ .from = .red, .to = .orange, .direction = .radial, .matrix = .halftone },
    };
    for (gradients, 0..) |gradient, i| {
        sheet.put(try gradient.render(gpa, 46, 90), @intCast(6 + i * 50), 234);
    }
    const background: dk.Background = .{ .field = .aurora, .tone = .green, .accent = .blue, .density = 0.8 };
    sheet.put(try background.render(gpa, 186, 90, 2), 208, 244);
    return sheet.grid;
}

const Sheet = struct {
    gpa: std.mem.Allocator,
    grid: dk.PixelGrid,

    /// Takes ownership of the tile.
    fn put(self: *Sheet, tile: dk.PixelGrid, x: i32, y: i32) void {
        var owned = tile;
        defer owned.deinit(self.gpa);
        self.grid.overlay(owned, x, y);
    }
};
