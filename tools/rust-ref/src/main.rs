//! Upstream Rust `dither-core` reference for ditherkit.zig.
//!
//! - `golden [dir]`: writes the parity goldens (default `tests/golden`).
//! - `bench`: runs the same workloads as `bench/bench.zig`.
//!
//! Run from the repo root, e.g. `zig build golden` / `zig build bench-rust`.
//!
//! Golden format (`*.grid`): b"DKG1", width u32 LE, height u32 LE, then per
//! pixel 5 bytes: lit (0|1), r, g, b, a. Row-major.

mod bench;
mod scenes;

use dither_core::PixelGrid;
use std::{env, fs, path::Path};

fn write(dir: &Path, name: &str, g: &PixelGrid) {
    let mut out = b"DKG1".to_vec();
    out.extend((g.width() as u32).to_le_bytes());
    out.extend((g.height() as u32).to_le_bytes());
    for c in g.cells() {
        match c {
            Some(c) => out.extend([1, c.r, c.g, c.b, c.a]),
            None => out.extend([0; 5]),
        }
    }
    fs::write(dir.join(format!("{name}.grid")), out).expect("write golden");
}

fn golden(dir: &Path) {
    fs::create_dir_all(dir).unwrap();
    write(dir, "shades", &scenes::shades());
    write(dir, "matrices", &scenes::matrices());
    write(dir, "fills", &scenes::fills());
    write(dir, "bloom", &scenes::bloom());
    write(dir, "sparkle", &scenes::sparkle());
    eprintln!("wrote goldens to {}", dir.display());
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("golden") => golden(Path::new(
            args.get(1).map_or("tests/golden", String::as_str),
        )),
        Some("bench") => bench::run(),
        _ => eprintln!("usage: rust-ref golden [dir] | rust-ref bench"),
    }
}
