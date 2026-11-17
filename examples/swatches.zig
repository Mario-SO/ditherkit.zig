//! Shared demo grid: one row per tone, one column per threshold matrix,
//! each cell a left-to-right intensity ramp. Uses only the ported core.

const std = @import("std");
const dk = @import("ditherkit");

pub const cell_w = 28;
pub const cell_h = 8;
pub const gap = 2;

pub fn render(gpa: std.mem.Allocator) !dk.PixelGrid {
    const matrices = std.enums.values(dk.Matrix);
    const cols = matrices.len;
    const rows = dk.Tone.all.len;
    var g = try dk.PixelGrid.init(gpa, cols * (cell_w + gap) + gap, rows * (cell_h + gap) + gap);
    errdefer g.deinit(gpa);

    for (dk.Tone.all, 0..) |tone, row| {
        for (matrices, 0..) |m, col| {
            const ox = gap + col * (cell_w + gap);
            const oy = gap + row * (cell_h + gap);
            for (0..cell_h) |y| for (0..cell_w) |x| {
                const t = @as(f32, @floatFromInt(x)) / (cell_w - 1);
                const px: i32 = @intCast(ox + x);
                const py: i32 = @intCast(oy + y);
                if (m.on(px, py, t)) g.set(px, py, tone.shade(0.3 + 0.6 * t));
            };
        }
    }
    try g.bloom(gpa, .low);
    return g;
}
