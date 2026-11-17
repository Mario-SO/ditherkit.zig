//! # ditherkit_term
//!
//! Terminal frontend: paints a `PixelGrid` with truecolor ANSI escapes.
//! Stands in for `dither-ratatui` (Zig has no Ratatui), starting with the
//! port of `dither-ratatui/src/raster.rs`.
//!
//! Each terminal cell shows two vertically stacked pixels using the upper
//! half block `▀` (foreground = top pixel, background = bottom pixel). Since
//! a cell is roughly twice as tall as it is wide, pixels come out square.
//!
//! TODO(port): widgets.rs (Button/Avatar/Gradient/Background/Meter/Legend),
//! charts.rs (Chart/PieChart/RadarChart/Sparkline + hit testing), theme.rs.

const std = @import("std");
const dk = @import("ditherkit");
const Rgba = dk.Rgba;
const PixelGrid = dk.PixelGrid;
const Writer = std.Io.Writer;

/// Pixel resolution of a `cols` x `rows` cell area: one pixel per column,
/// two per row.
pub fn pixelSize(cols: usize, rows: usize) struct { usize, usize } {
    return .{ cols, rows * 2 };
}

/// Writes `grid` as rows of half-block cells. Transparent pixels show `bg`;
/// translucent pixels are blended over it. Every row ends with a reset and
/// a newline. Caller flushes `w`.
pub fn paint(w: *Writer, grid: PixelGrid, bg: Rgba) Writer.Error!void {
    var cy: usize = 0;
    while (cy * 2 < grid.height) : (cy += 1) {
        for (0..grid.width) |cx| {
            const top = (grid.get(cx, cy * 2) orelse Rgba.transparent).over(bg);
            const bottom = (grid.get(cx, cy * 2 + 1) orelse Rgba.transparent).over(bg);
            try w.print("\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m▀", .{
                top.r, top.g, top.b, bottom.r, bottom.g, bottom.b,
            });
        }
        try w.writeAll("\x1b[0m\n");
    }
}

test "paint emits one line per two pixel rows" {
    var g = try PixelGrid.init(std.testing.allocator, 3, 4);
    defer g.deinit(std.testing.allocator);
    g.set(0, 0, Rgba.white);

    var buf: [1024]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try paint(&w, g, Rgba.black);
    const out = w.buffered();
    try std.testing.expectEqual(2, std.mem.count(u8, out, "\n"));
    try std.testing.expect(std.mem.startsWith(u8, out, "\x1b[38;2;255;255;255m\x1b[48;2;0;0;0m▀"));
}
