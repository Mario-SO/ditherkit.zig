<img src="assets/icon.svg" width="56" height="56" alt="">

# ditherkit.zig

Ordered-dither charts, buttons, gradients and backgrounds for Zig — a port of
[dither-kit-rs](https://github.com/DeepanshuMishraa/dither-kit-rs).

**Status: early port.** The core primitives (colors, tones, matrices, fills,
`PixelGrid`, bloom, sparkle, easing) are ported and tested; the rasterizers
(gradients, backgrounds, charts, …) are not yet. See [PORTING.md](PORTING.md).

Requires **Zig 0.17.0**. No dependencies.

## Project rules

1. **Pixel perfect.** Output matches upstream Rust byte for byte; checked by
   parity tests against goldens rendered by the pinned upstream crate.
2. **Same or better performance.** Every hot path is benchmarked against the
   identical Rust workload.
3. **Conventional layout.** Zero-dependency core, frontends as separate modules.
4. **Portable.** The core compiles for Linux, macOS, Windows (x86_64/aarch64),
   riscv64 and wasm32-wasi; CI checks it.

Details in [AGENTS.md](AGENTS.md).

## Layout

```
build.zig / build.zig.zon
src/                 module `ditherkit`        ← dither-core (zero deps)
  root.zig             public API + re-exports
  color.zig            Rgba, Tone, OKLCH ramps           ✅
  dither.zig           Matrix, Fill, hash2/hash01        ✅
  ease.zig             outCubic, inOutCubic, approach    ✅
  grid.zig             PixelGrid, Run(s), Bloom, sparkle ✅
  fmath.zig            Rust-compatible powf/powi
  paint.zig            gradient, background, button, avatar, meter  ⏳
  chart.zig            cartesian, pie, radar, sparkline              ⏳
frontends/
  term/root.zig      module `ditherkit_term`   ← dither-ratatui (raw ANSI)
examples/            preview (PPM contact sheet), term (terminal swatches), icon (assets/icon.svg)
tests/               parity tests: scenes.zig + golden/*.grid from upstream Rust
bench/               benchmarks, twin of tools/rust-ref/src/bench.rs
tools/rust-ref/      pinned upstream Rust: renders goldens, runs benchmarks
```

## Commands

```sh
zig build test                 # unit + pixel-parity tests
zig build fmt                  # formatting check
zig build cross                # compile for every supported target
zig build bench                # Zig benchmarks (compare: zig build bench-rust)
zig build golden               # regenerate goldens from upstream Rust (cargo)
zig build term                 # draw swatches in a truecolor terminal
zig build preview -- out.ppm   # render a contact sheet
zig build icon -- assets/icon.svg  # re-render the project icon
```

## Current numbers

Parity: all scenes byte-identical to upstream (also in ReleaseFast/Safe/Small).

Best of 3 runs, Apple Silicon, µs (lower is better):

| workload | Rust | Zig |
| --- | ---: | ---: |
| shade (100k OKLCH ramps) | 3301 | 2195 |
| matrix_fill (512²) | 142 | 126 |
| bloom_aura (256²) | 2949 | 1174 |
| sparkle (256²) | 130 | 113 |
| runs (512²) | 137 | 133 |

## Using it

```zig
const dk = @import("ditherkit");

var grid = try dk.PixelGrid.init(gpa, 64, 32);
defer grid.deinit(gpa);
const blue: dk.Tone = .blue;
grid.set(3, 4, blue.shade(0.6));
try grid.bloom(gpa, .low);

var it = grid.runs();
while (it.next()) |run| {
    // run.x, run.y, run.len, run.color (RGBA)
}
```

## License

MIT OR Apache-2.0, same as upstream.
