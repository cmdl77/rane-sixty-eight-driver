#!/usr/bin/env python3
"""
Rane Sixty-Eight Complete Firmware Flasher & Unicorn Hardware Protocol Simulator
================================================================================
Implements 100% of Rane's official SIXTY-EIGHTApi.framework USB Flash Protocol
(reverse-engineered from SIXTY-EIGHTApi, SIXTY-EIGHT.10.6.kext, Cypress FX2 8051
firmware Section 6, and LPC2468 ARM7 Bootloader Section 1 & Main App Section 2):

1. Image Validation (IsValidFirmwareImage):
   - Verifies "Copyright 2009 Rane Corporation" header, VID 0x1CC5, PID 0x0004,
     Big-Endian Payload CRC32 at 0x3C, and all 7 Section Table bit-reversed CRCs.
2. Enter Bootloader (USB EP1 Opcode 0x17):
   - Sends [0x17, seq(4), 0...] on EP1 OUT (0x01).
   - Main App (0x13C80) reads Flash Sector 4 (0x00004000), adds +1 to byte 0x0A
     (invalidating Section 0's CRC), erases & rewrites 0x00004000, and replies 0x17.
   - Cypress FX2 (0x0885) transmits the 0x17 ACK to host, disconnects USB, and
     automatically sends 0x81 over SPI to trigger the LPC2468 Watchdog Reset.
3. Bootloader Re-Enumeration (bcdDevice == 0x9900):
   - Bootloader (0x01000) sees invalid Section 0 CRC at 0x02404, stays in recovery
     mode, loads embedded FX2 rescue firmware (0x4000001B), and enumerates with
     bcdDevice = 0x9900 (Opcode 0x01 returns [0x01, seq(4), 0x01, 0x05, ver(4)]).
4. Differential Section Flashing (USB EP1 Opcode 0x15 & 0x14):
   - Reads current Section Table at 0x00004000 via Opcode 0x15 (ReadFlashBlock).
   - Flashes all changed payload sections (Entries 1..6) in 256-byte pages:
     * Chunks 0..6 (offsets 0x00..0xC0): Fire-and-forget EP1 OUT [0x14, seq(4), addr_BE(4), data(32)]
     * Chunk 7 (offset 0xE0): EP1 OUT [0x14, seq(4), addr_BE(4), data(32)] -> waits for
       EP1 IN reply [0x16, seq(4), 0x14, addr_BE(4)] after IAP Flash Page write completes.
   - Commits Entry 0 (0x00004000, the 256-byte Section Table with valid CRCs) LAST!
5. Finish & Reboot into Main App (USB EP1 Opcode 0x16):
   - Sends [0x16, seq(4), 0...] on EP1 OUT (0x01).
   - Bootloader releases lock and replies 0x16; FX2 (0x0834) transmits ACK,
     disconnects USB, and sends 0x81 over SPI to reboot into the new Main Firmware!
"""

import argparse
import struct
import sys
import time
import zlib
from typing import Dict, List, Optional, Tuple

DEFAULT_PATCHED_FW = "/Users/henrydieckmann/.gemini/antigravity/scratch/rane-sixty-eight-driver/sixty_eight_firmware_oled_patched.bin"
DEFAULT_ORIG_FW = "/Users/henrydieckmann/Desktop/treibertemp/sixty_eight_firmware.bin"


def rane_section_crc(data: bytes) -> int:
    """Computes Rane's section CRC32: 32-bit bit-reversal of ~CRC32(data)."""
    c = (~zlib.crc32(data)) & 0xFFFFFFFF
    return int(f"{c:032b}"[::-1], 2)


def validate_firmware_image(fw_bytes: bytes) -> Tuple[bool, str, List[Dict[str, int]]]:
    """Replicates Rane's official IsValidFirmwareImage(PKh, j, Pj, Pj) at 0x7AB5."""
    if len(fw_bytes) < 0x140:
        return False, "File too small (< 0x140 bytes)", []

    magic_str = fw_bytes[:32].split(b"\x00")[0].decode("ascii", errors="replace")
    if magic_str != "Copyright 2009 Rane Corporation":
        return False, f"Invalid header magic: {magic_str!r}", []

    vid = struct.unpack_from(">H", fw_bytes, 0x21)[0]
    pid = struct.unpack_from(">H", fw_bytes, 0x23)[0]
    payload_len = struct.unpack_from(">I", fw_bytes, 0x38)[0]
    stored_hdr_crc = struct.unpack_from(">I", fw_bytes, 0x3C)[0]

    if vid != 0x1CC5 or pid != 0x0004:
        return False, f"Unexpected VID:PID {vid:04X}:{pid:04X}", []

    if 0x40 + payload_len != len(fw_bytes):
        return False, f"Payload length mismatch: 0x40 + 0x{payload_len:X} != 0x{len(fw_bytes):X}", []

    calc_hdr_crc = zlib.crc32(fw_bytes[0x40:]) & 0xFFFFFFFF
    if calc_hdr_crc != stored_hdr_crc:
        return False, f"Header payload CRC mismatch: calc=0x{calc_hdr_crc:08X} != stored=0x{stored_hdr_crc:08X}", []

    sections = []
    file_cursor = 0x0040
    for idx in range(7):
        entry_off = 0x0040 + idx * 12
        addr, size, stored_crc = struct.unpack_from("<III", fw_bytes, entry_off)
        if addr == 0:
            break
        if idx == 0:
            crc_data = fw_bytes[file_cursor + 12 : file_cursor + size]
        else:
            crc_data = fw_bytes[file_cursor : file_cursor + size]
        calc_crc = rane_section_crc(crc_data)
        if calc_crc != stored_crc:
            return (
                False,
                f"Section {idx} (0x{addr:05X}) CRC mismatch: calc=0x{calc_crc:08X} != stored=0x{stored_crc:08X}",
                [],
            )
        sections.append(
            {
                "index": idx,
                "addr": addr,
                "size": size,
                "crc": stored_crc,
                "file_off": file_cursor,
            }
        )
        file_cursor += size

    return True, "OK (Header + all 7 Section CRCs verified)", sections


class UnicornRaneHardwareSimulator:
    """
    Emulates the Rane Sixty-Eight LPC2468 Flash + SRAM + Cypress FX2 USB-to-SPI bridge
    running the real ARM7 Bootloader (Section 1 at 0x01000) and Main App (Section 2 at 0x08000).
    """

    def __init__(self, initial_fw_bytes: bytes):
        from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_UNMAPPED
        from unicorn.arm_const import (
            UC_ARM_REG_R0,
            UC_ARM_REG_R1,
            UC_ARM_REG_R2,
            UC_ARM_REG_R3,
            UC_ARM_REG_SP,
            UC_ARM_REG_LR,
            UC_ARM_REG_PC,
        )

        self.UC_ARM_REG_R0 = UC_ARM_REG_R0
        self.UC_ARM_REG_R1 = UC_ARM_REG_R1
        self.UC_ARM_REG_R2 = UC_ARM_REG_R2
        self.UC_ARM_REG_R3 = UC_ARM_REG_R3
        self.UC_ARM_REG_SP = UC_ARM_REG_SP
        self.UC_ARM_REG_LR = UC_ARM_REG_LR
        self.UC_ARM_REG_PC = UC_ARM_REG_PC

        self.mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
        self.mu.mem_map(0x00000000, 0x00100000)  # 1MB Flash space
        self.mu.mem_map(0x40000000, 0x00010000)  # 64KB SRAM
        self.mu.mem_map(0xE0000000, 0x00200000)  # APB Peripherals (Watchdog, GPIO, PinConnect)
        self.mu.mem_map(0x3FFFC000, 0x00004000)  # Fast GPIO (FIO)
        self.mu.mem_map(0x7FFFF000, 0x00001000)  # LPC2468 IAP ROM at 0x7FFFFFF0
        self.mu.mem_map(0xFFFF0000, 0x00010000)  # LPC2468 VIC (0xFFFFF000)
        # Put Thumb 'BX LR' (0x4770) at 0x7FFFFFF0 so IAP calls return cleanly to ARM mode
        self.mu.mem_write(0x7FFFFFF0, struct.pack("<H", 0x4770))

        # Populate initial factory Flash from initial_fw_bytes
        _, _, secs = validate_firmware_image(initial_fw_bytes)
        # Permanent Bootloader lives at 0x00001000..0x00003FFF
        self.mu.mem_write(0x00001000, initial_fw_bytes[0x00140:0x03140])
        for s in secs:
            self.mu.mem_write(s["addr"], initial_fw_bytes[s["file_off"] : s["file_off"] + s["size"]])

        self.in_bootloader = False
        self.watchdog_triggered = False
        self.iap_calls = 0

        # Hook LPC2468 IAP entry (0x7FFFFFF0) and Watchdog / SPI stubs
        self.mu.hook_add(UC_HOOK_CODE, self._hook_code)
        self.boot_cpu()

    def _hook_code(self, uc, address, size, user_data):
        # 1. Intercept LPC2468 IAP ROM call at 0x7FFFFFF0
        if address == 0x7FFFFFF0:
            r0 = uc.reg_read(self.UC_ARM_REG_R0)
            r1 = uc.reg_read(self.UC_ARM_REG_R1)
            cmd, p0, p1, p2, p3 = struct.unpack("<IIIII", uc.mem_read(r0, 20))
            self.iap_calls += 1
            if cmd == 50:  # Prepare sector(s) for write
                uc.mem_write(r1, struct.pack("<I", 0))  # CMD_SUCCESS
            elif cmd == 51:  # Copy RAM to Flash (dst=p0, src=p1, len=p2)
                data = bytes(uc.mem_read(p1, p2))
                uc.mem_write(p0, data)
                if hasattr(uc, "ctl_remove_cache"):
                    uc.ctl_remove_cache(p0, p0 + p2)
                uc.mem_write(r1, struct.pack("<I", 0))
            elif cmd == 52:  # Erase sector(s) p0..p1
                if p0 == 4:
                    uc.mem_write(0x00004000, b"\xFF" * 0x1000)
                uc.mem_write(r1, struct.pack("<I", 0))
            elif cmd == 53:  # Blank check sector(s) p0..p1
                if p0 == 4:
                    sec_bytes = bytes(uc.mem_read(0x00004000, 0x100))
                    is_blank = all(b == 0xFF for b in sec_bytes)
                    uc.mem_write(r1, struct.pack("<I", 0 if is_blank else 8))
                else:
                    uc.mem_write(r1, struct.pack("<I", 8))  # SECTOR_NOT_BLANK
            return

        # 2. Intercept Watchdog infinite loop (0x0222C in Bootloader, 0x13FA4 in Main App)
        if address in (0x0222C, 0x13FA4):
            self.watchdog_triggered = True
            uc.emu_stop()
            return

        # 3. Skip hardware SPI bus wait loops in Main App (0x13970, 0x08798) and Bootloader (0x02270, 0x025F4, 0x0260C)
        if address in (0x13970, 0x08798, 0x15270, 0x15250, 0x025F4, 0x0260C):
            uc.reg_write(self.UC_ARM_REG_PC, uc.reg_read(self.UC_ARM_REG_LR))
            return

    def boot_cpu(self):
        """Executes the Bootloader's hardware CRC check (0x023D4) to decide Bootloader vs Main App."""
        self.watchdog_triggered = False
        # Run Bootloader Keil scatter-load (0x010B0 -> 0x02540) to init Bootloader SRAM
        self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
        self.mu.emu_start(0x000010B0, 0x00002540, timeout=0, count=200000)

        # Call Bootloader's 0x023D4 (Blank check Sector 4 + 7-Section CRC32 Validator 0x02404)
        self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
        self.mu.reg_write(self.UC_ARM_REG_LR, 0x00001000)
        self.mu.emu_start(0x000023D4, 0x00001000, timeout=0, count=5000000)
        valid_app = self.mu.reg_read(self.UC_ARM_REG_R0)

        if valid_app == 1:
            self.in_bootloader = False
            # Decompress Main App SRAM RW data (0x080F4) and zero-init Main App .bss (0x400011C0..0x40007000)
            self.mu.reg_write(self.UC_ARM_REG_R0, 0x00018788)
            self.mu.reg_write(self.UC_ARM_REG_R1, 0x40000000)
            self.mu.reg_write(self.UC_ARM_REG_R2, 0x000011C0)
            self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
            self.mu.reg_write(self.UC_ARM_REG_LR, 0x00008000)
            self.mu.emu_start(0x000080F4, 0x00008000, timeout=0, count=200000)
            self.mu.mem_write(0x400011C0, b"\x00" * (0x7000 - 0x11C0))
            # Mark USB Port A (0) as active MIDI Control Point at 0x400010F6
            self.mu.mem_write(0x400010F6, b"\x00")
        else:
            self.in_bootloader = True

    def send_usb_ep1_packet(self, usb_pkt: bytes) -> Optional[bytes]:
        """
        Simulates sending a 64-byte USB HID/EP1 OUT packet through the Cypress FX2 chip
        to either the Main App (0x139B8) or the Bootloader (0x01DFC).
        """
        assert len(usb_pkt) == 64
        cmd = usb_pkt[0]
        seq_bytes = usb_pkt[1:5]
        # Cypress FX2 strips seq_bytes (usb_pkt[1:5]) when building the 64-byte SPI RX buffer
        spi_rx = bytearray(64)
        spi_rx[0] = cmd
        spi_rx[1:60] = usb_pkt[5:64]

        if not self.in_bootloader:
            # Main App SPI handler 0x139B8 (USB-A: RX=0x40001DC4, TX=0x40001E04)
            rx_addr = struct.unpack("<I", self.mu.mem_read(0x139E0 + 8 + 0xE50, 4))[0]
            tx_addr = struct.unpack("<I", self.mu.mem_read(0x139E4 + 8 + 0xE50, 4))[0]
            self.mu.mem_write(rx_addr, bytes(spi_rx))
            self.mu.mem_write(tx_addr, b"\x00" * 64)
            self.mu.reg_write(self.UC_ARM_REG_R0, 0)  # Port A
            self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
            self.mu.reg_write(self.UC_ARM_REG_LR, 0x00008000)
            self.mu.emu_start(0x000139B8, 0x00008000, timeout=0, count=500000)
            spi_tx = bytes(self.mu.mem_read(tx_addr, 64))

            # Cypress FX2 8051 (0x0885): if reply is 0x17, send ACK and trigger 0x81 Watchdog Reset!
            if spi_tx[0] == 0x17:
                spi_rx_rst = bytearray(64)
                spi_rx_rst[0] = 0x81
                self.mu.mem_write(rx_addr, bytes(spi_rx_rst))
                self.mu.reg_write(self.UC_ARM_REG_R0, 0)
                self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
                self.mu.reg_write(self.UC_ARM_REG_LR, 0x00008000)
                self.mu.emu_start(0x000139B8, 0x00008000, timeout=0, count=500000)
                if self.watchdog_triggered:
                    self.boot_cpu()
        else:
            # Bootloader SPI handler 0x01DFC (USB-A: RX=0x40001CE4, TX=0x40001D24)
            rx_addr = 0x40001CE4
            tx_addr = 0x40001D24
            self.mu.mem_write(rx_addr, bytes(spi_rx))
            self.mu.mem_write(tx_addr, b"\x00" * 64)
            self.mu.reg_write(self.UC_ARM_REG_R0, 0)  # Port A
            self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
            self.mu.reg_write(self.UC_ARM_REG_LR, 0x00001000)
            self.mu.emu_start(0x00001DFC, 0x00001000, timeout=0, count=500000)
            spi_tx = bytes(self.mu.mem_read(tx_addr, 64))

            # Cypress FX2 8051 (0x0834): if cmd == 0x16 and reply == 0x16, trigger 0x81 Watchdog Reset!
            if cmd == 0x16 and spi_tx[0] == 0x16:
                spi_rx_rst = bytearray(64)
                spi_rx_rst[0] = 0x81
                self.mu.mem_write(rx_addr, bytes(spi_rx_rst))
                self.mu.reg_write(self.UC_ARM_REG_R0, 0)
                self.mu.reg_write(self.UC_ARM_REG_SP, 0x40007F00)
                self.mu.reg_write(self.UC_ARM_REG_LR, 0x00001000)
                self.mu.emu_start(0x00001DFC, 0x00001000, timeout=0, count=500000)
                if self.watchdog_triggered:
                    self.boot_cpu()

        # Re-insert seq_bytes into USB EP1 IN reply (Note: on 0x14 Chunk 7 ACK, Bootloader puts 0x14 in spi_tx[0])
        usb_reply = bytearray(64)
        usb_reply[0] = spi_tx[0]
        usb_reply[1:5] = seq_bytes
        usb_reply[5:64] = spi_tx[1:60]
        return bytes(usb_reply)


class LiveUSBHIDTransport:
    """
    Communicates with a physical Rane Sixty-Eight (VID 0x1CC5, PID 0x0004) on macOS
    via native IOKit IOHIDManager / IOHIDDeviceSetReport (EP1 OUT) and
    IOHIDDeviceRegisterInputReportCallback (EP1 IN), automatically handling
    USB re-enumeration between Main App mode (bcdDevice 0x0100) and
    Bootloader Recovery mode (bcdDevice 0x9900).
    """

    VID = 0x1CC5
    PID = 0x0004

    def __init__(self):
        import ctypes
        from ctypes import POINTER, CFUNCTYPE, c_bool, c_char_p, c_double, c_int, c_long, c_uint8, c_uint32, c_void_p

        self.ctypes = ctypes
        self.c_void_p = c_void_p
        self.c_int = c_int
        self.c_uint8 = c_uint8
        self.c_uint32 = c_uint32
        self.c_long = c_long

        self.iokit = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/IOKit.framework/IOKit")
        self.cf = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

        self.cf.CFRunLoopGetCurrent.restype = c_void_p
        self.cf.CFRunLoopRunInMode.argtypes = [c_void_p, c_double, c_bool]
        self.cf.CFRunLoopRunInMode.restype = c_int
        self.kCFRunLoopDefaultMode = c_void_p.in_dll(self.cf, "kCFRunLoopDefaultMode")

        self.iokit.IOHIDManagerCreate.argtypes = [c_void_p, c_uint32]
        self.iokit.IOHIDManagerCreate.restype = c_void_p
        self.iokit.IOHIDManagerSetDeviceMatching.argtypes = [c_void_p, c_void_p]
        self.iokit.IOHIDManagerOpen.argtypes = [c_void_p, c_uint32]
        self.iokit.IOHIDManagerClose.argtypes = [c_void_p, c_uint32]
        self.iokit.IOHIDManagerCopyDevices.argtypes = [c_void_p]
        self.iokit.IOHIDManagerCopyDevices.restype = c_void_p

        self.cf.CFSetGetCount.argtypes = [c_void_p]
        self.cf.CFSetGetCount.restype = c_long
        self.cf.CFSetGetValues.argtypes = [c_void_p, POINTER(c_void_p)]
        self.cf.CFRelease.argtypes = [c_void_p]

        self.iokit.IOHIDDeviceOpen.argtypes = [c_void_p, c_uint32]
        self.iokit.IOHIDDeviceOpen.restype = c_int
        self.iokit.IOHIDDeviceClose.argtypes = [c_void_p, c_uint32]
        self.iokit.IOHIDDeviceScheduleWithRunLoop.argtypes = [c_void_p, c_void_p, c_void_p]
        self.iokit.IOHIDDeviceSetReport.argtypes = [c_void_p, c_int, c_long, POINTER(c_uint8), c_long]
        self.iokit.IOHIDDeviceSetReport.restype = c_int

        self.REPORT_CB = CFUNCTYPE(None, c_void_p, c_int, c_void_p, c_int, c_uint32, POINTER(c_uint8), c_long)
        self.iokit.IOHIDDeviceRegisterInputReportCallback.argtypes = [
            c_void_p,
            POINTER(c_uint8),
            c_long,
            self.REPORT_CB,
            c_void_p,
        ]

        self.cf.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
        self.cf.CFStringCreateWithCString.restype = c_void_p
        self.iokit.IOHIDDeviceGetProperty.argtypes = [c_void_p, c_void_p]
        self.iokit.IOHIDDeviceGetProperty.restype = c_void_p
        self.cf.CFNumberGetValue.argtypes = [c_void_p, c_int, c_void_p]

        self.dev = None
        self.mgr = None
        self.in_bootloader = False
        self.rx_buf = (c_uint8 * 64)()
        self.replies: List[bytes] = []

        def _on_report(ctx, res, sender, rtype, rid, rptr, rlen):
            if rlen > 0:
                data = bytes(rptr[:rlen])
                # Ignore periodic 0x40 meter/pot reports from Main App
                if data[0] != 0x40:
                    self.replies.append(data)

        self._cb_ref = self.REPORT_CB(_on_report)
        self._connect(expected_bootloader=None, timeout_sec=10.0)

    def _get_int_prop(self, dev: int, key: str) -> int:
        k = self.cf.CFStringCreateWithCString(None, key.encode("ascii"), 0x08000100)
        num = self.iokit.IOHIDDeviceGetProperty(dev, k)
        self.cf.CFRelease(k)
        if not num:
            return 0
        val = self.c_int(0)
        self.cf.CFNumberGetValue(num, 9, self.ctypes.byref(val))
        return val.value

    def _connect(self, expected_bootloader: Optional[bool] = None, timeout_sec: float = 20.0) -> None:
        deadline = time.time() + timeout_sec
        while time.time() < deadline:
            mgr = self.iokit.IOHIDManagerCreate(None, 0)
            self.iokit.IOHIDManagerSetDeviceMatching(mgr, None)
            self.iokit.IOHIDManagerOpen(mgr, 0)
            dev_set = self.iokit.IOHIDManagerCopyDevices(mgr)
            found_dev = None
            found_ver = 0
            if dev_set:
                cnt = self.cf.CFSetGetCount(dev_set)
                if cnt > 0:
                    devs = (self.c_void_p * cnt)()
                    self.cf.CFSetGetValues(dev_set, devs)
                    for i in range(cnt):
                        vid = self._get_int_prop(devs[i], "VendorID")
                        pid = self._get_int_prop(devs[i], "ProductID")
                        ver = self._get_int_prop(devs[i], "VersionNumber")
                        if vid == self.VID and pid in (0x0004, 0x0005, 0x0008):
                            is_bl = (ver == 0x9900)
                            if expected_bootloader is None or is_bl == expected_bootloader:
                                found_dev = devs[i]
                                found_ver = ver
                                break
                self.cf.CFRelease(dev_set)
            if found_dev is not None:
                kr = self.iokit.IOHIDDeviceOpen(found_dev, 0)
                if kr == 0:
                    self.mgr = mgr
                    self.dev = found_dev
                    self.in_bootloader = (found_ver == 0x9900)
                    self.iokit.IOHIDDeviceScheduleWithRunLoop(
                        self.dev, self.cf.CFRunLoopGetCurrent(), self.kCFRunLoopDefaultMode
                    )
                    self.iokit.IOHIDDeviceRegisterInputReportCallback(
                        self.dev, self.rx_buf, 64, self._cb_ref, None
                    )
                    # Send Opcode 0x36 (InitHid) to ensure FX2 EP1 IN reporting is enabled
                    init_pkt = (self.c_uint8 * 64)(0x36, 0x00, 0x00, 0x00, 0x01, 0x01)
                    self.iokit.IOHIDDeviceSetReport(self.dev, 1, 0, init_pkt, 64)
                    self.cf.CFRunLoopRunInMode(self.kCFRunLoopDefaultMode, 0.05, False)
                    self.replies.clear()
                    return
            self.iokit.IOHIDManagerClose(mgr, 0)
            self.cf.CFRelease(mgr)
            time.sleep(0.3)
        raise RuntimeError(
            f"Timed out waiting for Rane Sixty-Eight on USB (expected_bootloader={expected_bootloader})."
        )

    def send_usb_ep1_packet(self, usb_pkt: bytes) -> Optional[bytes]:
        assert len(usb_pkt) == 64
        cmd = usb_pkt[0]
        self.replies.clear()
        pkt_arr = (self.c_uint8 * 64)(*usb_pkt)
        kr = self.iokit.IOHIDDeviceSetReport(self.dev, 1, 0, pkt_arr, 64)
        if kr != 0:
            raise RuntimeError(f"IOHIDDeviceSetReport(cmd=0x{cmd:02X}) failed with kr=0x{kr:08X}")

        # On 0x14 (WriteFlashBlock), Chunks 0..6 ((addr & 0xE0) != 0xE0) do not return an EP1 IN packet
        if cmd == 0x14:
            addr = struct.unpack_from(">I", usb_pkt, 5)[0]
            if (addr & 0xE0) != 0xE0:
                time.sleep(0.001)
                return bytes(64)

        # Wait for EP1 IN reply
        deadline = time.time() + 5.0
        reply = None
        while time.time() < deadline:
            self.cf.CFRunLoopRunInMode(self.kCFRunLoopDefaultMode, 0.01, False)
            for r in self.replies:
                if r[0] == cmd or (cmd == 0x14 and r[0] in (0x14, 0x16)):
                    reply = r
                    break
            if reply is not None:
                break

        if cmd == 0x17:
            # Mixer is disconnecting USB and rebooting into Bootloader Recovery mode (bcdDevice=0x9900)
            time.sleep(1.5)
            self._connect(expected_bootloader=True, timeout_sec=20.0)
            return reply or bytes([0x17] + [0] * 63)
        if cmd == 0x16:
            # Mixer is disconnecting USB and rebooting into Main App mode (bcdDevice=0x0100)
            time.sleep(1.5)
            self._connect(expected_bootloader=False, timeout_sec=20.0)
            return reply or bytes([0x16] + [0] * 63)

        if reply is None:
            raise RuntimeError(f"Timed out waiting for USB EP1 IN reply to opcode 0x{cmd:02X}")
        return reply


def build_usb_hid_packet(cmd: int, seq: int, payload: bytes = b"") -> bytes:
    pkt = bytearray(64)
    pkt[0] = cmd
    struct.pack_into("<I", pkt, 1, seq)
    pkt[5 : 5 + len(payload)] = payload
    return bytes(pkt)


def run_flash_protocol(target, fw_bytes: bytes) -> None:
    print("======================================================================")
    print("1. Validating Firmware File (IsValidFirmwareImage)...")
    ok, msg, new_sections = validate_firmware_image(fw_bytes)
    print(f"   -> {msg}")
    if not ok:
        sys.exit(1)

    seq = 1

    # Step 2: Query current mode/version via Opcode 0x01
    print("\n2. Querying Mixer Mode & Version (USB Opcode 0x01)...")
    reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x01, seq))
    seq += 1
    mode_byte = reply[6]
    print(f"   -> Reply: cmd=0x{reply[0]:02X}, sub=0x{mode_byte:02X} ({'Main App (0x28)' if mode_byte == 0x28 else 'Bootloader (0x05)'})")

    # Step 3: If in Main App mode, send Opcode 0x17 to invalidate Section 0 CRC and reboot into Bootloader
    if not target.in_bootloader:
        print("\n3. Sending Enter-Bootloader Command (USB Opcode 0x17)...")
        if hasattr(target, "mu"):
            sec0_crc_before = struct.unpack("<I", target.mu.mem_read(0x00004008, 4))[0]
        reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x17, seq))
        seq += 1
        if hasattr(target, "mu"):
            sec0_crc_after = struct.unpack("<I", target.mu.mem_read(0x00004008, 4))[0]
            print(f"   -> Main App modified Flash [0x4008] CRC: 0x{sec0_crc_before:08X} -> 0x{sec0_crc_after:08X} (Byte 0x400A + 1!)")
        print(f"   -> FX2 received 0x{reply[0]:02X} ACK, pulsed 0x81 Watchdog Reset -> Mixer rebooted!")
        print(f"   -> Mixer is now in Bootloader Recovery Mode: {target.in_bootloader}")

    # Verify Bootloader version via Opcode 0x01
    reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x01, seq))
    seq += 1
    print(f"   -> Bootloader Opcode 0x01 Reply: [0x{reply[0]:02X}, seq, 0x{reply[5]:02X}, 0x{reply[6]:02X}, 0x{reply[7]:02X}] (0x05 = Bootloader active!)")

    # Step 4: Read current Summary Table at 0x00004000 via Opcode 0x15 (ReadSummaryTableFromFlash)
    print("\n4. Reading Flash Section Summary Table at 0x00004000 (USB Opcode 0x15)...")
    flash_table = bytearray()
    for off in (0, 54, 108):
        count = min(54, 120 - off)
        req_payload = struct.pack(">IB", 0x00004000 + off, count)
        reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x15, seq, req_payload))
        seq += 1
        flash_table.extend(reply[10 : 10 + count])

    # Compare CRCs of Sections 1..6 (WriteFlashIfNecessary)
    print("\n5. Comparing & Flashing Modified Sections (256-Byte Pages via USB Opcode 0x14)...")
    for s in new_sections[1:]:  # Sections 1..6 first; Section 0 (0x4000) is committed LAST!
        idx = s["index"]
        f_addr, f_size, f_crc = struct.unpack_from("<III", flash_table, idx * 12)
        if f_addr == s["addr"] and f_size == s["size"] and f_crc == s["crc"]:
            print(f"   [Skip]  Section {idx} (0x{s['addr']:05X}, {s['size']} bytes): CRC 0x{s['crc']:08X} unchanged")
            continue

        print(f"   [Flash] Section {idx} (0x{s['addr']:05X}, {s['size']} bytes): CRC 0x{f_crc:08X} -> 0x{s['crc']:08X}", flush=True)
        sec_data = fw_bytes[s["file_off"] : s["file_off"] + s["size"]]
        num_pages = s["size"] // 256
        for page_idx in range(num_pages):
            page_addr = s["addr"] + page_idx * 256
            page_bytes = sec_data[page_idx * 256 : (page_idx + 1) * 256]
            for chunk_idx in range(8):
                chunk_off = chunk_idx * 32
                chunk_data = page_bytes[chunk_off : chunk_off + 32]
                payload = struct.pack(">I", page_addr + chunk_off) + chunk_data
                reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x14, seq, payload))
                seq += 1
                if chunk_idx == 7 and reply[0] not in (0x14, 0x16):
                    raise RuntimeError(f"Flash write failed at page 0x{page_addr:05X}: reply=0x{reply[0]:02X}")
            if (page_idx + 1) % 50 == 0 or (page_idx + 1) == num_pages:
                print(f"           ... Page {page_idx + 1}/{num_pages} (0x{page_addr:05X}) ACKed", flush=True)
        print(f"           -> Wrote {num_pages} pages ({s['size']} bytes) & verified {num_pages} x Page ACKs!", flush=True)

    # Step 6: Commit Section 0 (0x00004000, the 256-byte Section Table) LAST!
    s0 = new_sections[0]
    print(f"\n6. Committing Section 0 (0x00004000 Section Table, CRC=0x{s0['crc']:08X}) LAST...")
    s0_bytes = fw_bytes[s0["file_off"] : s0["file_off"] + 256]
    for chunk_idx in range(8):
        chunk_off = chunk_idx * 32
        payload = struct.pack(">I", 0x00004000 + chunk_off) + s0_bytes[chunk_off : chunk_off + 32]
        reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x14, seq, payload))
        seq += 1
        if chunk_idx == 7 and reply[0] not in (0x14, 0x16):
            raise RuntimeError("Failed to commit Section 0!")
    print("   -> Section 0 committed & ACKed!")

    # Step 7: Read-Back & Verify Section 0 (0x00004000) via USB Opcode 0x15 (and Flash 0x08A44 in simulator)
    print("\n7. Verifying Committed Flash via USB Opcode 0x15 Read-Back...")
    req_payload = struct.pack(">IB", 0x00004000, 48)
    reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x15, seq, req_payload))
    seq += 1
    sec0_readback = reply[10:58]
    print(f"   -> USB Opcode 0x15 Read-Back at 0x00004000 matches image: {sec0_readback == s0_bytes[:48]}")
    if hasattr(target, "mu"):
        flash_patch = bytes(target.mu.mem_read(0x00008A44, 32))
        expected_patch = fw_bytes[0x03140 + (0x08A44 - 0x08000) : 0x03140 + (0x08A44 - 0x08000) + 32]
        print(f"   -> LPC2468 Flash Sector at 0x00008A44 matches patched code: {flash_patch == expected_patch} ({target.iap_calls} IAP calls executed)")

    # Step 8: Send Opcode 0x16 to release lock and trigger FX2 0x81 Watchdog Reboot into Main App
    print("\n8. Sending Finish & Reboot Command (USB Opcode 0x16 -> FX2 0x81 Watchdog Reset)...")
    reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x16, seq))
    seq += 1
    print(f"   -> Mixer rebooted! In Bootloader: {target.in_bootloader} (False = Main App Running!)")

    # Verify Main App version via Opcode 0x01 after reboot
    reply = target.send_usb_ep1_packet(build_usb_hid_packet(0x01, seq))
    seq += 1
    print(
        f"   -> Post-Flash Main App Opcode 0x01 Reply: cmd=0x{reply[0]:02X}, ver={reply[5]:X}.{reply[6]:02X}, sig=0x{struct.unpack_from('>I', reply, 7)[0]:08X}"
    )

    # Step 9: Send USB Opcode 0x41 (MIDI SysEx 0x7D, 0x01, 0x02) if testing OLED-patched firmware or simulator
    if hasattr(target, "mu") or new_sections[2]["crc"] == 0xF40626B7:
        print("\n9. Testing Newly Flashed Main App via USB Opcode 0x41 (MIDI SysEx 0x7D, 0x01, 0x02)...")
        for sysex in (
            b"\xF0\x17\x52\x00\xF7",
            b"\xF0\x17\x7D\x01\xF7",
            b"\xF0\x17\x01HENRY'S RANE68\xF7",
            b"\xF0\x17\x02FLASH SUCCESS!\xF7",
        ):
            target.send_usb_ep1_packet(build_usb_hid_packet(0x41, seq, bytes([len(sysex)]) + sysex))
            seq += 1
            if hasattr(target, "mu"):
                # Run MIDI parser 0x0B96C
                target.mu.reg_write(target.UC_ARM_REG_SP, 0x40007F00)
                target.mu.reg_write(target.UC_ARM_REG_LR, 0x00008000)
                target.mu.emu_start(0x0000B96C, 0x00008000, timeout=0, count=200000)

        if hasattr(target, "mu"):
            # Also call update_lcd() (0x08A2C) to prove our 0x7D patch prevents overwriting!
            target.mu.reg_write(target.UC_ARM_REG_SP, 0x40007F00)
            target.mu.reg_write(target.UC_ARM_REG_LR, 0x00008000)
            target.mu.emu_start(0x00008A2C, 0x00008000, timeout=0, count=200000)

            line1 = bytes(target.mu.mem_read(0x400000E7, 14)).decode("ascii", errors="replace")
            line2 = bytes(target.mu.mem_read(0x400000F5, 14)).decode("ascii", errors="replace")
            print(f"   -> Active OLED Line 1 (0x400000E7): \"{line1}\"")
            print(f"   -> Active OLED Line 2 (0x400000F5): \"{line2}\"")
    print("======================================================================")


def main() -> None:
    parser = argparse.ArgumentParser(description="Rane Sixty-Eight Firmware Flasher & Simulator")
    parser.add_argument("--firmware", default=DEFAULT_PATCHED_FW, help="Path to firmware .bin file")
    parser.add_argument("--simulate", action="store_true", default=True, help="Run full USB flash protocol in Unicorn ARM simulator (default)")
    parser.add_argument("--live-usb", action="store_true", help="Flash a physical Rane Sixty-Eight connected over USB")
    parser.add_argument("--confirm", action="store_true", help="Required safety confirmation when using --live-usb")
    args = parser.parse_args()

    with open(args.firmware, "rb") as f:
        fw_bytes = f.read()

    if args.live_usb:
        if not args.confirm:
            print("ERROR: --live-usb requires --confirm to write to physical mixer Flash.")
            sys.exit(1)
        target = LiveUSBHIDTransport()
    else:
        with open(DEFAULT_ORIG_FW, "rb") as f:
            orig_bytes = f.read()
        target = UnicornRaneHardwareSimulator(orig_bytes)

    run_flash_protocol(target, fw_bytes)


if __name__ == "__main__":
    main()

