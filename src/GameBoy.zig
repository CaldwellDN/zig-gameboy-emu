const std = @import("std");
const Registers = @import("registers.zig").Registers;
const Bus = @import("bus.zig").Bus;

pub const GameBoy = struct {
    registers: Registers,
    bus: Bus,
    allocator: std.mem.Allocator,

    pub fn init(io: std.Io, alloc: std.mem.Allocator, rom_path: ?[]const u8) !GameBoy {
        var rom_data: []u8 = &[_]u8{};

        if (rom_path != null) {
            const cwd = std.Io.Dir.cwd();
            rom_data = try cwd.readFileAlloc(io, rom_path.?, alloc, @enumFromInt(8 * 1024 * 1024));
        } else {
            rom_data = try alloc.alloc(u8, 0x8000);
            @memset(rom_data, 0);
        }

        return GameBoy{
            .registers = .{},
            .bus = Bus{
                .cartridge = rom_data,
                .vram = [_]u8{0} ** 0x2000,
                .work_ram = [_]u8{0} ** 0x2000,
                .high_ram = [_]u8{0} ** 128,
                .boot_rom_enabled = true,
            },
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *GameBoy) void {
        self.allocator.free(self.bus.cartridge);
    }

    fn getRegValue(self: *GameBoy, bits: u3) u8 {
        return switch (bits) {
            0 => self.registers.b(),
            1 => self.registers.c(),
            2 => self.registers.d(),
            3 => self.registers.e(),
            4 => self.registers.h(),
            5 => self.registers.l(),
            6 => self.bus.read(self.registers.hl),
            7 => self.registers.a(),
        };
    }

    fn setRegValue(self: *GameBoy, bits: u3, val: u8) void {
        switch (bits) {
            0 => self.registers.set_b(val),
            1 => self.registers.set_c(val),
            2 => self.registers.set_d(val),
            3 => self.registers.set_e(val),
            4 => self.registers.set_h(val),
            5 => self.registers.set_l(val),
            6 => self.bus.write(self.registers.hl, val),
            7 => self.registers.set_a(val),
        }
    }

    pub fn step(self: *GameBoy) void {
        const pc = self.registers.pc;
        const opcode = self.bus.read(pc);

        // std.debug.print("PC: 0x{X:0>4} | Opcode: 0x{X:0>2}\n", .{ pc, opcode });
        std.debug.print("PC: 0x{X:0>4} | Opcode: 0x{X:0>2} | HL: 0x{X:0>4}\n", .{ pc, opcode, self.registers.hl });

        self.registers.pc += 1;
        self.execute(opcode);
    }

    fn execute(self: *GameBoy, opcode: u16) void {
        switch (opcode) {
            0x00 => { // NOP
                // Program Counter already incremented in step() function
            },

            0x01, 0x11, 0x21, 0x31 => { // LD reg, d16
                const low = self.bus.read(self.registers.pc);
                const high = self.bus.read(self.registers.pc + 1);
                const val = (@as(u16, high) << 8) | low;

                self.registers.pc += 2;

                switch (opcode) {
                    0x01 => self.registers.bc = val,
                    0x11 => self.registers.de = val,
                    0x21 => self.registers.hl = val,
                    0x31 => self.registers.sp = val,
                    else => unreachable,
                }
            },

            0x02, 0x12, 0x22, 0x32 => { // LD - NOTE: rewrite with helper functions later
                const a_val = self.registers.a();

                switch (opcode) {
                    0x02 => self.bus.write(self.registers.bc, a_val),
                    0x12 => self.bus.write(self.registers.de, a_val),
                    0x22, 0x32 => {
                        self.bus.write(self.registers.hl, a_val);
                        self.registers.hl = if (opcode == 0x22) self.registers.hl +% 1 else self.registers.hl -% 1;
                    },
                    else => unreachable,
                }
            },

            0x07 => { // RLCA
                const a = self.registers.a();
                const bit7 = (a >> 7);
                const result = (a << 1) | bit7;

                self.registers.set_a(result);

                self.registers.set_flag(Registers.Flags.Z, false);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, false);
                self.registers.set_flag(Registers.Flags.C, bit7 == 1);
            },

            0x08 => { // LD a16, SP
                const low_a16: u8 = self.bus.read(self.registers.pc);
                const high_a16: u8 = self.bus.read(self.registers.pc + 1);
                self.registers.pc += 2;

                const a16: u16 = (@as(u16, high_a16) << 8) | low_a16;

                const low_sp: u8 = @truncate(self.registers.sp);
                const high_sp: u8 = @intCast(self.registers.sp >> 8);

                self.bus.write(a16, low_sp);
                self.bus.write(a16 +% 1, high_sp);
            },

            0x17 => { // RLA
                const a = self.registers.a();
                const old_carry: u8 = if (self.registers.get_flag(Registers.Flags.C)) 1 else 0;
                const bit7 = (a >> 7);
                const result = (a << 1) | old_carry;

                self.registers.set_a(result);

                self.registers.set_flag(Registers.Flags.Z, false);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, false);
                self.registers.set_flag(Registers.Flags.C, bit7 == 1);
            },

            0x0A, 0x1A, 0x2A, 0x3A => {
                const addr = switch (opcode) {
                    0x0A => self.registers.bc,
                    0x1A => self.registers.de,
                    0x2A, 0x3A => self.registers.hl,
                    else => unreachable,
                };

                const val = self.bus.read(addr);
                self.registers.set_a(val);

                if (addr == 0x2A) {
                    self.registers.hl = self.registers.hl +% 1;
                } else if (addr == 0x3A) {
                    self.registers.hl = self.registers.hl -% 1;
                }
            },

            0x0E, 0x1E, 0x2E, 0x3E, 0x06, 0x16, 0x26, 0x36 => { // LD C/E/L/A, d8
                const val = self.bus.read(self.registers.pc);
                self.registers.pc += 1;

                switch (opcode) {
                    0x0E => self.registers.set_c(val),
                    0x1E => self.registers.set_e(val),
                    0x2E => self.registers.set_l(val),
                    0x3E => self.registers.set_a(val),
                    0x06 => self.registers.set_b(val),
                    0x16 => self.registers.set_d(val),
                    0x26 => self.registers.set_h(val),
                    0x36 => {
                        self.bus.write(self.registers.hl, val);
                    },
                    else => unreachable,
                }
            },

            0x20, 0x30, 0x28, 0x38 => { // JR NZ, JR NC, JR Z, JR C
                const offset_u8 = self.bus.read(self.registers.pc);
                const offset = @as(i8, @bitCast(offset_u8));
                self.registers.pc += 1;

                const condition = switch (opcode) {
                    0x20 => !self.registers.get_flag(Registers.Flags.Z), // NZ
                    0x28 => self.registers.get_flag(Registers.Flags.Z), // Z
                    0x30 => !self.registers.get_flag(Registers.Flags.C), // NC
                    0x38 => self.registers.get_flag(Registers.Flags.C), // C
                    else => unreachable,
                };

                if (condition) {
                    const new_pc = @as(i16, @intCast(self.registers.pc)) + offset;
                    self.registers.pc = @intCast(new_pc);
                }
            },

            0x04, 0x14, 0x24, 0x34, 0x0C, 0x1C, 0x2C, 0x3C => { // INC register
                const reg_bit: u3 = @intCast((opcode >> 3) & 0x7);
                const val = self.getRegValue(reg_bit);
                self.setRegValue(reg_bit, val +% 1);

                self.registers.set_flag(Registers.Flags.Z, (val +% 1) == 0);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, (val & 0x0F) == 0x0F);
            },

            0x05, 0x15, 0x25, 0x35, 0x0D, 0x1D, 0x2D, 0x3D => { // DEC register
                const reg_bit: u3 = @intCast((opcode >> 3) & 0x7);
                const val = self.getRegValue(reg_bit);
                self.setRegValue(reg_bit, val -% 1);

                self.registers.set_flag(Registers.Flags.Z, (val -% 1) == 0);
                self.registers.set_flag(Registers.Flags.N, true);
                self.registers.set_flag(Registers.Flags.H, (val & 0x0F) == 0);
            },

            0x03, 0x13, 0x23, 0x33 => { // INC register pair
                switch (opcode) {
                    0x03 => self.registers.bc = self.registers.bc +% 1,
                    0x13 => self.registers.de = self.registers.de +% 1,
                    0x23 => self.registers.hl = self.registers.hl +% 1,
                    0x33 => self.registers.sp = self.registers.sp +% 1,
                    else => unreachable,
                }
            },

            0x0B, 0x1B, 0x2B, 0x3B => { // DEC register pair
                switch (opcode) {
                    0x0B => self.registers.bc = self.registers.bc -% 1,
                    0x1B => self.registers.de = self.registers.de -% 1,
                    0x2B => self.registers.hl = self.registers.hl -% 1,
                    0x3B => self.registers.sp = self.registers.sp -% 1,
                    else => unreachable,
                }
            },

            0x40...0x75, 0x77...0x7F => { // 8-bit load operations
                const destination: u3 = @intCast((opcode >> 3) & 0x7);
                const source: u3 = @intCast(opcode & 0x7);
                const val = self.getRegValue(source);
                self.setRegValue(destination, val);
            },

            0x80...0x87 => { // ADD register operations + HL
                const a_val: u8 = self.registers.a();
                const reg_idx: u3 = @intCast(opcode & 0x7);
                const reg_val: u8 = if (reg_idx == 6) self.bus.read(self.registers.hl) else self.getRegValue(reg_idx);

                const result: u16 = @as(u16, a_val) + reg_val;
                const result_u8: u8 = @as(u8, @intCast(result & 0xFF));

                const H_check = (a_val & 0x0F) + (reg_val & 0x0F) > 0x0F;

                self.registers.set_a(result_u8);

                self.registers.set_flag(Registers.Flags.Z, result_u8 == 0);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, H_check);
                self.registers.set_flag(Registers.Flags.C, result > 0xFF);
            },

            0x88...0x8F => { // ADC register operations + HL
                const a_val: u8 = self.registers.a();
                const reg_idx: u3 = @intCast(opcode & 0x7);
                const reg_val: u8 = if (reg_idx == 6) self.bus.read(self.registers.hl) else self.getRegValue(reg_idx);

                const carry_val: u8 = if (self.registers.get_flag(Registers.Flags.C)) 1 else 0;

                const result: u16 = @as(u16, a_val) + reg_val + carry_val;
                const result_u8: u8 = @as(u8, @intCast(result & 0xFF));

                const H_check = (a_val & 0x0F) + (reg_val & 0x0F) + carry_val > 0x0F;

                self.registers.set_a(result_u8);

                self.registers.set_flag(Registers.Flags.Z, result_u8 == 0);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, H_check);
                self.registers.set_flag(Registers.Flags.C, result > 0xFF);
            },

            0xA8...0xAD, 0xAF => { // XOR 8-bit
                const source_bits: u3 = @intCast(opcode & 0x7);
                const source_val = self.getRegValue(source_bits);

                const value = self.registers.a() ^ source_val;
                self.registers.set_a(value);

                self.registers.set_flag(Registers.Flags.Z, value == 0);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, false);
                self.registers.set_flag(Registers.Flags.C, false);
            },

            0xC1, 0xD1, 0xE1, 0xF1 => { // POP BC, DE, HL, AF
                const low_val = self.bus.read(self.registers.sp);
                self.registers.sp = self.registers.sp +% 1;

                const high_val = self.bus.read(self.registers.sp);
                self.registers.sp = self.registers.sp +% 1;

                switch (opcode) {
                    0xC1 => {
                        self.registers.set_c(low_val);
                        self.registers.set_b(high_val);
                    },
                    0xD1 => {
                        self.registers.set_e(low_val);
                        self.registers.set_d(high_val);
                    },
                    0xE1 => {
                        self.registers.set_l(low_val);
                        self.registers.set_h(high_val);
                    },
                    0xF1 => {
                        self.registers.set_f(low_val & 0xF0);
                        self.registers.set_a(high_val);
                    },
                    else => unreachable,
                }
            },

            0xC5, 0xD5, 0xE5, 0xF5 => { // PUSH BC, DE, HL, AF
                const vals = switch (opcode) {
                    0xC5 => .{ self.registers.b(), self.registers.c() },
                    0xD5 => .{ self.registers.d(), self.registers.e() },
                    0xE5 => .{ self.registers.h(), self.registers.l() },
                    0xF5 => .{ self.registers.a(), self.registers.f() },
                    else => unreachable,
                };
                self.registers.sp = self.registers.sp -% 1;
                self.bus.write(self.registers.sp, vals[0]);

                self.registers.sp = self.registers.sp -% 1;
                self.bus.write(self.registers.sp, vals[1]);
            },

            0xC9 => {},

            0xCC => { // CALL Z, a16
                const low = self.bus.read(self.registers.pc);
                const high = self.bus.read(self.registers.pc + 1);
                const dest_addr = (@as(u16, high) << 8) | low;

                self.registers.pc += 2;

                if (self.registers.get_flag(Registers.Flags.Z)) {
                    const return_addr = self.registers.pc;

                    self.registers.sp -%= 1;
                    self.bus.write(self.registers.sp, @as(u8, @intCast((return_addr >> 8) & 0xFF)));

                    self.registers.sp -%= 1;
                    self.bus.write(self.registers.sp, @as(u8, @intCast(return_addr & 0xFF)));

                    self.registers.pc = dest_addr;
                }
            },

            0xCD => {
                const low = self.bus.read(self.registers.pc);
                const high = self.bus.read(self.registers.pc + 1);
                const dst: u16 = (@as(u16, high) << 8) | low;

                const return_addr = self.registers.pc + 2;
                self.registers.sp = self.registers.sp -% 1;
                self.bus.write(self.registers.sp, @intCast((return_addr >> 8) & 0xFF));
                self.registers.sp = self.registers.sp -% 1;
                self.bus.write(self.registers.sp, @intCast(return_addr & 0xFF));

                self.registers.pc = dst;
            },

            0xCE => { // ADC A, d8
                const d8: u8 = self.bus.read(self.registers.pc);
                self.registers.pc += 1;

                const a_val = self.registers.a();
                const carry_val: u8 = if (self.registers.get_flag(Registers.Flags.C)) 1 else 0;

                const result: u16 = @as(u16, a_val) + d8 + carry_val;
                const result_u8: u8 = @as(u8, @intCast(result & 0xFF));

                const H_check = (a_val & 0x0F) + (d8 & 0x0F) + carry_val > 0x0F;

                self.registers.set_a(result_u8);

                self.registers.set_flag(Registers.Flags.Z, result_u8 == 0);
                self.registers.set_flag(Registers.Flags.N, false);
                self.registers.set_flag(Registers.Flags.H, H_check);
                self.registers.set_flag(Registers.Flags.C, result > 0xFF);
            },

            0xE0, 0xF0, 0xE2, 0xF2 => {
                switch (opcode) {
                    0xE0 => {
                        const offset = self.bus.read(self.registers.pc);
                        self.registers.pc += 1;
                        const dst = 0xFF00 + @as(u16, offset);

                        self.bus.write(dst, self.registers.a());
                    },
                    0xF0 => {
                        const offset = self.bus.read(self.registers.pc);
                        self.registers.pc += 1;
                        const src = 0xFF00 + @as(u16, offset);

                        self.registers.set_a(self.bus.read(src));
                    },
                    0xE2 => {
                        const dst = 0xFF00 + @as(u16, self.registers.c());
                        self.bus.write(dst, self.registers.a());
                    },
                    0xF2 => {
                        const src = 0xFF00 + @as(u16, self.registers.c());
                        self.registers.set_a(self.bus.read(src));
                    },
                    else => unreachable,
                }
            },

            0xCB => { // 16-bit opcodes
                const opcode_2 = self.bus.read(self.registers.pc);
                self.registers.pc += 1;

                std.debug.print("CB Opcode: 0xCB{X:0>2}\n", .{opcode_2});

                switch (opcode_2) {
                    0x10...0x17 => {
                        const reg_idx: u3 = @intCast(opcode_2 & 0x7);
                        const og_val = self.getRegValue(reg_idx);

                        const old_carry: u8 = if (self.registers.get_flag(Registers.Flags.C)) 1 else 0;
                        const bit7_set = (og_val & 0x80) != 0;
                        const new_val = (og_val << 1) | old_carry;

                        self.setRegValue(reg_idx, new_val);

                        self.registers.set_flag(Registers.Flags.Z, new_val == 0);
                        self.registers.set_flag(Registers.Flags.N, false);
                        self.registers.set_flag(Registers.Flags.H, false);
                        self.registers.set_flag(Registers.Flags.C, bit7_set);
                    },

                    0x40...0x7F => { // BIT b, r8
                        const bit: u3 = @intCast((opcode_2 >> 3) & 0x7);
                        const reg_idx: u3 = @intCast(opcode_2 & 0x7);

                        const val = self.getRegValue(reg_idx);
                        const bit_mask = @as(u8, 1) << bit;
                        const is_set = (val & bit_mask) != 0;

                        self.registers.set_flag(Registers.Flags.Z, !is_set);
                        self.registers.set_flag(Registers.Flags.N, false);
                        self.registers.set_flag(Registers.Flags.H, true);
                    },
                    else => {
                        std.debug.print("Unknown Opcode\n", .{});
                        std.process.exit(0);
                    },
                }
            },

            else => {
                std.debug.print("Unknown Opcode 0x{X:0>2}\n", .{opcode});
                std.process.exit(0);
            },
        }
    }
};

test "LD tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();

    inline for (0..8) |dest| {
        inline for (0..8) |src| {
            // Skip 6 (HL) for now as it involves memory reads/writes
            if (dest == 6 or src == 6) continue;
            // Skip 0x76 (HALT) which is tucked inside this range
            const opcode = @as(u8, 0x40 | (dest << 3) | src);
            if (opcode == 0x76) continue;

            const test_val: u8 = @intCast(0xAA + src);
            gb.setRegValue(@intCast(src), test_val);

            gb.execute(opcode);

            try std.testing.expectEqual(test_val, gb.getRegValue(@intCast(dest)));
        }
    }
}

test "INC 8-bit register tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();

    const opcodes = [_]u8{ 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x3C }; // Removed 0x34 (HL) for now

    for (opcodes) |opcode| {
        const reg_idx: u3 = @intCast((opcode >> 3) & 0x7);

        const test_vals = [_]u8{ 0x0F, 0x1E, 0xFF }; // 15, 30, 255
        for (test_vals) |test_val| {
            gb.setRegValue(reg_idx, test_val);
            gb.registers.set_f(0);

            gb.execute(opcode);

            const expected: u8 = test_val +% 1;
            const actual = gb.getRegValue(reg_idx);

            std.testing.expectEqual(expected, actual) catch |err| {
                std.debug.print("\nFailed on Opcode 0x{X:0>2} (Register Index: {})\n", .{ opcode, reg_idx });
                return err;
            };
            try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.N));

            switch (test_val) {
                0x0F => {
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.H));
                },
                0x1E => {
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.H));
                },
                0xFF => {
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.H));
                },
                else => unreachable,
            }
        }
    }
}

test "DEC 8-bit register tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();

    const opcodes = [_]u8{ 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x3D }; // Removed 0x34 (HL) for now

    for (opcodes) |opcode| {
        const reg_idx: u3 = @intCast((opcode >> 3) & 0x7);

        const test_vals = [_]u8{ 0x01, 0x10, 0x00 }; // 1, 16, 0
        for (test_vals) |test_val| {
            gb.setRegValue(reg_idx, test_val);
            gb.registers.set_f(0);

            gb.execute(opcode);

            const expected: u8 = test_val -% 1;
            const actual = gb.getRegValue(reg_idx);

            std.testing.expectEqual(expected, actual) catch |err| {
                std.debug.print("\nFailed on Opcode 0x{X:0>2} (Register Index: {})\n", .{ opcode, reg_idx });
                return err;
            };
            try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.N));

            switch (test_val) {
                0x01 => {
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.H));
                },
                0x10 => {
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.H));
                },
                0x00 => {
                    try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.Z));
                    try std.testing.expectEqual(true, gb.registers.get_flag(Registers.Flags.H));
                },
                else => unreachable,
            }
        }
    }
}

// ADD + SUB Operation Tests (NOTE: need to implement SUB)

test "ADD Register Tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();
    gb.bus.boot_rom_enabled = false;

    // 0: basic check; 1: Half-Carry Check; 241: Carry Check & Zero Check
    const test_vals = [_]u8{ 0x00, 0x01, 0xF1 }; // 0, 1, 241
    // a_val is always the register value for A
    const a_val: u8 = 0x0F; // 15

    for (0x80..0x87) |opcode_usize| {
        const opcode: u16 = @intCast(opcode_usize);
        const reg_idx: u3 = @intCast(opcode & 0x7);

        if (opcode == 0x86) gb.registers.hl = 0xC000; // If performing HL opcode, we write the number to work_ram

        for (test_vals) |test_val| {
            gb.registers.set_a(a_val);
            gb.setRegValue(reg_idx, test_val);

            gb.execute(opcode);
            const expected: u8 = test_val +% a_val;
            const actual: u8 = gb.registers.a();

            std.testing.expectEqual(expected, actual) catch |err| {
                std.debug.print("\nFailed on Opcode 0x{X:0>2}: Expected 0x{X:0>4}, got 0x{X:0>4}\n", .{ opcode, expected, actual });
                return err;
            };
            try std.testing.expectEqual(expected == 0, gb.registers.get_flag(Registers.Flags.Z));
            try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.N));
            try std.testing.expectEqual((test_val & 0x0F) + (a_val & 0x0F) > 0x0F, gb.registers.get_flag(Registers.Flags.H));
            try std.testing.expectEqual(@as(u16, test_val) + a_val > 0xFF, gb.registers.get_flag(Registers.Flags.C));
        }
    }
}

// NOTE: Add AND and OR opcode tests below once implemented.

test "XOR Register Tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();
    const opcodes = [_]u8{ 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAF }; // Removed 0xAE (HL) for now

    // Going to test three values XOR'd against 21 (0x15)
    const a_val: u8 = 0x15;
    const test_vals = [_]u8{ 0x00, 0x0A, 0x15 };

    for (opcodes) |opcode| {
        const reg_idx: u3 = @intCast(opcode & 0x7);
        for (test_vals) |test_val| {
            gb.setRegValue(reg_idx, test_val);

            // If the opcode is XOR A, it will always equal 0;
            const expected: u8 = if (opcode != 0xAF) a_val ^ test_val else 0;
            gb.registers.set_a(a_val);

            gb.execute(opcode);

            const actual = gb.registers.a();
            std.testing.expectEqual(expected, actual) catch |err| {
                std.debug.print("\nFailed on Opcode 0x{X:0>2} (Register Index: {})\n", .{ opcode, reg_idx });
                return err;
            };
            try std.testing.expectEqual(expected == 0, gb.registers.get_flag((Registers.Flags.Z)));
            try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.N));
            try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.H));
            try std.testing.expectEqual(false, gb.registers.get_flag(Registers.Flags.C));
        }
    }
}

test "LD Register-Pair Tests" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var gb = try GameBoy.init(io, gpa, null);
    defer gb.deinit();
    gb.bus.boot_rom_enabled = false;
    gb.registers.pc = 257;

    const opcodes = [_]u8{ 0x01, 0x11, 0x21, 0x31 };
    const expected: u16 = 0xAAFF;
    const low_byte: u8 = 0xFF;
    const high_byte: u8 = 0xAA;

    for (opcodes) |opcode| {
        gb.bus.cartridge[0] = low_byte;
        gb.bus.cartridge[1] = high_byte;
        gb.registers.pc = 0x0000;

        gb.execute(opcode);
        const actual = switch (opcode) {
            0x01 => gb.registers.bc,
            0x11 => gb.registers.de,
            0x21 => gb.registers.hl,
            0x31 => gb.registers.sp,
            else => unreachable,
        };
        std.testing.expectEqual(expected, actual) catch |err| {
            std.debug.print("\nFailed on Opcode 0x{X:0>2}: Expected 0x{X:0>4}, got 0x{X:0>4}\n", .{ opcode, expected, actual });
            return err;
        };
    }
}
