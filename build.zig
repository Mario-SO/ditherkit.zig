const std = @import("std");

/// Targets `zig build cross` must keep compiling for.
const cross_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `ditherkit`: the renderer-neutral engine (port of `dither-core`).
    const core = b.addModule("ditherkit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // `ditherkit_term`: ANSI half-block terminal frontend (stands in for
    // `dither-ratatui`; Zig has no Ratatui, so it writes escape codes directly).
    const term = b.addModule("ditherkit_term", .{
        .root_source_file = b.path("frontends/term/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "ditherkit", .module = core }},
    });

    // Tests: `zig build test`
    const test_step = b.step("test", "Run all unit tests");
    for ([_]*std.Build.Module{ core, term }) |mod| {
        const t = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // Pixel parity against upstream Rust goldens (part of `zig build test`).
    // Run with and without libc, since `fmath.powf` has a backend for each.
    for ([_]bool{ false, true }) |libc| {
        const parity_core = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = libc,
        });
        const parity = b.addTest(.{
            .name = if (libc) "parity-libc" else "parity",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/parity.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = libc,
                .imports = &.{
                    .{ .name = "ditherkit", .module = parity_core },
                    .{ .name = "scenes", .module = sceneModule(b, parity_core, target, optimize) },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(parity).step);
    }

    // Cross-compile the core and its tests for every supported target:
    // `zig build cross` (compile only; catches portability breaks).
    const cross_step = b.step("cross", "Compile core + tests for all supported targets");
    for (cross_targets) |query| {
        const cross_target = b.resolveTargetQuery(query);
        const module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = cross_target,
            .optimize = .safe,
        });
        const triple = query.zigTriple(b.allocator) catch @panic("OOM");
        const unit = b.addTest(.{ .name = b.fmt("cross-{s}", .{triple}), .root_module = module });
        cross_step.dependOn(&unit.step);

        const parity = b.addTest(.{
            .name = b.fmt("cross-parity-{s}", .{triple}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/parity.zig"),
                .target = cross_target,
                .optimize = .safe,
                .imports = &.{
                    .{ .name = "ditherkit", .module = module },
                    .{ .name = "scenes", .module = sceneModule(b, module, cross_target, .safe) },
                },
            }),
        });
        cross_step.dependOn(&parity.step);
    }

    // Benchmarks, always optimized for speed: `zig build bench` vs `zig build bench-rust`.
    const fast_core = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .fast,
        .link_libc = true,
    });
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = .fast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "ditherkit", .module = fast_core },
                .{ .name = "scenes", .module = sceneModule(b, fast_core, target, .fast) },
            },
        }),
    });
    const bench_run = b.addRunArtifact(bench);
    bench_run.has_side_effects = true;
    b.step("bench", "Run speed-optimized benchmarks").dependOn(&bench_run.step);

    // Opt in to reference commands using a separate Cargo project.
    if (b.option([]const u8, "rust-ref", "Path to the external Rust reference Cargo.toml")) |manifest| {
        const rust_ref = .{ "cargo", "run", "--release", "--quiet", "--locked", "--manifest-path", manifest, "--" };
        const golden = b.addSystemCommand(&(rust_ref ++ .{ "golden", "tests/golden" }));
        golden.setEnvironmentVariable("CARGO_NET_GIT_FETCH_WITH_CLI", "true");
        b.step("golden", "Regenerate parity goldens from upstream Rust").dependOn(&golden.step);

        const bench_rust = b.addSystemCommand(&(rust_ref ++ .{"bench"}));
        bench_rust.setEnvironmentVariable("CARGO_NET_GIT_FETCH_WITH_CLI", "true");
        b.step("bench-rust", "Run the upstream Rust benchmarks").dependOn(&bench_rust.step);
    }

    // Examples: `zig build <name> -- args`
    const examples = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "preview", .desc = "Render a PPM contact sheet (zig build preview -- out.ppm)" },
        .{ .name = "term", .desc = "Draw dithered swatches in a truecolor terminal" },
        .{ .name = "icon", .desc = "Render the project icon (zig build icon -- assets/icon.svg)" },
    };
    for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{ex.name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "ditherkit", .module = core },
                    .{ .name = "ditherkit_term", .module = term },
                },
            }),
        });
        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        run.addPassthruArgs();
        b.step(ex.name, ex.desc).dependOn(&run.step);
    }

    if (b.option(bool, "sdl", "Build the SDL3 desktop frontend and example") orelse false) {
        addSdl(b, core, target, optimize, test_step);
    }

    // Formatting check: `zig build fmt`
    const fmt = b.addFmt(.{
        .paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("src"), b.path("frontends"), b.path("examples"), b.path("tests"), b.path("bench") },
        .check = true,
    });
    b.step("fmt", "Check formatting").dependOn(&fmt.step);
}

fn addSdl(
    b: *std.Build,
    core: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    test_step: *std.Build.Step,
) void {
    const dependency = b.lazyDependency("translate_c", .{}) orelse return;
    const Translator = @import("translate_c").Translator;
    const header = b.addWriteFiles().add("sdl.h", "#include <SDL3/SDL.h>\n");
    const binding: Translator = .init(dependency, .{
        .c_source_file = header,
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{.{ .name = "SDL3", .options = .{ .use_pkg_config = .force } }},
    });
    const sdl = b.addModule("ditherkit_sdl", .{
        .root_source_file = b.path("frontends/sdl/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ditherkit", .module = core },
            .{ .name = "sdl3", .module = binding.mod },
        },
    });
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = sdl })).step);

    const desktop = b.addExecutable(.{
        .name = "desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/desktop.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ditherkit", .module = core },
                .{ .name = "ditherkit_sdl", .module = sdl },
            },
        }),
    });
    b.installArtifact(desktop);
    const run = b.addRunArtifact(desktop);
    run.addPassthruArgs();
    b.step("desktop", "Open the contact sheet in an SDL3 window").dependOn(&run.step);
}

/// The parity scenes (`tests/scenes.zig`), bound to a given core module.
fn sceneModule(
    b: *std.Build,
    core: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("tests/scenes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "ditherkit", .module = core }},
    });
}
