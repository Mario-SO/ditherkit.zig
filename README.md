<img src="assets/icon.svg" width="56" height="56" alt="">

# ditherkit.zig

Ordered-dither charts, buttons, gradients and backgrounds for Zig — a port of
[dither-kit-rs](https://github.com/DeepanshuMishraa/dither-kit-rs).

The rendering core includes every paint and chart rasterizer from the pinned
Rust release. The ANSI frontend adds widgets and chart interaction geometry.
An optional SDL3 frontend draws the same grids in native windows. See
[PORTING.md](PORTING.md) for frontend coverage.

Requires **Zig 0.17.0**. The rendering core and ANSI frontend have no dependencies.

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
  fmath.zig            Rust-compatible float math
  paint.zig            gradient, background, button, avatar, meter
  chart.zig            cartesian, pie, radar, sparkline
frontends/
  term/root.zig      module `ditherkit_term`   ANSI widgets and charts
  sdl/root.zig       module `ditherkit_sdl`    optional SDL3 canvas
examples/            PPM preview, terminal gallery, SDL3 preview, project icon
tests/               parity tests: scenes.zig + golden/*.grid from upstream Rust
bench/               Zig benchmarks
```

## Commands

```sh
zig build test                 # unit + pixel-parity tests
zig build fmt                  # formatting check
zig build cross                # compile for every supported target
zig build bench                # run the Zig benchmarks
zig build term                 # draw swatches in a truecolor terminal
zig build term -- --gallery    # draw the terminal widget gallery
zig build preview -- out.ppm   # render the upstream contact sheet
zig build desktop -Dsdl        # open the contact sheet in an SDL3 window
zig build test -Dsdl           # also test the SDL3 canvas
zig build icon -- assets/icon.svg  # re-render the project icon
```

The optional desktop targets require SDL3 development headers and libraries on
the build machine, discoverable by `pkg-config`. Zig fetches the pinned
Translate-C package when `-Dsdl` is enabled.

## Verification

`zig build test` compares 14 scenes byte for byte with the pinned Rust goldens
and runs them with and without libc. The table shows the best
time for each workload over three runs on Apple Silicon, in microseconds.
See [PORTING.md](PORTING.md) to regenerate the fixtures or rerun the Rust
benchmarks with the external reference harness.

| Workload | Rust | Zig |
| --- | ---: | ---: |
| shade | 3439.8 | 2343.5 |
| matrix_fill | 142.6 | 126.4 |
| bloom_aura | 2965.1 | 2255.5 |
| sparkle | 115.0 | 90.8 |
| runs | 140.2 | 123.4 |
| gradient | 72.8 | 21.4 |
| background | 173.6 | 134.2 |
| button | 24.1 | 2.4 |
| avatar | 2.2 | 0.4 |
| meter | 22.6 | 3.2 |
| cartesian | 209.0 | 138.0 |
| sparkline | 32.0 | 19.8 |
| pie | 83.6 | 51.5 |
| radar | 49.0 | 23.3 |

## Using it

```zig
const dk = @import("ditherkit");

const samples = [_]dk.Series{
    .{ .label = "Requests", .tone = .blue, .values = &.{ 3, 8, 5, 9 } },
};
const chart: dk.Cartesian = .{ .series = &samples, .hover = 2 };
var grid = try chart.render(gpa, 80, 32);
defer grid.deinit(gpa);

var it = grid.runs();
while (it.next()) |run| {
    // run.x, run.y, run.len, run.color (RGBA)
}
```

## License

MIT OR Apache-2.0, same as upstream.
