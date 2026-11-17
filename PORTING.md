# Porting guide: dither-kit-rs → ditherkit.zig

The [upstream revision](https://github.com/DeepanshuMishraa/dither-kit-rs/tree/3abee173e404c85a86653cfc180c88779ddfdb63)
used for the checked-in goldens is `3abee173e404c85a86653cfc180c88779ddfdb63`.

## Crate and module coverage

| Rust crate | Zig | Coverage |
| --- | --- | --- |
| `dither-core` | `src/` → `ditherkit` | All primitives, paint rasterizers, charts, and geometry |
| `dither-ratatui` | `frontends/term/` → `ditherkit_term` | ANSI half-blocks, themes, widgets, axes, legends, tooltips, and hit testing |
| `dither-gpui`, `dither-rune` | `frontends/sdl/` → `ditherkit_sdl` | SDL3 grid composition and scaling. Native application event handling and desktop widget layouts belong to the host application. |

The terminal frontend writes through `std.Io.Writer`. Applications supply
keyboard and mouse events and pass hover, focus, selection, and animation
progress to the widgets. Its label layout uses one cell per Unicode code point.

The SDL3 canvas uploads reusable nearest-neighbor textures using
`PixelGrid.runs()` and composites with the core's RGBA rules. The
`desktop` example displays the same 400×330 grid as the PPM preview.

## dither-core file map

| Rust | Zig | Coverage |
| --- | --- | --- |
| `color.rs` | `color.zig` | Colors, tones, perceptual shade ramps |
| `dither.rs` | `dither.zig` | Matrices, fills, coordinate hashes |
| `ease.rs` | `ease.zig` | Cubic easing and exponential approach |
| `grid.rs` | `grid.zig` | Pixel grid, runs, bloom, sparkle |
| `paint.rs` | `paint.zig` | Gradients, fields, button textures, avatars, meters |
| `chart.rs` | `chart.zig` | Cartesian, pie, radar, sparkline, scales, hit testing |
| `examples/preview.rs` | `examples/preview.zig` | Upstream PPM contact sheet |

## Conventions

| Rust | Zig |
| --- | --- |
| `Option<Rgba>` | `?Rgba` |
| `enum Tone { …, Hue(f32) }` | `union(enum)` with a `.hue: f32` payload |
| `PascalCase` variants, `ALL` consts | `snake_case` tags, `all` decls, `name()` via `@tagName` |
| `snake_case` fns (`out_cubic`) | `camelCase` fns (`outCubic`) |
| `Vec`, `clone()`, implicit alloc | explicit `gpa: std.mem.Allocator`; caller `deinit`s |
| builders (`Gradient::new(t).to(u)`) | structs with default fields (`.{ .from = .blue, .to = .purple }`) |
| `impl Iterator` (`runs()`) | iterator struct with `next() ?T` |
| `x.rem_euclid(n)` | `@mod(x, n)` |
| `i32 / i32` (truncating) | `@divTrunc` |
| `f as integer` (saturating) | `fmath.saturatingInt` (round first only where Rust does) |
| `f32::powf` | `fmath.powf` (libm when linked, else `std.math.pow`) |
| `f32::powi(n)` | `fmath.powi` (squaring, same as LLVM) — never `std.math.pow` |
| `wrapping_mul` | `*%` |
| `u32::MAX as f32` | `4294967296.0` (Rust rounds to 2^32) |
| `#[cfg(test)] mod tests` | `test "…"` blocks at the bottom of each file |

## Updating the Rust parity fixtures

The repo contains the rendered fixtures in `tests/golden/`. The default
build and CI compare pixels against those fixtures using Zig. Regenerating them
and comparing benchmark timings requires the separate Rust reference project
and Cargo. The local reference project is at `../ditherkit-rust-ref`.

1. Port the Rust file to its Zig twin. Add identical inputs in
   `tests/scenes.zig` and the reference project's `src/scenes.rs`.
2. Register the new fixture in `tests/parity.zig` and the reference project's
   `src/main.rs`, then generate and verify it.

   ```sh
   zig build golden -Drust-ref=../ditherkit-rust-ref/Cargo.toml
   zig build test fmt cross
   ```

3. Add matching workloads in `bench/bench.zig` and the reference project's
   `src/bench.rs`. Compare the best of several runs.

   ```sh
   zig build bench
   zig build bench-rust -Drust-ref=../ditherkit-rust-ref/Cargo.toml
   ```
