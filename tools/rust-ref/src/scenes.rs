//! Rust twins of `tests/scenes.zig`. Each scene must draw exactly what its
//! Zig counterpart draws; keep them in sync.

use dither_core::dither::hash2;
use dither_core::*;

const MATRICES: [Matrix; 5] = [
    Matrix::Bayer2,
    Matrix::Bayer4,
    Matrix::Bayer8,
    Matrix::Halftone,
    Matrix::Noise,
];

pub fn shades() -> PixelGrid {
    let tones: Vec<Tone> = Tone::ALL
        .iter()
        .copied()
        .chain([Tone::Hue(42.5), Tone::Hue(-30.0)])
        .collect();
    let mut g = PixelGrid::new(101, tones.len());
    for (t, tone) in tones.iter().enumerate() {
        for i in 0..=100 {
            g.set(i, t as i32, tone.shade(i as f32 / 100.0));
        }
    }
    g
}

/// Ramps through each matrix, in coordinates centred on 0 to cover negatives.
pub fn matrices() -> PixelGrid {
    let mut g = PixelGrid::new(64, 64 * MATRICES.len());
    for (k, m) in MATRICES.iter().enumerate() {
        for y in 0..64 {
            for x in 0..64 {
                if m.on(x - 32, y - 32, x as f32 / 63.0) {
                    g.set(x, k as i32 * 64 + y, Rgba::WHITE);
                }
            }
        }
    }
    g
}

pub fn fills() -> PixelGrid {
    let mut g = PixelGrid::new(64, 64 * Fill::ALL.len());
    for (k, f) in Fill::ALL.iter().enumerate() {
        for y in 0..64 {
            for x in 0..64 {
                if f.covers(x - 32, y - 32, x as f32 / 63.0) {
                    g.set(x, k as i32 * 64 + y, Rgba::WHITE);
                }
            }
        }
    }
    g
}

pub fn seed(w: usize, h: usize) -> PixelGrid {
    let mut g = PixelGrid::new(w, h);
    let c = Tone::Blue.shade(0.6);
    for y in 0..h as i32 {
        for x in 0..w as i32 {
            match hash2(x, y) % 23 {
                0 => g.set(x, y, c),
                1 => g.set(x, y, c.with_alpha(100)),
                _ => {}
            }
        }
    }
    g
}

pub fn bloom() -> PixelGrid {
    let mut out = PixelGrid::new(32, 32 * Bloom::ALL.len());
    for (k, b) in Bloom::ALL.iter().enumerate() {
        let mut g = seed(32, 32);
        g.bloom(*b);
        out.overlay(&g, 0, k as i32 * 32);
    }
    out
}

pub fn sparkle() -> PixelGrid {
    let mut out = PixelGrid::new(48, 96);
    for (k, (time, anywhere)) in [(1.7f32, false), (4.2, true)].into_iter().enumerate() {
        let mut g = PixelGrid::new(48, 48);
        for y in 0..48 {
            for x in 0..48 {
                if (x + y) % 3 == 0 {
                    g.set(x, y, Tone::Pink.base());
                }
            }
        }
        g.sparkle(time, 0.3, Rgba::WHITE, anywhere);
        g.fade(0.8);
        out.overlay(&g, 0, k as i32 * 48);
    }
    out
}
