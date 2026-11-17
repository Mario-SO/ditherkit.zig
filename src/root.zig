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

pub const Direction = paint.Direction;
pub const Gradient = paint.Gradient;
pub const Field = paint.Field;
pub const Background = paint.Background;
pub const ButtonStyle = paint.ButtonStyle;
pub const buttonTexture = paint.buttonTexture;
pub const avatar = paint.avatar;
pub const meter = paint.meter;

pub const Series = chart.Series;
pub const Scale = chart.Scale;
pub const CartesianKind = chart.CartesianKind;
pub const Cartesian = chart.Cartesian;
pub const Slice = chart.Slice;
pub const Pie = chart.Pie;
pub const PieGeometry = chart.PieGeometry;
pub const Radar = chart.Radar;
pub const RadarGeometry = chart.RadarGeometry;
pub const formatValue = chart.formatValue;
pub const sparkline = chart.sparkline;

test {
    std.testing.refAllDecls(@This());
}
