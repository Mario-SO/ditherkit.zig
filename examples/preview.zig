//! Renders a contact sheet to a PPM image (port of
//! `dither-core/examples/preview.rs`). Only covers the surfaces that are
//! ported so far; grows as paint.zig / chart.zig land.
//!
//! `zig build preview -- out.ppm`

const std = @import("std");
const dk = @import("ditherkit");
const swatches = @import("swatches.zig");

const bg = dk.Rgba.hex(0x0b0b0f);
const scale = 4;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len > 1) args[1] else "preview.ppm";

    var grid = try swatches.render(init.gpa);
    defer grid.deinit(init.gpa);

    const w = grid.width * scale;
    const h = grid.height * scale;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(init.gpa);
    try out.print(init.gpa, "P6\n{d} {d}\n255\n", .{ w, h });
    for (0..h) |y| for (0..w) |x| {
        const c = (grid.get(x / scale, y / scale) orelse dk.Rgba.transparent).over(bg);
        try out.appendSlice(init.gpa, &.{ c.r, c.g, c.b });
    };

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = out.items });
    std.debug.print("wrote {s} ({d}x{d})\n", .{ path, w, h });
}
