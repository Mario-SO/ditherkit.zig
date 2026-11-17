# Porting guide: dither-kit-rs → ditherkit.zig

Upstream: https://github.com/DeepanshuMishraa/dither-kit-rs (Rust 2024, ~6.9k lines).

## Crate → module map

| Rust crate | Zig | Status |
| --- | --- | --- |
| `dither-core` (zero deps) | `src/` → module `ditherkit` | partial |
| `dither-ratatui` | `frontends/term/` → module `ditherkit_term` | `raster.rs` only |
| `dither-gpui` (GPUI Kit + gpui-motion-kit) | — | no Zig equivalent; see below |
| `dither-rune` (Rune, git dep) | — | no Zig equivalent; see below |

## dither-core file status

| Rust | Lines | Zig | Status |
| --- | --- | --- | --- |
| `color.rs` | 238 | `color.zig` | ✅ ported + tests |
| `dither.rs` | 166 | `dither.zig` | ✅ ported + tests |
| `ease.rs` | 24 | `ease.zig` | ✅ ported |
| `grid.rs` | 284 | `grid.zig` | ✅ ported + tests |
| `paint.rs` | 419 | `paint.zig` | ⏳ stub with TODO list |
| `chart.rs` | 832 | `chart.zig` | ⏳ stub with TODO list (port after paint) |
| `examples/preview.rs` | 187 | `examples/preview.zig` | partial — grows with paint/chart |

## Frontends

- **Terminal** (`dither-ratatui`): Zig has no Ratatui, so `ditherkit_term`
  writes truecolor ANSI half-blocks to a `*std.Io.Writer`. Next: widgets
  (`widgets.rs`), charts with hit testing (`charts.rs`), theme, and a gallery
  example (raw mode + mouse input via termios/escape codes, or a TUI lib such
  as libvaxis).
- **Desktop** (`dither-gpui`, `dither-rune`): both frameworks are Rust-only.
  Undecided — candidates are raylib, sokol, SDL3 or dvui. Whatever is chosen
  just needs to paint `PixelGrid.runs()` as rectangles, exactly as the Rust
  frontends do.

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
| `f as u8` (saturating) | `toU8` helper in `color.zig` (round + clamp) |
| `f32::powf` | `fmath.powf` (libm when linked, else `std.math.pow`) |
| `f32::powi(n)` | `fmath.powi` (squaring, same as LLVM) — never `std.math.pow` |
| `wrapping_mul` | `*%` |
| `u32::MAX as f32` | `4294967296.0` (Rust rounds to 2^32) |
| `#[cfg(test)] mod tests` | `test "…"` blocks at the bottom of each file |

## Workflow for porting a file

1. Port the `.rs` file to its `.zig` twin, tests included.
2. Add a scene for it to `tests/scenes.zig` **and** `tools/rust-ref/src/scenes.rs`,
   wire it into `tests/parity.zig` and `tools/rust-ref/src/main.rs`, then
   `zig build golden && zig build test`.
3. Add its hot path to `bench/bench.zig` **and** `tools/rust-ref/src/bench.rs`;
   `zig build bench` must be ≤ `zig build bench-rust`.
4. `zig build fmt cross`, update the status tables here and in the README.
