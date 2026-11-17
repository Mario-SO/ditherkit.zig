//! Composable terminal cells and half-block raster painting.

const std = @import("std");
const dk = @import("ditherkit");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Rgba = dk.Rgba;

pub const Rect = struct {
    x: usize = 0,
    y: usize = 0,
    width: usize,
    height: usize,

    pub fn contains(self: Rect, col: usize, row: usize) bool {
        return col >= self.x and col - self.x < self.width and
            row >= self.y and row - self.y < self.height;
    }
};

pub const Style = struct {
    foreground: Rgba,
    bold: bool = false,
    underline: bool = false,
    crossed_out: bool = false,
};

pub const Cell = struct {
    glyph: u21 = ' ',
    style: Style = .{ .foreground = .white },
    background: ?Rgba = null,
};

pub const Buffer = struct {
    area: Rect,
    cells: []Cell,

    pub fn init(gpa: Allocator, cols: usize, rows: usize) Allocator.Error!Buffer {
        const count = std.math.mul(usize, cols, rows) catch return error.OutOfMemory;
        const cells = try gpa.alloc(Cell, count);
        @memset(cells, .{});
        return .{ .area = .{ .width = cols, .height = rows }, .cells = cells };
    }

    pub fn deinit(self: *Buffer, gpa: Allocator) void {
        gpa.free(self.cells);
        self.* = undefined;
    }

    fn cellAt(self: Buffer, col: usize, row: usize) ?*Cell {
        if (!self.area.contains(col, row)) return null;
        return &self.cells[row * self.area.width + col];
    }

    pub fn get(self: Buffer, col: usize, row: usize) ?Cell {
        return if (self.cellAt(col, row)) |cell| cell.* else null;
    }

    pub fn fill(self: Buffer, rect: Rect, background: Rgba) void {
        for (rect.y..@max(rect.y, @min(rect.y +| rect.height, self.area.height))) |y| {
            for (rect.x..@max(rect.x, @min(rect.x +| rect.width, self.area.width))) |x| {
                self.cellAt(x, y).?.* = .{ .background = background };
            }
        }
    }

    /// Writes single-column Unicode glyphs, clipped to the given width.
    /// Control characters are replaced with spaces.
    pub fn text(self: Buffer, x: usize, y: usize, width: usize, label: []const u8, style: Style) void {
        const view = std.unicode.Utf8View.init(label) catch return;
        var it = view.iterator();
        var i: usize = 0;
        while (i < width) : (i += 1) {
            const glyph = it.nextCodepoint() orelse break;
            const cell = self.cellAt(x +| i, y) orelse break;
            cell.glyph = if (glyph < 32 or (glyph >= 127 and glyph < 160)) ' ' else glyph;
            cell.style = style;
        }
    }

    pub fn raster(self: Buffer, rect: Rect, pixels: dk.PixelGrid, fallback: Rgba) void {
        self.rasterScaled(rect, pixels, 1, fallback);
    }

    pub fn rasterScaled(self: Buffer, rect: Rect, pixels: dk.PixelGrid, scale: usize, fallback: Rgba) void {
        const zoom = @max(scale, 1);
        const rows = @min(rect.height, @min((pixels.height *| zoom +| 1) / 2, self.area.height -| rect.y));
        const cols = @min(rect.width, @min(pixels.width *| zoom, self.area.width -| rect.x));
        for (0..rows) |y| {
            for (0..cols) |x| {
                const top = pixels.get(x / zoom, y * 2 / zoom);
                const bottom = pixels.get(x / zoom, (y * 2 + 1) / zoom);
                if (top == null and bottom == null) continue;
                const cell = self.cellAt(rect.x + x, rect.y + y).?;
                const bg = cell.background orelse fallback;
                cell.* = .{
                    .glyph = '▀',
                    .style = .{ .foreground = (top orelse Rgba.transparent).over(bg) },
                    .background = (bottom orelse Rgba.transparent).over(bg),
                };
            }
        }
    }

    /// Writes the buffer as truecolor ANSI. Caller flushes the writer.
    pub fn write(self: Buffer, writer: *Writer, fallback: Rgba) Writer.Error!void {
        for (0..self.area.height) |y| {
            for (self.cells[y * self.area.width ..][0..self.area.width]) |cell| {
                try emit(writer, cell.glyph, cell.style, cell.background orelse fallback);
            }
            try writer.writeAll("\x1b[0m\n");
        }
    }
};

pub fn emit(w: *Writer, glyph: u21, style: Style, bg: Rgba) Writer.Error!void {
    const fg = style.foreground;
    try w.print("\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b, bg.r, bg.g, bg.b });
    if (style.bold) try w.writeAll("\x1b[1m");
    if (style.underline) try w.writeAll("\x1b[4m");
    if (style.crossed_out) try w.writeAll("\x1b[9m");
    var utf8: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(glyph, &utf8) catch unreachable;
    try w.writeAll(utf8[0..n]);
    if (style.bold or style.underline or style.crossed_out) try w.writeAll("\x1b[0m");
}

pub fn textWidth(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch 0;
}
