# ditherkit.zig — project rules

A Zig port of [dither-kit-rs](https://github.com/DeepanshuMishraa/dither-kit-rs).
These four rules are non-negotiable; every change is judged against them.

## 1. Same look as upstream — pixel perfect

- Output must match upstream Rust `dither-core` pixel for pixel. "Close" is a bug.
- Every ported rasterizer gets a scene in **both** `tests/scenes.zig` and
  `tools/rust-ref/src/scenes.rs` (identical inputs), then `zig build golden`
  to regenerate `tests/golden/*.grid`. `zig build test` compares byte for byte.
- Never hand-edit goldens. Never loosen the comparison to make a test pass;
  find the semantic difference instead (see the conversion table in PORTING.md:
  `rem_euclid`, truncating division, saturating casts, `u32::MAX as f32`, …).
- Float math that Rust sends to libm goes through `src/fmath.zig`, so results
  track Rust on every platform.
- Upstream is pinned in `tools/rust-ref/Cargo.toml`. Bump it deliberately,
  regenerate goldens, and port the upstream diff in the same change.

## 2. Same or better performance

- Every hot path has a workload in **both** `bench/bench.zig` and
  `tools/rust-ref/src/bench.rs`. Compare with `zig build bench` vs
  `zig build bench-rust` (best of several runs; the machine is noisy).
- A change that makes any Zig number slower than Rust doesn't land.
- No allocation inside per-pixel loops; take scratch buffers from the caller's
  allocator. Prefer `inline` for per-pixel helpers (`Matrix.on`, `Fill.covers`).

## 3. Neat, conventional architecture

- `src/` is the core module `ditherkit`: zero dependencies, no I/O, no
  globals, no frontend concerns. One upstream `.rs` file → one `.zig` file.
- Frontends live in `frontends/<name>/root.zig` as separate modules that
  import `ditherkit`; they never reach into each other.
- `examples/` show usage, `tests/` hold cross-cutting tests (parity),
  `bench/` holds benchmarks, `tools/` holds dev tooling. Unit tests sit at the
  bottom of the file they test.
- Explicit allocators (`gpa: std.mem.Allocator`), caller `deinit`s. Zig naming:
  `camelCase` functions, `snake_case` enum tags, `PascalCase` types.
- `zig build fmt` must pass. Keep `README.md` and `PORTING.md` status current.

## 4. Easily portable

- The core must build for every target in `cross_targets` (`build.zig`);
  `zig build cross` checks it. Don't require libc, an OS, threads or SIMD
  intrinsics in `src/`; optional fast paths must fall back (see `fmath.zig`).
- Frontend-specific dependencies stay in that frontend's module.
- Pin the Zig version in `build.zig.zon` (`minimum_zig_version`) and CI.

## Commands

```sh
zig build test         # unit + parity tests (with and without libc)
zig build fmt          # formatting check
zig build cross        # compile core + tests for all supported targets
zig build bench        # Zig benchmarks (ReleaseFast)
zig build bench-rust   # upstream Rust benchmarks (needs cargo)
zig build golden       # regenerate goldens from upstream Rust (needs cargo)
```
