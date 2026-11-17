//! Small easing helpers for frontends without a motion engine (e.g. TUIs).
//! Port of `dither-core/src/ease.rs`.

const std = @import("std");
const fmath = @import("fmath.zig");

/// Cubic ease-out: fast start, gentle landing.
pub fn outCubic(t: f32) f32 {
    const k = 1.0 - fmath.clamp(t, 0.0, 1.0);
    return 1.0 - k * k * k;
}

/// Cubic ease-in-out.
pub fn inOutCubic(t: f32) f32 {
    const tc = fmath.clamp(t, 0.0, 1.0);
    if (tc < 0.5) return 4.0 * tc * tc * tc;
    const k = -2.0 * tc + 2.0;
    return 1.0 - k * k * k / 2.0;
}

/// Exponential approach of `current` toward `target` over `dt` seconds with
/// time constant `tau`; frame-rate independent smoothing.
pub fn approach(current: f32, target: f32, dt: f32, tau: f32) f32 {
    return target + (current - target) * fmath.expf(-dt / @max(tau, 1e-4));
}

test "endpoints" {
    try std.testing.expectEqual(0.0, outCubic(0.0));
    try std.testing.expectEqual(1.0, outCubic(1.0));
    try std.testing.expectEqual(0.5, inOutCubic(0.5));
}
