//! # ditherkit
//!
//! Renderer-neutral engine behind ditherkit.zig (a port of `dither-core`
//! from dither-kit-rs): ordered dithering, named tones with perceptual
//! shade ramps, and rasterizers for charts, gradients, backgrounds, buttons,
//! avatars, and meters. Everything draws into a `PixelGrid`; frontends paint it.
//!
//! No dependencies and fully deterministic output, so snapshots and tests are
//! stable. Allocation is explicit: anything that builds a grid takes an
//! `std.mem.Allocator`.

const std = @import("std");

pub const color = @import("color.zig");
pub const dither = @import("dither.zig");
pub const ease = @import("ease.zig");
pub const fmath = @import("fmath.zig");
pub const grid = @import("grid.zig");
pub const paint = @import("paint.zig");
pub const chart = @import("chart.zig");

pub const Rgba = color.Rgba;
pub const Tone = color.Tone;
pub const Fill = dither.Fill;
pub const Matrix = dither.Matrix;
pub const Bloom = grid.Bloom;
pub const PixelGrid = grid.PixelGrid;
pub const Run = grid.Run;

// TODO(port): re-export once `paint.zig` / `chart.zig` are ported:
// Background, ButtonStyle, Direction, Field, Gradient, avatar, button_texture, meter,
// Cartesian, CartesianKind, Pie, PieGeometry, Radar, RadarGeometry, Scale, Series,
// Slice, format_value, sparkline.

test {
    std.testing.refAllDecls(@This());
}
