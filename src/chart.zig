//! Cartesian (area/line/bar), pie/donut, radar and sparkline rasterizers.
//! Port of `dither-core/src/chart.rs` (832 lines) — NOT STARTED.
//!
//! To port (Rust name → Zig name):
//!   struct Series { label, tone, values: Vec<f64>, fill, hidden }   → Series ([]const f64, borrowed)
//!   struct Scale + nice()/y()                                      → Scale
//!   fn format_value(f64) -> String                                 → formatValue(buf, v) []u8 (no alloc)
//!   fn interpolate / line / guide                                  → interpolate / line / guide
//!   enum CartesianKind { Area, Line, Bar }
//!   struct Cartesian<'a> (len, scale, column_x, index_at, render)  → Cartesian
//!   fn sparkline(values, tone, w, h, hovered, progress)            → sparkline
//!   struct Slice, Pie<'a>, PieGeometry (index_at)                  → Slice, Pie, PieGeometry
//!   struct Radar<'a>, RadarGeometry                                → Radar, RadarGeometry
//!
//! Depends on `paint.zig` only for shared helpers; port that first.
