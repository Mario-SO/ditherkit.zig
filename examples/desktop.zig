//! Opens the same contact sheet as the PPM example in an SDL3 window.
//! zig build desktop -Dsdl

const std = @import("std");
const frontend = @import("ditherkit_sdl");
const preview = @import("preview.zig");
const sdl = frontend.sdl;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    run(init.gpa, args.len > 1 and std.mem.eql(u8, args[1], "--once")) catch |err| {
        if (err == error.SdlFailure) std.log.err("SDL3: {s}", .{std.mem.span(sdl.SDL_GetError())});
        return err;
    };
}

fn run(gpa: std.mem.Allocator, once: bool) !void {
    var grid = try preview.render(gpa);
    defer grid.deinit(gpa);
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) return error.SdlFailure;
    defer sdl.SDL_Quit();

    var window: ?*sdl.SDL_Window = null;
    var renderer: ?*sdl.SDL_Renderer = null;
    if (!sdl.SDL_CreateWindowAndRenderer("ditherkit.zig", @intCast(grid.width * 3), @intCast(grid.height * 3), sdl.SDL_WINDOW_RESIZABLE, &window, &renderer)) return error.SdlFailure;
    defer sdl.SDL_DestroyWindow(window);
    defer sdl.SDL_DestroyRenderer(renderer);
    if (!sdl.SDL_SetRenderLogicalPresentation(renderer, @intCast(grid.width), @intCast(grid.height), sdl.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE)) return error.SdlFailure;

    var canvas = try frontend.Canvas.init(renderer.?, grid.width, grid.height);
    defer canvas.deinit();
    try canvas.upload(grid, .hex(0x0b0b0f));
    while (true) {
        if (!sdl.SDL_RenderClear(renderer)) return error.SdlFailure;
        try canvas.draw(renderer.?, null);
        if (!sdl.SDL_RenderPresent(renderer)) return error.SdlFailure;
        if (once) return;
        var event: sdl.SDL_Event = undefined;
        if (!sdl.SDL_WaitEvent(&event)) return error.SdlFailure;
        if (event.type == sdl.SDL_EVENT_QUIT or
            (event.type == sdl.SDL_EVENT_KEY_DOWN and event.key.key == sdl.SDLK_ESCAPE)) return;
    }
}
