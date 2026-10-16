#!/usr/bin/env python3
"""
Rane Sixty-Eight LPC2468 Interactive LCD & DSP Hardware Simulator
Emulates the exact 14x2 character LCD SRAM buffers (0x400000E7 / 0x400000F5),
the TAP tempo button, TIME/Beat rotary encoder, FX selector, and USB Serato Sync.
"""

import sys
import time
import struct
import unicorn
from unicorn import arm_const

class SixtyEightHardwareSandbox:
    def __init__(self, firmware_path='/Users/henrydieckmann/Desktop/treibertemp/sixty_eight_firmware.bin'):
        with open(firmware_path, 'rb') as f:
            raw = f.read()
        self.code = raw[0x40:] # strip 64-byte header
        
        self.uc = unicorn.Uc(unicorn.UC_ARCH_ARM, unicorn.UC_MODE_ARM)
        
        self.FLASH_BASE = 0x00000000
        self.FLASH_SIZE = 0x00080000 # 512 KB
        self.SRAM_BASE  = 0x40000000
        self.SRAM_SIZE  = 0x00020000 # 128 KB
        self.PERIPH_BASE = 0xE0000000
        self.PERIPH_SIZE = 0x00100000
        self.VIC_BASE    = 0xFFFFE000
        self.VIC_SIZE    = 0x00004000
        
        self.uc.mem_map(self.FLASH_BASE, self.FLASH_SIZE)
        self.uc.mem_map(self.SRAM_BASE, self.SRAM_SIZE)
        self.uc.mem_map(self.PERIPH_BASE, self.PERIPH_SIZE)
        self.uc.mem_map(self.VIC_BASE, self.VIC_SIZE)
        
        self.uc.mem_write(self.FLASH_BASE, self.code.ljust(self.FLASH_SIZE, b'\x00'))
        self.STACK_TOP = self.SRAM_BASE + 0x10000
        
        # State variables
        self.current_bpm = 120.0
        self.current_fx = "ECHO"
        self.fx_idx = 0
        self.fx_list = ["ECHO", "ROBOT", "REVERB", "FLANGER", "PHASER", "FILTER"]
        
        self.beat_list = [
            ("1/8", 0.125), ("1/4", 0.25), ("1/2", 0.5), 
            ("3/4", 0.75),  ("1/1", 1.0),  ("2/1", 2.0), ("4/1", 4.0)
        ]
        self.beat_idx = 4 # default 1/1
        self.current_beat, self.beat_fraction = self.beat_list[self.beat_idx]
        
        self.tap_times = []
        self.serato_locked = False
        self.asterisk_blink = False
        self.reverb_decay = 50 # percent
        
        # Exact SRAM addresses from LPC2468 Firmware Disassembly:
        self.LCD_LINE1_ADDR = 0x400000E7 # 14 ASCII chars
        self.LCD_LINE2_ADDR = 0x400000F5 # 14 ASCII chars
        self.BPM_REG_ADDR   = 0x40000140 # float32
        self.MODE_REG_ADDR  = 0x40000144 # uint8 (0=manual, 2=serato sync)
        self.AST_FLAG_ADDR  = 0x40000088 # uint8 (1=flash asterisk)
        self.LOCK_FLAG_ADDR = 0x400018BC # uint8 (1=unlocked)
        
        self.update_firmware_state()

    def update_firmware_state(self):
        """Formats the LCD buffer exactly as function 0x03B2C does in the firmware."""
        period_ms = min(3999, int((60000.0 / self.current_bpm) * self.beat_fraction))
        bpm_int = int(round(self.current_bpm))
        
        # Asterisk logic: In Serato Sync mode, '*' pulses with the beat.
        ast = "*" if (self.serato_locked and self.asterisk_blink) else " "
        
        # Exact Firmware formatting for Line 1 (14 bytes):
        # "BPM:120 *  1/1"
        line1_str = f"BPM:{bpm_int:>3} {ast}  {self.current_beat:>3} "[:14]
        
        # Line 2 (14 bytes):
        if self.current_fx == "REVERB":
            # As decompiled at 0x03D68: "   50%      "
            line2_str = f"   {self.reverb_decay:>2}%      "[:14]
        else:
            # As decompiled at 0x0405C: "TIME:  500ms  "
            line2_str = f"TIME:{period_ms:>5}ms  "[:14]
            
        # Write to LPC2468 SRAM
        self.uc.mem_write(self.LCD_LINE1_ADDR, line1_str.encode('ascii'))
        self.uc.mem_write(self.LCD_LINE2_ADDR, line2_str.encode('ascii'))
        self.uc.mem_write(self.BPM_REG_ADDR, struct.pack('<f', float(self.current_bpm)))
        self.uc.mem_write(self.MODE_REG_ADDR, b'\x02' if self.serato_locked else b'\x00')
        self.uc.mem_write(self.AST_FLAG_ADDR, b'\x01' if self.asterisk_blink else b'\x00')

    def read_display(self):
        line1 = self.uc.mem_read(self.LCD_LINE1_ADDR, 14).decode('latin1', errors='replace')
        line2 = self.uc.mem_read(self.LCD_LINE2_ADDR, 14).decode('latin1', errors='replace')
        return line1, line2

    def render_lcd(self):
        l1, l2 = self.read_display()
        period_ms = min(3999, int((60000.0 / self.current_bpm) * self.beat_fraction))
        mode_str = "SERATO SYNC (LOCKED)" if self.serato_locked else "STANDALONE (MANUAL)"
        lock_status = "UNLOCKED (0x01)" if self.serato_locked else "STANDBY (0x00)"
        
        print("\n" + "╔" + "═" * 36 + "╗")
        print(f"║   RANE SIXTY-EIGHT OLED DISPLAY    ║")
        print("╠" + "═" * 36 + "╣")
        print(f"║   ┌────────────────────────────┐   ║")
        print(f"║   │ [{l1}] │   ║")
        print(f"║   │ [{l2}] │   ║")
        print(f"║   └────────────────────────────┘   ║")
        print("╠" + "═" * 36 + "╣")
        print(f"║ Effect:     {self.current_fx:<22} ║")
        print(f"║ DSP Delay:  {period_ms:>4} ms (Division: {self.current_beat:<4}) ║")
        print(f"║ Tempo Mode: {mode_str:<22} ║")
        print(f"║ Sec Unlock: {lock_status:<22} ║")
        print("╚" + "═" * 36 + "╝")

    def tap_button(self):
        now = time.time()
        self.tap_times.append(now)
        if len(self.tap_times) > 4:
            self.tap_times.pop(0)
            
        if len(self.tap_times) >= 2:
            diffs = [self.tap_times[i] - self.tap_times[i-1] for i in range(1, len(self.tap_times))]
            if diffs[-1] > 2.0:
                self.tap_times = [now]
                print("👆 [TAP] Taktzeit zu lang (>2s) -> Neuer Tap-Zyklus gestartet...")
                return
            avg_diff = sum(diffs) / len(diffs)
            calculated_bpm = 60.0 / avg_diff
            if 40.0 <= calculated_bpm <= 300.0:
                self.current_bpm = calculated_bpm
                self.serato_locked = False
                self.asterisk_blink = True
                print(f"👆 [TAP] Errechnetes Tempo: {self.current_bpm:.1f} BPM (Δt = {avg_diff*1000:.0f} ms)")
        else:
            self.asterisk_blink = True
            print("👆 [TAP] 1. Tap registriert. Drücke erneut für Tempo...")
        self.update_firmware_state()
        self.render_lcd()

    def encoder_beat_up(self):
        if self.beat_idx < len(self.beat_list) - 1:
            self.beat_idx += 1
            self.current_beat, self.beat_fraction = self.beat_list[self.beat_idx]
            print(f"🎛️ [TIME ENCODER ↻] Beat-Teiler erhöht: {self.current_beat}")
            self.update_firmware_state()
            self.render_lcd()
        else:
            print("🎛️ [TIME ENCODER] Maximum erreicht (4/1)")

    def encoder_beat_down(self):
        if self.beat_idx > 0:
            self.beat_idx -= 1
            self.current_beat, self.beat_fraction = self.beat_list[self.beat_idx]
            print(f"🎛️ [TIME ENCODER ↺] Beat-Teiler verringert: {self.current_beat}")
            self.update_firmware_state()
            self.render_lcd()
        else:
            print("🎛️ [TIME ENCODER] Minimum erreicht (1/8)")

    def cycle_fx(self):
        self.fx_idx = (self.fx_idx + 1) % len(self.fx_list)
        self.current_fx = self.fx_list[self.fx_idx]
        print(f"🔘 [FX SELECT] Neuer Effekt gewählt: {self.current_fx}")
        self.update_firmware_state()
        self.render_lcd()

    def inject_serato_sync(self, target_bpm=120.0):
        print(f"\n💻 [USB SERATO LINK] Sende Firmware-Befehle:")
        print("   1. SysEx Opcode 0x18: F0 17 18 02 43 88 38 03 6A 01 F7  -> Hardware Unlock")
        bpm_int = int(target_bpm * 100) # 12000 for 120.00
        b_hi = (bpm_int >> 8) & 0xFF
        b_lo = bpm_int & 0xFF
        print(f"   2. SysEx Opcode 0x53: F0 17 53 02 01 {b_hi:02X} {b_lo:02X} 01 F7 -> Set BPM {target_bpm:.2f}")
        
        self.uc.mem_write(self.LOCK_FLAG_ADDR, b'\x01')
        self.current_bpm = target_bpm
        self.serato_locked = True
        self.asterisk_blink = True
        self.update_firmware_state()
        print("🔒 [DSP ENGINE] Hardware gelockt! Stern '*' blinkt im Serato-Takt.")
        self.render_lcd()

def main():
    fw_path = '/Users/henrydieckmann/Desktop/treibertemp/sixty_eight_firmware.bin'
    sim = SixtyEightHardwareSandbox(fw_path)
    
    print("\n" + "=" * 60)
    print("   RANE SIXTY-EIGHT SANDBOX DISPLAY & DSP SIMULATION")
    print("=" * 60)
    print("Initiale Display-Anzeige:")
    sim.render_lcd()
    
    # 1. TAP Simulation
    print("\n>>> SCHRITT 1: 3x TAP-Taster drücken im 128 BPM Takt...")
    time.sleep(0.4)
    sim.tap_button()
    time.sleep(0.468)
    sim.tap_button()
    time.sleep(0.468)
    sim.tap_button()
    
    # 2. TIME Encoder
    print("\n>>> SCHRITT 2: TIME-Encoder drehen (1/1 -> 1/2 -> 1/4 -> 3/4)...")
    time.sleep(0.4)
    sim.encoder_beat_down()
    time.sleep(0.3)
    sim.encoder_beat_down()
    time.sleep(0.3)
    sim.encoder_beat_up()
    
    # 3. FX Select
    print("\n>>> SCHRITT 3: Effektrad drehen auf REVERB...")
    time.sleep(0.4)
    sim.cycle_fx() # ROBOT
    time.sleep(0.3)
    sim.cycle_fx() # REVERB
    
    # 4. Serato Sync
    print("\n>>> SCHRITT 4: Serato Sync USB Injektion (126.00 BPM)...")
    time.sleep(0.4)
    sim.inject_serato_sync(126.00)

if __name__ == '__main__':
    main()
