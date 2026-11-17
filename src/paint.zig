//! Gradients, animated backgrounds, button textures, avatars and meters.
//! Port of `dither-core/src/paint.rs` (419 lines) — NOT STARTED.
//!
//! To port (Rust name → Zig name):
//!   enum Direction { Up, Down, Left, Right, Radial } + position()  → Direction.position
//!   struct Gradient (builder: to/direction/matrix/density, render) → Gradient
//!   enum Field { Plasma, Waves, Ripple, Noise, Aurora } + sample() → Field.sample
//!   struct Background (builder: accent/matrix/density, render(w,h,time))
//!   enum ButtonStyle { Solid, Outline, Ghost } + density()/surface()
//!   fn button_texture(..)                                          → buttonTexture
//!   fn avatar(name, hue)  (8x8 mirrored identicon)                 → avatar
//!   fn fnv1a(bytes) u64                                            → fnv1a
//!   fn meter(w, h, value, tone, fill)                              → meter
//!
//! Conventions: Rust builders become structs with default field values
//! (`Gradient{ .from = .blue, .to = .purple }`), and every `render` takes
//! `gpa: std.mem.Allocator` and returns a `PixelGrid` the caller deinits.
