//! Pixel parity against upstream Rust `dither-core`.
//!
//! Each scene in `scenes.zig` is rendered and compared byte for byte with the
//! grid the Rust twin wrote to `golden/`. Regenerate the goldens with
//! `zig build golden` (needs cargo) after bumping the pinned upstream rev.

const std = @import("std");
const dk = @import("ditherkit");
const scenes = @import("scenes");

const Scene = struct {
    name: []const u8,
    golden: []const u8,
    render: *const fn (std.mem.Allocator) anyerror!dk.PixelGrid,
};

const all = [_]Scene{
    .{ .name = "shades", .golden = @embedFile("golden/shades.grid"), .render = scenes.shades },
    .{ .name = "matrices", .golden = @embedFile("golden/matrices.grid"), .render = scenes.matrices },
    .{ .name = "fills", .golden = @embedFile("golden/fills.grid"), .render = scenes.fills },
    .{ .name = "bloom", .golden = @embedFile("golden/bloom.grid"), .render = scenes.bloom },
    .{ .name = "sparkle", .golden = @embedFile("golden/sparkle.grid"), .render = scenes.sparkle },
};

const header_len = 12;
const pixel_len = 5;

fn decode(bytes: []const u8, i: usize) ?dk.Rgba {
    const p = bytes[header_len + i * pixel_len ..][0..pixel_len];
    return if (p[0] == 0) null else .{ .r = p[1], .g = p[2], .b = p[3], .a = p[4] };
}

fn eqlPixel(a: ?dk.Rgba, b: ?dk.Rgba) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.?.eql(b.?);
}

fn expectParity(scene: Scene) !void {
    const gpa = std.testing.allocator;
    var g = try scene.render(gpa);
    defer g.deinit(gpa);

    const golden = scene.golden;
    try std.testing.expectEqualSlices(u8, "DKG1", golden[0..4]);
    const w = std.mem.readInt(u32, golden[4..8], .little);
    const h = std.mem.readInt(u32, golden[8..12], .little);
    try std.testing.expectEqual(w, g.width);
    try std.testing.expectEqual(h, g.height);

    var mismatches: usize = 0;
    for (g.cells, 0..) |got, i| {
        const want = decode(golden, i);
        if (eqlPixel(got, want)) continue;
        if (mismatches < 5) std.debug.print("{s}: ({d},{d}) zig={any} rust={any}\n", .{ scene.name, i % w, i / w, got, want });
        mismatches += 1;
    }
    if (mismatches > 0) {
        std.debug.print("{s}: {d}/{d} pixels differ from Rust\n", .{ scene.name, mismatches, g.cells.len });
        return error.PixelMismatch;
    }
}

test "shades match Rust" {
    try expectParity(all[0]);
}
test "matrices match Rust" {
    try expectParity(all[1]);
}
test "fills match Rust" {
    try expectParity(all[2]);
}
test "bloom matches Rust" {
    try expectParity(all[3]);
}
test "sparkle matches Rust" {
    try expectParity(all[4]);
}
