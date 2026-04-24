const std = @import("std");

pub const Registers = struct {
    af: u16 = 0x0000,
    bc: u16 = 0x0000,
    de: u16 = 0x0000,
    hl: u16 = 0x0000,
    sp: u16 = 0x0000,
    pc: u16 = 0x0000,

    pub fn a(self: Registers) u8 {
        return @intCast(self.af >> 8);
    }

    pub fn f(self: Registers) u8 {
        return @intCast(self.af & 0xFF);
    }

    pub fn set_a(self: *Registers, val: u8) void {
        self.af = (self.af & 0x00FF) | (@as(u16, val) << 8);
    }

    pub fn set_f(self: *Registers, val: u8) void {
        self.af = (self.af & 0xFF00) | (val & 0xF0);
    }

    pub fn b(self: Registers) u8 {
        return @intCast(self.bc >> 8);
    }

    pub fn c(self: Registers) u8 {
        return @intCast(self.bc & 0xFF);
    }

    pub fn set_b(self: *Registers, val: u8) void {
        self.bc = (self.bc & 0x00FF) | (@as(u16, val) << 8);
    }

    pub fn set_c(self: *Registers, val: u8) void {
        self.bc = (self.bc & 0xFF00) | val;
    }

    pub fn d(self: Registers) u8 {
        return @intCast(self.de >> 8);
    }

    pub fn e(self: Registers) u8 {
        return @intCast(self.de & 0xFF);
    }

    pub fn set_d(self: *Registers, val: u8) void {
        self.de = (self.de & 0x00FF) | (@as(u16, val) << 8);
    }

    pub fn set_e(self: *Registers, val: u8) void {
        self.de = (self.de & 0xFF00) | val;
    }

    pub fn h(self: Registers) u8 {
        return @intCast(self.hl >> 8);
    }

    pub fn l(self: Registers) u8 {
        return @intCast(self.hl & 0xFF);
    }

    pub fn set_h(self: *Registers, val: u8) void {
        self.hl = (self.hl & 0x00FF) | (@as(u16, val) << 8);
    }

    pub fn set_l(self: *Registers, val: u8) void {
        self.hl = (self.hl & 0xFF00) | val;
    }

    pub const Flags = struct {
        pub const Z: u8 = 0x80;
        pub const N: u8 = 0x40;
        pub const H: u8 = 0x20;
        pub const C: u8 = 0x10;
    };

    pub fn set_flag(self: *Registers, flag_mask: u8, value: bool) void {
        const f_val = self.f();
        if (value) {
            self.set_f(f_val | flag_mask);
        } else {
            self.set_f(f_val & ~flag_mask);
        }
    }

    pub fn get_flag(self: *Registers, flag_mask: u8) bool {
        return (self.f() & flag_mask) != 0;
    }
};
