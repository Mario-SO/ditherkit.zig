//! Draws truecolor terminal swatches or a gallery of widgets.
//! zig build term -- --gallery

const std = @import("std");
const dk = @import("ditherkit");
const term = @import("ditherkit_term");
const swatches = @import("swatches.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var buf: [4096]u8 = undefined;
    var fw: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &fw.interface;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--gallery")) {
        var frame = try gallery(init.gpa);
        defer frame.deinit(init.gpa);
        try frame.write(w, term.Theme.dark.background);
    } else {
        var grid = try swatches.render(init.gpa);
        defer grid.deinit(init.gpa);
        try term.paint(w, grid, term.Theme.dark.background);
        try w.print("tones ↓  matrices → {s}\n", .{"bayer2 · bayer4 · bayer8 · halftone · noise"});
    }
    try w.flush();
}

fn gallery(gpa: std.mem.Allocator) !term.Buffer {
    var frame = try term.Buffer.init(gpa, 76, 24);
    errdefer frame.deinit(gpa);
    const series = [_]dk.Series{
        .{ .label = "Desktop", .tone = .blue, .values = &.{ 186, 305, 237, 173, 209, 214, 280 } },
        .{ .label = "Mobile", .tone = .pink, .values = &.{ 80, 200, 120, 190, 130, 140, 160 }, .fill = .hatched },
    };
    const chart: term.Chart = .{
        .spec = .{ .series = &series, .hover = 3, .bloom = .low },
        .labels = &.{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
    };
    try chart.render(gpa, frame, .{ .width = 47, .height = 14 });
    const pie: term.PieChart = .{ .spec = .{
        .slices = &.{
            .{ .label = "Chrome", .tone = .blue, .value = 275 },
            .{ .label = "Safari", .tone = .pink, .value = 200 },
            .{ .label = "Other", .tone = .green, .value = 125 },
        },
        .inner_radius = 0.55,
    } };
    try pie.render(gpa, frame, .{ .x = 49, .width = 27, .height = 15 });

    const button: term.Button = .{ .label = "Continue", .tone = .green, .state = .{ .focused = true } };
    try button.render(gpa, frame, .{ .x = 2, .y = 16, .width = 22, .height = 3 });
    const avatar: term.Avatar = .{ .name = "Ada Lovelace" };
    try avatar.render(gpa, frame, .{ .x = 27, .y = 16, .width = 8, .height = 4 });
    const meter: term.Meter = .{ .tone = .orange, .value = 0.72 };
    try meter.render(gpa, frame, .{ .x = 2, .y = 21, .width = 33, .height = 2 });
    const spark: term.Sparkline = .{ .tone = .purple, .values = &.{ 3, 5, 2, 7, 6, 9 }, .hovered = true };
    try spark.render(gpa, frame, .{ .x = 38, .y = 16, .width = 36, .height = 7 });
    return frame;
}
