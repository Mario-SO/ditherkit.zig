//! Truecolor ANSI terminal frontend. Compose widgets in a Buffer or
//! stream an existing PixelGrid as rows of half-block glyphs.

const std = @import("std");
const dk = @import("ditherkit");
const Rgba = dk.Rgba;
const PixelGrid = dk.PixelGrid;
const Writer = std.Io.Writer;

const cells = @import("buffer.zig");
pub const Buffer = cells.Buffer;
pub const Rect = cells.Rect;
pub const Style = cells.Style;
pub const Theme = @import("theme.zig").Theme;
pub const widgets = @import("widgets.zig");
pub const Avatar = widgets.Avatar;
pub const Background = widgets.Background;
pub const Button = widgets.Button;
pub const ButtonState = widgets.ButtonState;
pub const Gradient = widgets.Gradient;
pub const Legend = widgets.Legend;
pub const LegendItem = widgets.LegendItem;
pub const Meter = widgets.Meter;
pub const labelColor = widgets.labelColor;
pub const charts = @import("charts.zig");
pub const Chart = charts.Chart;
pub const PieChart = charts.PieChart;
pub const RadarChart = charts.RadarChart;
pub const Sparkline = charts.Sparkline;

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
            try cells.emit(w, '▀', .{ .foreground = top }, bottom);
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

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(widgets);
    std.testing.refAllDecls(charts);
}
