const Rgba = @import("ditherkit").Rgba;

pub const Theme = struct {
    background: Rgba = .hex(0x0b0b0f),
    foreground: Rgba = .hex(0xe7e7ea),
    muted: Rgba = .hex(0x8a8a94),
    border: Rgba = .hex(0x2c2c34),
    popover: Rgba = .hex(0x16161c),

    pub const dark: Theme = .{};
    pub const light: Theme = .{
        .background = .hex(0xfafafa),
        .foreground = .hex(0x18181b),
        .muted = .hex(0x71717a),
        .border = .hex(0xe4e4e7),
        .popover = .white,
    };
};
