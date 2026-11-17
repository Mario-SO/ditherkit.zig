//! Draws the swatch grid in a truecolor terminal.
//! `zig build term`

const std = @import("std");
const dk = @import("ditherkit");
const term = @import("ditherkit_term");
const swatches = @import("swatches.zig");

pub fn main(init: std.process.Init) !void {
    var grid = try swatches.render(init.gpa);
    defer grid.deinit(init.gpa);

    var buf: [4096]u8 = undefined;
    var fw: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &fw.interface;
    try term.paint(w, grid, dk.Rgba.hex(0x0b0b0f));
    try w.print("tones ↓  matrices → {s}\n", .{"bayer2 · bayer4 · bayer8 · halftone · noise"});
    try w.flush();
}
