//! SDL3 frontend. Upload a renderer-neutral grid to a reusable texture,
//! compositing translucent pixels over the application's background.

const std = @import("std");
const dk = @import("ditherkit");
pub const sdl = @import("sdl3");

pub const Canvas = struct {
    texture: *sdl.SDL_Texture,
    width: usize,
    height: usize,

    pub const Error = error{ InvalidDimensions, SdlFailure };

    /// Create and use the canvas on SDL's main thread. The renderer must
    /// outlive the canvas.
    pub fn init(renderer: *sdl.SDL_Renderer, width: usize, height: usize) Error!Canvas {
        if (width == 0 or height == 0 or width > std.math.maxInt(c_int) or height > std.math.maxInt(c_int)) {
            return error.InvalidDimensions;
        }
        const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGBA32, sdl.SDL_TEXTUREACCESS_STREAMING, @intCast(width), @intCast(height)) orelse return error.SdlFailure;
        errdefer sdl.SDL_DestroyTexture(texture);
        if (!sdl.SDL_SetTextureScaleMode(texture, sdl.SDL_SCALEMODE_NEAREST) or
            !sdl.SDL_SetTextureBlendMode(texture, sdl.SDL_BLENDMODE_NONE)) return error.SdlFailure;
        return .{ .texture = texture, .width = width, .height = height };
    }

    pub fn deinit(self: *Canvas) void {
        sdl.SDL_DestroyTexture(self.texture);
        self.* = undefined;
    }

    pub fn upload(self: Canvas, grid: dk.PixelGrid, background: dk.Rgba) Error!void {
        if (grid.width != self.width or grid.height != self.height) return error.InvalidDimensions;
        var pixels: ?*anyopaque = null;
        var pitch: c_int = 0;
        if (!sdl.SDL_LockTexture(self.texture, null, &pixels, &pitch)) return error.SdlFailure;
        defer sdl.SDL_UnlockTexture(self.texture);

        const bytes: [*]u8 = @ptrCast(pixels.?);
        const stride: usize = @intCast(pitch);
        const bg = background.withAlpha(255);
        for (0..self.height) |y| @memset(self.row(bytes, stride, y), bg);
        var runs = grid.runs();
        while (runs.next()) |run| {
            const color = if (run.color.a == 255) run.color else run.color.over(bg);
            @memset(self.row(bytes, stride, run.y)[run.x..][0..run.len], color);
        }
    }

    fn row(self: Canvas, bytes: [*]u8, pitch: usize, y: usize) []dk.Rgba {
        const start: [*]dk.Rgba = @ptrCast(bytes + y * pitch);
        return start[0..self.width];
    }

    /// Draw the uploaded grid; null destination fills the render target.
    pub fn draw(self: Canvas, renderer: *sdl.SDL_Renderer, destination: ?*const sdl.SDL_FRect) Error!void {
        if (!sdl.SDL_RenderTexture(renderer, self.texture, null, destination)) return error.SdlFailure;
    }
};

test "SDL canvas composites the same pixels as the core" {
    const surface = sdl.SDL_CreateSurface(3, 2, sdl.SDL_PIXELFORMAT_RGBA32) orelse return error.SdlFailure;
    defer sdl.SDL_DestroySurface(surface);
    const renderer = sdl.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlFailure;
    defer sdl.SDL_DestroyRenderer(renderer);
    var canvas = try Canvas.init(renderer, 3, 2);
    defer canvas.deinit();

    const gpa = std.testing.allocator;
    var grid = try dk.PixelGrid.init(gpa, 3, 2);
    defer grid.deinit(gpa);
    const bg = dk.Rgba.hex(0x100420);
    const fg = dk.Rgba.init(240, 160, 70, 128);
    grid.set(1, 0, fg);
    grid.set(0, 1, .white);
    grid.set(1, 1, .white);
    try canvas.upload(grid, bg);
    try canvas.draw(renderer, null);
    if (!sdl.SDL_RenderPresent(renderer)) return error.SdlFailure;

    for (0..2) |y| {
        for (0..3) |x| {
            var got: dk.Rgba = undefined;
            if (!sdl.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &got.r, &got.g, &got.b, &got.a)) return error.SdlFailure;
            var expected = grid.get(x, y) orelse dk.Rgba.transparent;
            expected = expected.over(bg);
            try std.testing.expectEqual(expected, got);
        }
    }
}
