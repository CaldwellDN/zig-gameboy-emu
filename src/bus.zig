pub const Bus = struct {
    const boot_rom = @embedFile("dmg_boot.bin");
    cartridge: []u8,
    vram: [0x2000]u8,
    work_ram: [0x2000]u8,
    high_ram: [128]u8,
    boot_rom_enabled: bool = true,

    pub fn read(self: *Bus, address: u16) u8 {
        if (self.boot_rom_enabled and address < 0x0100) {
            return boot_rom[address];
        }
        return switch (address) {
            0x0000...0x7FFF => if (address < self.cartridge.len) self.cartridge[address] else 0xFF,
            0x8000...0x9FFF => self.vram[address - 0x8000],
            0xA000...0xBFFF => 0,
            0xC000...0xDFFF => self.work_ram[address - 0xC000],
            0xE000...0xFDFF => self.work_ram[address - 0xE000],
            0xFE00...0xFE9F => 0,
            0xFF80...0xFFFE => self.high_ram[address - 0xFF80],
            else => 0xFF,
        };
    }
    pub fn write(self: *Bus, addr: u16, val: u8) void {
        switch (addr) {
            0x8000...0x9FFF => self.vram[addr - 0x8000] = val,
            0xC000...0xDFFF => self.work_ram[addr - 0xC000] = val,
            0xFF00...0xFF49, 0xFF51...0xFF7F, 0xFFFF => {
                // The void for now, will be implemented later
            },
            0xFF80...0xFFFE => self.high_ram[addr - 0xFF80] = val,
            0xFF50 => if (val != 0) {
                self.boot_rom_enabled = false;
            },
            else => {}, // Ignore writes to ROM or unimplemented areas
        }
    }
};
