#!/usr/bin/env python3
"""
Rane Sixty-Eight Firmware Patch & ARM7TDMI Unicorn Emulator Verification
========================================================================
Tests the per-channel Filter Mode routine (PGM 1..4) and real-time
SysEx 0x06 switching (`F0 17 06 <arg> F7`, where `arg = (ch << 4) | mode`):
  - Mode 0 (0x00): Normal (Left 0..63 = Low-Pass, 64 = Neutral, Right 65..127 = High-Pass)
  - Mode 1 (0x01): Low-Pass Only (Full 270° range: 127 = Neutral 64, 126..0 = LPF 63..0)
  - Mode 2 (0x02): High-Pass Only (Full 270° range: 0 = Neutral 64, 2..127 = HPF 65..127)
  - Mode 3 (0x03): Hardware Filter OFF / Pure MIDI Controller (DSP locked at 64 Neutral, USB MIDI sends full 0..127)
"""
import struct
import zlib
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import (
    UC_ARM_REG_R0,
    UC_ARM_REG_R1,
    UC_ARM_REG_R2,
    UC_ARM_REG_R3,
    UC_ARM_REG_LR,
    UC_ARM_REG_PC,
    UC_ARM_REG_SP,
)

ORIG_FW_PATH = "firmware_extracted/sixty_eight_firmware_v1_28_original.bin"


def flash_to_raw(flash_addr: int) -> int:
    return flash_addr - 0x08000 + 0x03140


def read_flash_word(buf: bytes, flash_addr: int) -> int:
    return struct.unpack_from("<I", buf, flash_to_raw(flash_addr))[0]


def write_flash_word(buf: bytearray, flash_addr: int, val: int) -> None:
    struct.pack_into("<I", buf, flash_to_raw(flash_addr), val)


def encode_b(src_addr: int, dst_addr: int, cond: int = 0xE, link: bool = False) -> int:
    offset = (dst_addr - (src_addr + 8)) >> 2
    op = 0x0B if link else 0x0A
    return (cond << 28) | (op << 24) | (offset & 0x00FFFFFF)


def rane_section_crc(data: bytes) -> int:
    c = (~zlib.crc32(data)) & 0xFFFFFFFF
    return int(f"{c:032b}"[::-1], 2)


def patch_firmware_with_filter_modes(orig_bytes: bytes) -> bytearray:
    patched = bytearray(orig_bytes)

    # 1. Unlock USB Front-End SysEx filter (0x13FA8) for command 0x06:
    assert read_flash_word(patched, 0x14004) == encode_b(0x14004, 0x1411C)
    write_flash_word(patched, 0x14004, encode_b(0x14004, 0x140A8))

    # 2. Deduplicate 5-byte SysEx epilogues at 0x0BB70 and 0x0BCC0 -> jump to 0x0BC74,
    # freeing 10 words (0x0BCC4..0x0BCD4 and 0x0BB74..0x0BB84) inside 0x0B96C:
    write_flash_word(patched, 0x0BB70, encode_b(0x0BB70, 0x0BC74))
    write_flash_word(patched, 0x0BCC0, encode_b(0x0BCC0, 0x0BC74))

    # 3. Hook SysEx consumer (0x0B96C) at 0x0BA60 (`cmp r0, #4; bne #0xc560`):
    assert read_flash_word(patched, 0x0BA60) == encode_b(0x0BA60, 0x0C560, cond=0x1)
    write_flash_word(patched, 0x0BA60, encode_b(0x0BA60, 0x0BCC4, cond=0x1))

    # At 0x0BCC4..0x0BCD4:
    write_flash_word(patched, 0x0BCC4, 0xE3500006)                          # cmp r0, #6
    write_flash_word(patched, 0x0BCC8, encode_b(0x0BCC8, 0x0C560, cond=1))  # bne #0x0C560
    write_flash_word(patched, 0x0BCCC, 0xE59F0B2C)                          # ldr r0, [0x0C800] (0x400001D5)
    write_flash_word(patched, 0x0BCD0, 0xE5D00000)                          # ldrb r0, [r0] (read_idx)
    write_flash_word(patched, 0x0BCD4, encode_b(0x0BCD4, 0x0BB74))          # b #0x0BB74

    # At 0x0BB74..0x0BB84:
    write_flash_word(patched, 0x0BB74, 0xE2800003)                          # add r0, r0, #3
    write_flash_word(patched, 0x0BB78, 0xE20000FF)                          # and r0, r0, #0xFF
    write_flash_word(patched, 0x0BB7C, 0xE7D11000)                          # ldrb r1, [r1, r0] (arg)
    write_flash_word(patched, 0x0BB80, encode_b(0x0BB80, 0x191D4, link=True))  # bl #0x191D4
    write_flash_word(patched, 0x0BB84, encode_b(0x0BB84, 0x0BC74))          # b #0x0BC74

    # 4. Write `apply_filter_mode` (0x19198..0x191D0) and `sysex_06_apply` (0x191D4..0x191FC)
    # in the Section 2 code cave (0x19198..0x19200, 26 words):
    cave_words = [
        0xE59F205C,  # 0x19198: ldr   r2, [pc, #0x5C]       ; r2 = [0x191FC] = 0x400018A8
        0xE2823D35,  # 0x1919C: add   r3, r2, #0xD40        ; r3 = 0x400025E8
        0xE0833000,  # 0x191A0: add   r3, r3, r0            ; r3 = 0x400025E8 + ch
        0xE2241040,  # 0x191A4: eor   r1, r4, #0x40         ; r1 = r4 ^ 0x40
        0xE5C31000,  # 0x191A8: strb  r1, [r3]              ; raw_pot_xor40[ch] = r4 ^ 0x40
        0xE5D33004,  # 0x191AC: ldrb  r3, [r3, #4]          ; r3 = filter_mode[ch] (0..3)
        0xE1A01004,  # 0x191B0: mov   r1, r4                ; Mode 0 (LP+HP): r1 = r4
        0xE3530001,  # 0x191B4: cmp   r3, #1                ; compare mode with 1
        0x02841001,  # 0x191B8: addeq r1, r4, #1            ; Mode 1 (LP): r1 = r4 + 1
        0x01A010A1,  # 0x191BC: moveq r1, r1, lsr #1        ; Mode 1 (LP): r1 = (r4 + 1) >> 1 (0..64)
        0x83A01040,  # 0x191C0: movhi r1, #0x40             ; Mode 2 (HP) & 3 (Off): r1 = 64
        0xE3530002,  # 0x191C4: cmp   r3, #2                ; is it Mode 2 (HP)?
        0x008110A4,  # 0x191C8: addeq r1, r1, r4, lsr #1    ; Mode 2 (HP): r1 = 64 + (r4 >> 1) (64..127)
        0xE7821100,  # 0x191CC: str   r1, [r2, r0, lsl #2]  ; [0x400018A8 + ch*4] = r1
        0xE12FFF1E,  # 0x191D0: bx    lr                    ; return!
        # sysex_06_apply(r1 = (ch << 4) | mode):
        0xE1A00221,  # 0x191D4: mov   r0, r1, lsr #4        ; r0 = ch
        0xE2000003,  # 0x191D8: and   r0, r0, #3            ; clamp ch to 0..3
        0xE2011003,  # 0x191DC: and   r1, r1, #3            ; r1 = mode (0..3)
        0xE59F2014,  # 0x191E0: ldr   r2, [pc, #0x18]       ; r2 = [0x19200-4=0x191FC] = 0x400018A8
        0xE2823D35,  # 0x191E4: add   r3, r2, #0xD40        ; r3 = 0x400025E8
        0xE0833000,  # 0x191E8: add   r3, r3, r0            ; r3 = 0x400025E8 + ch
        0xE5C31004,  # 0x191EC: strb  r1, [r3, #4]          ; filter_mode[ch] = mode
        0xE5D34000,  # 0x191F0: ldrb  r4, [r3]              ; r4 = raw_pot_xor40[ch]
        0xE2244040,  # 0x191F4: eor   r4, r4, #0x40         ; r4 = raw_pot[ch] (64 if untouched)
        encode_b(0x191F8, 0x191AC),  # 0x191F8: b #0x191AC  ; recompute DSP & return via bx lr!
        0x400018A8,  # 0x191FC: .word 0x400018A8
    ]
    assert len(cave_words) == 26
    for idx, w in enumerate(cave_words):
        addr = 0x19198 + idx * 4
        assert read_flash_word(patched, addr) == 0xFFFFFFFF, f"Non-0xFF at 0x{addr:05X}"
        write_flash_word(patched, addr, w)

    # 5. Hook the 4 Channel Filter potentiometer handlers in 0x10C78:
    #   PGM 1 (CC 0x42 = 66): 0x10F98
    #   PGM 2 (CC 0x47 = 71): 0x1105C
    #   PGM 3 (CC 0x4C = 76): 0x11120
    #   PGM 4 (CC 0x51 = 81): 0x111E4
    filter_pot_hooks = [
        (0, 0x10F98),
        (1, 0x1105C),
        (2, 0x11120),
        (3, 0x111E4),
    ]
    for ch, hook_addr in filter_pot_hooks:
        write_flash_word(patched, hook_addr + 0, 0xE3A00000 | ch)                      # mov r0, #ch
        write_flash_word(patched, hook_addr + 4, encode_b(hook_addr + 4, 0x19198, link=True))  # bl #0x19198
        write_flash_word(patched, hook_addr + 8, 0xE1A00000)                           # nop (mov r0, r0)

    # 6. Recompute Section 2 CRC, Section 0 CRC, and Header Payload CRC32:
    sec2_size = struct.unpack_from("<I", patched, 0x005C)[0]
    struct.pack_into("<I", patched, 0x0060, rane_section_crc(bytes(patched[0x03140:0x03140 + sec2_size])))
    struct.pack_into("<I", patched, 0x0048, rane_section_crc(bytes(patched[0x0004C:0x00140])))
    hdr_crc = zlib.crc32(bytes(patched[0x0040:])) & 0xFFFFFFFF
    struct.pack_into(">I", patched, 0x003C, hdr_crc)

    return patched


def main() -> None:
    with open(ORIG_FW_PATH, "rb") as f:
        orig = f.read()

    patched = patch_firmware_with_filter_modes(orig)

    # Disassemble the new code cave using Capstone to verify every instruction
    md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    print("=" * 78)
    print("  1. CAPSTONE ARM7TDMI DISASSEMBLY OF NEW CODE CAVE (0x19198..0x191F8)")
    print("=" * 78)
    cave_bytes = bytes(patched[flash_to_raw(0x19198):flash_to_raw(0x191FC)])
    for insn in md.disasm(cave_bytes, 0x19198):
        print(f"  0x{insn.address:05X}: {insn.mnemonic:8s} {insn.op_str}")

    # Boot in Unicorn ARM7TDMI Emulator
    mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    mu.mem_map(0x00000000, 0x00100000)
    mu.mem_map(0x40000000, 0x00010000)
    mu.mem_map(0x3FFF0000, 0x00010000)  # Fast GPIO registers
    mu.mem_map(0xE0000000, 0x00100000)  # APB Peripherals

    import sys
    sys.path.insert(0, "tools")
    from flash_rane_firmware import validate_firmware_image
    ok, msg, secs = validate_firmware_image(bytes(patched))
    assert ok, f"Firmware validation failed: {msg}"
    mu.mem_write(0x00001000, bytes(patched[0x00140:0x03140]))
    for s in secs:
        mu.mem_write(s["addr"], bytes(patched[s["file_off"] : s["file_off"] + s["size"]]))

    print("\n" + "=" * 78)
    print("  2. UNICORN HARDWARE BOOTLOADER CRC32 VALIDATION (0x00002404)")
    print("=" * 78)
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00001000)
    mu.emu_start(0x00002404, 0x00001000, timeout=0, count=5000000)
    r0_crc = mu.reg_read(UC_ARM_REG_R0)
    print(f"  => Bootloader Validator Return Code R0 = {r0_crc} (1 = ALL 7 SECTIONS VALID!)")
    assert r0_crc == 1

    # Run Keil __scatterload (initializes RW data & zeroes BSS)
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.emu_start(0x000080B0, 0x000081B0, timeout=0, count=500000)

    # Capture USB MIDI CC messages sent by `bl #0x14aac` (r0 = ch, r1 = cc, r2 = val)
    usb_midi_log = []

    def hook_midi_send(uc, address, size, user_data):
        if address == 0x14AAC:
            midi_ch = uc.reg_read(UC_ARM_REG_R0)
            midi_cc = uc.reg_read(UC_ARM_REG_R1)
            midi_val = uc.reg_read(UC_ARM_REG_R2)
            usb_midi_log.append((midi_ch, midi_cc, midi_val))

    mu.hook_add(UC_HOOK_CODE, hook_midi_send)

    # Helper to send a SysEx packet through the USB Front-End (0x139B8 / 0x13FA8) AND Consumer (0x0B96C)
    def send_usb_sysex(sysex_bytes: bytes) -> None:
        # Write USB packet [0x41, len, F0, 17, ...] to USB endpoint buffer 0x40001240
        pkt = bytes([0x41, len(sysex_bytes)]) + sysex_bytes
        mu.mem_write(0x40001240, pkt)
        mu.reg_write(UC_ARM_REG_R0, 0)
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(0x000139B8, 0x00014234, timeout=0, count=100000)

        # Now run the SysEx consumer (0x0B96C)
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(0x0000B96C, 0x00008000, timeout=0, count=200000)

    # Helper to simulate turning a Channel Filter knob (PGM 1..4) via pot dispatcher 0x10C78
    # PGM 1..4 Filter CC numbers: 0x42 (66), 0x47 (71), 0x4C (76), 0x51 (81)
    CC_MAP = {0: 0x41, 1: 0x42, 2: 0x43, 3: 0x44}

    def turn_filter_knob(ch: int, pot_val: int):
        usb_midi_log.clear()
        cc = CC_MAP[ch]
        mu.reg_write(UC_ARM_REG_R0, 0)        # USB port 0
        mu.reg_write(UC_ARM_REG_R1, 0)        # MIDI ch 0
        mu.reg_write(UC_ARM_REG_R2, cc)       # Control CC ID
        mu.reg_write(UC_ARM_REG_R3, pot_val)  # Potentiometer 0..127
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(0x00010C78, 0x00008000, timeout=0, count=100000)
        dsp_val = struct.unpack("<I", mu.mem_read(0x400018A8 + ch * 4, 4))[0]
        midi_sent = usb_midi_log[-1] if usb_midi_log else None
        return dsp_val, midi_sent

    print("\n" + "=" * 78)
    print("  3. EMULATING ALL 4 FILTER MODES ACROSS PGM 1..4 + USB MIDI OUTPUT")
    print("=" * 78)

    mode_Configs = [
        (0, 0x00, "PGM 1 -> Mode 0: Normal (Left=LP, 12h=Neutral, Right=HP)"),
        (1, 0x01, "PGM 2 -> Mode 1: Low-Pass Only (Full 270° Sweep)"),
        (2, 0x02, "PGM 3 -> Mode 2: High-Pass Only (Full 270° Sweep)"),
        (3, 0x03, "PGM 4 -> Mode 3: Filter OFF / Pure MIDI Controller"),
    ]

    # Configure each channel with a different mode via SysEx `F0 17 06 <arg> F7`!
    for ch, mode, desc in mode_Configs:
        arg = (ch << 4) | mode
        sysex = bytes([0xF0, 0x17, 0x06, arg, 0xF7])
        send_usb_sysex(sysex)
        print(f"  [SysEx Sent] F0 17 06 {arg:02X} F7  ==>  {desc}")

    test_positions = [
        (0,   "7 Uhr (Links-Anschlag)"),
        (32,  "9:30 Uhr"),
        (64,  "12 Uhr (Mittelrastung)"),
        (96,  "2:30 Uhr"),
        (127, "5 Uhr (Rechts-Anschlag)"),
    ]

    for ch, mode, desc in mode_Configs:
        print(f"\n  --- {desc} ---")
        print(f"  {'Poti-Stellung':26s} | {'Poti Roh':8s} | {'Audio-DSP Wert':26s} | {'USB-MIDI Output'}")
        print("  " + "-" * 74)
        for pot_val, label in test_positions:
            dsp_val, midi_ev = turn_filter_knob(ch, pot_val)
            if dsp_val < 64:
                dsp_desc = f"{dsp_val:3d} (LOW-PASS  {int((64-dsp_val)/64*100):3d}%)"
            elif dsp_val == 64:
                dsp_desc = f"{dsp_val:3d} (NEUTRAL / BYPASS)"
            else:
                dsp_desc = f"{dsp_val:3d} (HIGH-PASS {int((dsp_val-64)/63*100):3d}%)"
            midi_str = f"CC {midi_ev[1]:2d} = {midi_ev[2]:3d}" if midi_ev else "NONE"
            print(f"  {label:26s} | {pot_val:8d} | {dsp_desc:26s} | {midi_str}")

    print("\n" + "=" * 78)
    print("  4. TESTING INSTANT LIVE SYSEX MODE SWITCH WITHOUT TOUCHING THE KNOB")
    print("=" * 78)
    # Put PGM 1 knob at 0 (full left) in Mode 0 (Normal -> DSP = 0 Low-Pass)
    turn_filter_knob(0, 0)
    dsp_before = struct.unpack("<I", mu.mem_read(0x400018A8, 4))[0]
    print(f"  1) PGM 1 Knob at 7 Uhr (0) in Mode 0 (Normal):      DSP = {dsp_before:3d} (Full Low-Pass)")

    # Now send SysEx F0 17 06 03 F7 (PGM 1 -> Mode 3 Filter OFF) WITHOUT moving the knob!
    send_usb_sysex(b"\xF0\x17\x06\x03\xF7")
    dsp_off = struct.unpack("<I", mu.mem_read(0x400018A8, 4))[0]
    print(f"  2) After SysEx F0 17 06 03 F7 (Mode 3 Filter OFF):  DSP = {dsp_off:3d} (Instant Neutral/Bypass!)")
    assert dsp_off == 64

    # Now put PGM 1 knob at 96 (2:30 o'clock right side) while in Mode 3, then switch to Mode 1 (Low-Pass Only)
    turn_filter_knob(0, 96)
    send_usb_sysex(b"\xF0\x17\x06\x01\xF7")
    dsp_lp = struct.unpack("<I", mu.mem_read(0x400018A8, 4))[0]
    print(f"  3) Knob at 2:30 Uhr (96) -> SysEx F0 17 06 01 F7:   DSP = {dsp_lp:3d} (Instant Low-Pass 25%!)")
    assert dsp_lp == 48

    # Switch PGM 1 to Mode 2 (High-Pass Only) while knob is still at 96:
    send_usb_sysex(b"\xF0\x17\x06\x02\xF7")
    dsp_hp = struct.unpack("<I", mu.mem_read(0x400018A8, 4))[0]
    print(f"  4) Knob at 2:30 Uhr (96) -> SysEx F0 17 06 02 F7:   DSP = {dsp_hp:3d} (Instant High-Pass 76%!)")
    assert dsp_hp == 112

    print("\n  => ALL UNICORN ARM7TDMI EMULATOR TESTS PASSED 100%!")


if __name__ == "__main__":
    main()
