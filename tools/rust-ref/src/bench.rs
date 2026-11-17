//! Rust twin of `bench/bench.zig`: identical workloads, identical report.

use crate::scenes::seed;
use dither_core::*;
use std::hint::black_box;
use std::time::{Duration, Instant};

const BUDGET: Duration = Duration::from_millis(400);

/// Best time over repeated runs until the time budget (min 5 runs) is spent.
fn measure(name: &str, mut f: impl FnMut() -> u64) {
    let (mut best, mut runs, start) = (Duration::MAX, 0u32, Instant::now());
    while runs < 5 || start.elapsed() < BUDGET {
        let t = Instant::now();
        black_box(f());
        best = best.min(t.elapsed());
        runs += 1;
    }
    println!("{name:<14} {:>12.1} us", best.as_secs_f64() * 1e6);
}

pub fn run() {
    println!("rust (dither-core)");
    measure("shade", || {
        let mut acc = 0u64;
        for i in 0..100_000u32 {
            let tone = Tone::ALL[(i % 7) as usize];
            acc += tone.shade((i % 1001) as f32 / 1000.0).r as u64;
        }
        acc
    });
    measure("matrix_fill", || {
        let mut acc = 0u64;
        for y in 0..512 {
            for x in 0..512 {
                let t = x as f32 / 511.0;
                acc += Matrix::Bayer8.on(x, y, t) as u64 + Fill::Dotted.covers(x, y, t) as u64;
            }
        }
        acc
    });
    measure("bloom_aura", || {
        let mut g = seed(256, 256);
        g.bloom(Bloom::Aura);
        g.lit_count() as u64
    });
    measure("sparkle", || {
        let mut g = PixelGrid::new(256, 256);
        let c = Tone::Pink.base();
        for y in 0..256 {
            for x in 0..256 {
                if (x + y) % 3 == 0 {
                    g.set(x, y, c);
                }
            }
        }
        g.sparkle(1.7, 0.3, Rgba::WHITE, false);
        g.lit_count() as u64
    });
    let g = seed(512, 512);
    measure("runs", || g.runs().map(|r| r.len as u64).sum());
}
