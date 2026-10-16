#!/usr/bin/env python3
"""
Local Rane Sixty-Eight Firmware Patch & Unicorn ARM Emulator Simulation
Unlocks SysEx Opcode 0x01 (OLED Line 1), 0x02 (OLED Line 2), 0x7D (Custom Mode ON),
and 0x7C (Custom Mode OFF -> BPM/TIME), recalculates Rane's bit-reversed CRC32
checksums, and verifies flashing + execution locally in Unicorn.
"""
import struct
import zlib
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import (
    UC_ARM_REG_R0,
    UC_ARM_REG_R1,
    UC_ARM_REG_R2,
    UC_ARM_REG_R6,
    UC_ARM_REG_R8,
    UC_ARM_REG_R9,
    UC_ARM_REG_SP,
    UC_ARM_REG_LR,
    UC_ARM_REG_PC,
)

ORIG_FW_PATH = "/Users/henrydieckmann/Desktop/treibertemp/sixty_eight_firmware.bin"
PATCHED_FW_PATH = "/Users/henrydieckmann/.gemini/antigravity/scratch/rane-sixty-eight-driver/sixty_eight_firmware_oled_patched.bin"


def flash_to_raw(flash_addr: int) -> int:
    return flash_addr - 0x08000 + 0x03140


def write_flash_word(buf: bytearray, flash_addr: int, val: int) -> None:
    off = flash_to_raw(flash_addr)
    struct.pack_into("<I", buf, off, val)


def rane_section_crc(data: bytes) -> int:
    """Computes Rane's section CRC32: 32-bit bit-reversal of ~CRC32(data)."""
    c = (~zlib.crc32(data)) & 0xFFFFFFFF
    return int(f"{c:032b}"[::-1], 2)


def main() -> None:
    with open(ORIG_FW_PATH, "rb") as f:
        patched = bytearray(f.read())

    # 1. Patch SysEx 0x01 & 0x02 target buffers and dirty flags in Section 2 (0x08000)
    write_flash_word(patched, 0x0C808, 0x400000E7)  # Line 1 active OLED buffer
    write_flash_word(patched, 0x0C80C, 0x400000F5)  # Line 2 active OLED buffer
    write_flash_word(patched, 0x0BBC8, 0xE5C2408F)  # Set Line 1 dirty flag [0x40000176] = 0x11
    write_flash_word(patched, 0x0BC24, 0xE5C24082)  # Set Line 2 dirty flag [0x40000177] = 0x11

    # 2. Patch update_lcd() (0x08A44..0x08A60) to check [0x4000013B] (SysEx 0x7D / 0x7C mode flag)
    write_flash_word(patched, 0x08A44, 0xE3A06000)
    write_flash_word(patched, 0x08A48, 0xE3A07000)
    write_flash_word(patched, 0x08A4C, 0xE58D0018)
    write_flash_word(patched, 0x08A50, 0xE58D0014)
    write_flash_word(patched, 0x08A54, 0xE59F1C94)  # Load 0x400000E7
    write_flash_word(patched, 0x08A58, 0xE5D11054)  # Read [0x4000013B]
    write_flash_word(patched, 0x08A5C, 0xE3510000)  # Compare with 0
    write_flash_word(patched, 0x08A60, 0x1A000257)  # Return early if custom mode active

    # 3. Recompute Checksums (Section 2 -> Section 0 -> Header Payload)
    old_sec2_crc = struct.unpack_from("<I", patched, 0x0060)[0]
    new_sec2_crc = rane_section_crc(patched[0x03140:0x14340])
    struct.pack_into("<I", patched, 0x0060, new_sec2_crc)

    old_sec0_crc = struct.unpack_from("<I", patched, 0x0048)[0]
    new_sec0_crc = rane_section_crc(patched[0x0004C:0x00140])
    struct.pack_into("<I", patched, 0x0048, new_sec0_crc)

    old_hdr_crc = struct.unpack_from("<I", patched, 0x003C)[0]
    new_hdr_crc = struct.unpack(">I", struct.pack("<I", zlib.crc32(patched[0x0040:]) & 0xFFFFFFFF))[0]
    struct.pack_into("<I", patched, 0x003C, new_hdr_crc)

    with open(PATCHED_FW_PATH, "wb") as f:
        f.write(patched)

    print(f"Section 2 (0x08000) CRC: 0x{old_sec2_crc:08X} -> 0x{new_sec2_crc:08X}")
    print(f"Section 0 (0x04000) CRC: 0x{old_sec0_crc:08X} -> 0x{new_sec0_crc:08X}")
    print(f"Header Payload      CRC: 0x{old_hdr_crc:08X} -> 0x{new_hdr_crc:08X}")

    # 4. Simulate Local Flashing & Bootloader CRC Verification in Unicorn
    mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    mu.mem_map(0x00000000, 0x00100000)
    mu.mem_map(0x40000000, 0x00010000)

    mu.mem_write(0x00001000, bytes(patched[0x00140:0x03140]))
    mu.mem_write(0x00004000, bytes(patched[0x00040:0x00140]))
    mu.mem_write(0x00005000, bytes(patched[0x00140:0x03140]))
    mu.mem_write(0x00008000, bytes(patched[0x03140:0x14340]))
    mu.mem_write(0x00038000, bytes(patched[0x14340:0x24A40]))
    mu.mem_write(0x00060000, bytes(patched[0x24A40:0x29A40]))
    mu.mem_write(0x00068000, bytes(patched[0x29A40:0x3B640]))
    mu.mem_write(0x0007A000, bytes(patched[0x3B640:0x3D240]))

    print("\n--- [Unicorn] Running Firmware Hardware CRC32 Validator (0x02404) ---")

    def hook_crc(uc, address, size, user_data):
        if address == 0x02454:
            r8 = uc.reg_read(UC_ARM_REG_R8)
            r9 = uc.reg_read(UC_ARM_REG_R9)
            status = "OK" if r8 == r9 else "FAIL"
            print(f"  [CRC Check] Section 0x04000: computed=0x{r8:08X} stored=0x{r9:08X} -> {status}")
        elif address == 0x024C4:
            r6 = uc.reg_read(UC_ARM_REG_R6)
            r8 = uc.reg_read(UC_ARM_REG_R8)
            r9 = uc.reg_read(UC_ARM_REG_R9)
            status = "OK" if r8 == r9 else "FAIL"
            print(f"  [CRC Check] Section 0x{r6:05X}: computed=0x{r8:08X} stored=0x{r9:08X} -> {status}")

    h1 = mu.hook_add(UC_HOOK_CODE, hook_crc)
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00001000)
    mu.emu_start(0x00002404, 0x000024E4, timeout=0, count=5000000)
    print(f"  => Hardware Validator Return Code R0 = {mu.reg_read(UC_ARM_REG_R0)} (1 = VALID FIRMWARE!)")
    mu.hook_del(h1)

    # 5. Boot Patched Main App (Keil __decompress + OLED SPI hook)
    print("\n--- [Unicorn] Booting Patched Main Firmware & Testing OLED Display ---")
    mu.reg_write(UC_ARM_REG_R0, 0x00018788)
    mu.reg_write(UC_ARM_REG_R1, 0x40000000)
    mu.reg_write(UC_ARM_REG_R2, 0x000011C0)
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00008000)
    mu.emu_start(0x000080F4, 0x00008000, timeout=0, count=200000)

    oled_screen = {1: "", 2: ""}

    def hook_oled_spi(uc, address, size, user_data):
        if address == 0x088F0:
            line_num = uc.reg_read(UC_ARM_REG_R0)
            buf_ptr = uc.reg_read(UC_ARM_REG_R1)
            length = uc.reg_read(UC_ARM_REG_R2)
            text = bytes(uc.mem_read(buf_ptr, length)).decode("ascii", errors="replace")
            oled_screen[line_num] = text
            print(f'  [OLED Hardware Driver 0x088F0] Write Line {line_num} ({length} chars): "{text}"')
            uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))

    mu.hook_add(UC_HOOK_CODE, hook_oled_spi)

    def run_main_loop_oled_flush():
        for _ in range(2):
            mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
            mu.reg_write(UC_ARM_REG_LR, 0x00008000)
            mu.emu_start(0x0000D70C, 0x0000D8A4, timeout=0, count=50000)

    def call_update_lcd():
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(0x00008A2C, 0x00008000, timeout=0, count=200000)

    def send_sysex(payload_bytes: bytes):
        mu.mem_write(0x40001540, payload_bytes)
        mu.mem_write(0x400001D5, b"\x00")
        mu.mem_write(0x400001D4, bytes([len(payload_bytes)]))
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(0x0000B96C, 0x00008000, timeout=0, count=200000)

    print("\n1) Stock Boot Screen (update_lcd + main loop flush):")
    call_update_lcd()
    run_main_loop_oled_flush()

    print("\n2) Sending SysEx 0x7D (Custom Display Mode ON) + SysEx 0x01 & 0x02:")
    send_sysex(b"\xF0\x17\x7D\x01\xF7")
    send_sysex(b"\xF0\x17\x01HENRY'S RANE68\xF7")
    send_sysex(b"\xF0\x17\x02OLED UNLOCKED!\xF7")
    run_main_loop_oled_flush()

    print("\n3) Simulating background BPM change calling update_lcd() while 0x7D is active:")
    call_update_lcd()
    run_main_loop_oled_flush()
    print(f'   OLED still shows: Line 1="{oled_screen[1]}" | Line 2="{oled_screen[2]}"')

    print("\n4) Sending SysEx 0x7C (Custom Display Mode OFF -> back to BPM/TIME):")
    send_sysex(b"\xF0\x17\x7C\x00\xF7")
    run_main_loop_oled_flush()


if __name__ == "__main__":
    main()
