const std = @import("std");
const Io = std.Io;
const GameBoy = @import("GameBoy.zig").GameBoy;

const gameboy_emu_zig = @import("gameboy_emu_zig");

pub fn main(init: std.process.Init) !void {
    var gb = try GameBoy.init(init.io, init.gpa, "Tetris.gb");

    std.debug.print("Boot ROM Start: 0x{X:0>2}\n", .{gb.bus.read(0x0000)});

    std.debug.print("Cartridge Logo Start: 0x{X:0>2}\n", .{gb.bus.read(0x0104)});

    while (true) {
        gb.step();
        // Test below, can remove
        if (gb.registers.pc == 0x000C) {
            std.debug.print("SUCCESS: PC reached 0x000C (Loop Exited)\n", .{});
        }
    }

    gb.deinit();
}
