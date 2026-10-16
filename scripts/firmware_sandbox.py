#!/usr/bin/env python3
import struct
import sys
import unicorn
from unicorn import arm_const

print("=" * 70)
print("   RANE SIXTY-EIGHT LPC2468 FIRMWARE CPU SANDBOX & EMULATOR   ")
print("=" * 70)

with open('/Users/henrydieckmann/Desktop/treibertemp/sixty_eight_firmware.bin', 'rb') as f:
    raw_bin = f.read()

firmware_code = raw_bin[0x40:]
print(f"Firmware payload loaded: {len(firmware_code)} bytes")

uc = unicorn.Uc(unicorn.UC_ARCH_ARM, unicorn.UC_MODE_ARM)

FLASH_BASE = 0x00000000
FLASH_SIZE = 0x00080000  # 512 KB
SRAM_BASE  = 0x40000000
SRAM_SIZE  = 0x00020000  # 128 KB
PERIPH_BASE = 0xE0000000
PERIPH_SIZE = 0x00100000 # 1 MB
VIC_BASE    = 0xFFFFE000 # LPC2468 VIC / System Control
VIC_SIZE    = 0x00004000

uc.mem_map(FLASH_BASE, FLASH_SIZE)
uc.mem_map(SRAM_BASE, SRAM_SIZE)
uc.mem_map(PERIPH_BASE, PERIPH_SIZE)
uc.mem_map(VIC_BASE, VIC_SIZE)

# Write firmware to Flash
uc.mem_write(FLASH_BASE, firmware_code.ljust(FLASH_SIZE, b'\x00'))

# Set up Stack Pointer
STACK_TOP = SRAM_BASE + 0x10000
uc.reg_write(arm_const.UC_ARM_REG_SP, STACK_TOP)

# Track memory states
def hook_mem_write(uc, access, address, size, value, user_data):
    if address == 0x40000140:
        fval = struct.unpack('<f', struct.pack('<I', value & 0xFFFFFFFF))[0]
        print(f"\n🎯 [LCD DSP UPDATE] BPM REGISTER WRITTEN: {fval:.2f} BPM (0x{value:08X})")
    elif address == 0x40000088:
        print(f"\n✨ [LCD DSP UPDATE] Serato Mode 1 / Asterisk Flasher: {value} (1=Active / Blinking)")
    elif address == 0x400018BC:
        print(f"\n🔓 [SECURITY CHECK] Hardware Lock 0x400018BC changed to: {value}")
    elif address == 0x400010F6:
        print(f"🎛️ [CONTROL POINT] Port assigned to: {value} (0=Port A, 1=Port B)")
    elif address == 0x400001EC:
        print(f"🔌 [HOST CONNECT] Port A Host Connected Flag set to: {value}")
    elif address == 0x400001EF:
        print(f"🎛️ [SOFTWARE MODE] DSP Software Mode Flag set to: {value}")

uc.hook_add(unicorn.UC_HOOK_MEM_WRITE, hook_mem_write)

# USB Endpoint Buffer Addresses (from LPC2468 firmware disassembly):
RX_BUF_PORT_A = 0x40001240
TX_BUF_PORT_A = 0x40001280

# Entry point of USB endpoint handler
USB_HANDLER_ENTRY = 0x0EAB8
USB_HANDLER_EXIT  = 0x0F33C

# Entry point of SysEx FIFO parser
SYSEX_PARSER_ENTRY = 0x06B20
SYSEX_PARSER_EXIT  = 0x08078

def run_usb_packet(packet_bytes, label=""):
    print(f"\n--- [EMULATOR FEED] Sending USB Packet ({label}): {[hex(b) for b in packet_bytes]} ---")
    
    # 1. Write packet into RX buffer (64 bytes)
    pkt_buf = bytearray(64)
    for i in range(min(len(packet_bytes), 64)):
        pkt_buf[i] = packet_bytes[i]
    uc.mem_write(RX_BUF_PORT_A, bytes(pkt_buf))
    
    # 2. Setup registers for USB Handler
    # r0 = 0 (Port A)
    uc.reg_write(arm_const.UC_ARM_REG_R0, 0)
    uc.reg_write(arm_const.UC_ARM_REG_SP, STACK_TOP)
    uc.reg_write(arm_const.UC_ARM_REG_LR, USB_HANDLER_EXIT)
    
    # 3. Emulate USB Handler until return
    try:
        uc.emu_start(USB_HANDLER_ENTRY, USB_HANDLER_EXIT, timeout=500000, count=5000)
    except Exception as e:
        pc = uc.reg_read(arm_const.UC_ARM_REG_PC)
        print(f"⚠️ Emulator stopped at PC=0x{pc:05X}: {e}")
        
    # Read response packet from TX buffer
    tx_data = uc.mem_read(TX_BUF_PORT_A, 16)
    print(f"   Mixer TX Response: {[hex(b) for b in tx_data[:8]]}")

def run_sysex_parser():
    print("\n--- [EMULATOR RUN] Executing SysEx FIFO Parser ---")
    uc.reg_write(arm_const.UC_ARM_REG_SP, STACK_TOP)
    uc.reg_write(arm_const.UC_ARM_REG_LR, SYSEX_PARSER_EXIT)
    try:
        uc.emu_start(SYSEX_PARSER_ENTRY, SYSEX_PARSER_EXIT, timeout=500000, count=10000)
    except Exception as e:
        pc = uc.reg_read(arm_const.UC_ARM_REG_PC)
        print(f"⚠️ SysEx Parser stopped at PC=0x{pc:05X}: {e}")

# -----------------------------------------------------------
# Test Sequence in Sandbox:
# -----------------------------------------------------------

# Test 1: Report 0x83 (Host Connect Port A)
run_usb_packet([0x83, 0x01], "Report 0x83 Connect")

# Test 2: Report 0x82 (Software Mode Active)
run_usb_packet([0x82, 0x01], "Report 0x82 Software Mode")

# Test 3: Opcode 0x18 (Magic Key Unlock)
sysex_unlock = [
    0x41, 0x0B, 0xF0, 0x17, 0x18,
    0x03, 0x59, 0x10, 0x14, 0x03, 0x2B, 0x28,
    0xF7
]
run_usb_packet(sysex_unlock, "Opcode 0x18 Unlock")

# Run SysEx parser to process the unlock
run_sysex_parser()

# Test 4: Opcode 0x52 (Set Control Point & BPM 120.00 = 12000 = 0x2EE0)
sysex_bpm = [
    0x41, 0x09, 0xF0, 0x17, 0x52,
    0x01, 0x00, 0x2E, 0xE0, 0x01,
    0xF7
]
run_usb_packet(sysex_bpm, "Opcode 0x52 Set BPM 120")

# Run SysEx parser to process BPM and update LCD
run_sysex_parser()

print("\n" + "=" * 70)
print("  SANDBOX RUN COMPLETE  ")
print("=" * 70)
