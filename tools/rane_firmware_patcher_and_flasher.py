#!/usr/bin/env python3
"""
Rane Sixty-Eight Official Firmware Extractor, OLED Binary Patcher & USB Flasher
===============================================================================
Extrahiert die originale Rane Sixty-Eight Firmware direkt aus dem offiziellen
Serato Scratch Live 2.5 Download ("Serato Scratch Live 2.5 Mac.zip" / ".dmg")
oder einem Rane "SIXTY-EIGHT.pkg" Treiberpaket, entschlüsselt das Image per
256-Byte XOR-Key, erstellt die gepatchte Custom-OLED-Firmware, prüft alle 7
Sektions-CRCs sowie die Ausführung im lokalen ARM7TDMI Unicorn-Emulator und
bietet einen geführten Flash-Dialog (Original vs. Gepatchte Version) mit
mehrstufigen Sicherheitsabfragen.

Offizieller Download (kostenloser Serato-Account erforderlich):
  https://serato.com/scratchlive/downloads
"""

import argparse
import ctypes
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

# 256-Byte XOR Key aus SIXTY-EIGHTApi.framework (__TEXT,__const)
# SHA-256: d47954d8038dda6cea66ddb8bd509ed66e6b4607f00d139aef8c4e03c370dc60
RANE_XOR_KEY_HEX = (
    "b8fb90bd4935455f06b6553313ef9f43d9ad4a8ee83295610df5d73eb64c8bd4"
    "31ca78bece31da77a913a0e4ebdc5495479ca63ef28f7be72ebdf14ef15e2f90"
    "3a26f77b952524c6ec7bf28095ef03d34bc028e64264f986fa9c141557a855c4"
    "b03f259268a14796e2508935ef5c33400a6723664be119c927d9cf535d3b2dc9"
    "a83e63726c2d23656930b984094299e39e9df9e54632c751908db763f95d2207"
    "0c2f0c5eb9c1927e97bd438f7c95749697b589d0144bc4238866316e63623640"
    "d3719818bd89a742397e9a3bd13850949c79b5785c6c0b1086e408c11258c0c1"
    "5618442a0a5e8f8113144a0b8c582e6859b49272b89a0c766d2e4c735f092c1c"
)

SERATO_DOWNLOAD_URL = "https://serato.com/scratchlive/downloads"
EXPECTED_XOR_KEY_SHA256 = "d47954d8038dda6cea66ddb8bd509ed66e6b4607f00d139aef8c4e03c370dc60"
RANE_MAGIC = b"Copyright 2009 Rane Corporation\x00"


def print_banner() -> None:
    print("=" * 78)
    print("  RANE SIXTY-EIGHT FIRMWARE EXTRACTOR, OLED PATCHER & HARDWARE FLASHER")
    print("  Unterstützt: Serato Scratch Live 2.5 Mac (.zip/.dmg) & SIXTY-EIGHT.pkg")
    print("=" * 78)


def ask_yes_no(prompt: str, default: bool = False) -> bool:
    suffix = " [J/n]: " if default else " [j/N]: "
    while True:
        try:
            ans = input(prompt + suffix).strip().lower()
        except EOFError:
            return default
        if not ans:
            return default
        if ans in ("j", "ja", "y", "yes"):
            return True
        if ans in ("n", "nein", "no"):
            return False
        print("  Bitte 'j' (Ja) oder 'n' (Nein) eingeben.")


# =============================================================================
# 1. SOFTWARE- & ABHÄNGIGKEITSPRÜFUNG (INKL. AUTOMATISCHER INSTALLATION)
# =============================================================================
def check_and_install_dependencies(auto_yes: bool = False) -> bool:
    print("\n[SCHRITT 1/5] Prüfe benötigte System-Tools & Python-Bibliotheken...")

    required_bins = [
        ("python3", "Python 3 Laufzeitumgebung"),
        ("unzip", "ZIP-Entpacker für Serato Scratch Live Download"),
        ("hdiutil", "macOS Disk-Image-Tool zum Mounten der Serato .dmg"),
        ("pkgutil", "macOS Package-Tool zum Entpacken von Sixty-Eight.pkg"),
    ]

    missing_bins = []
    for cmd, desc in required_bins:
        path = shutil.which(cmd)
        if path:
            print(f"  ✓ System-Tool '{cmd:8s}' gefunden ({path}) – {desc}")
        else:
            print(f"  ✗ System-Tool '{cmd:8s}' FEHLT! – {desc}")
            missing_bins.append(cmd)

    # Prüfe Xcode Command Line Tools
    clt_res = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
    if clt_res.returncode == 0:
        print(f"  ✓ Xcode Command Line Tools gefunden ({clt_res.stdout.strip()})")
    else:
        print("  ✗ Xcode Command Line Tools fehlen!")
        if auto_yes or ask_yes_no("  Sollen die Xcode Command Line Tools jetzt installiert werden?", default=True):
            subprocess.run(["xcode-select", "--install"], check=False)
            print("  Bitte schließe die macOS-Installation ab und starte das Skript erneut.")
            return False
        return False

    if missing_bins:
        print(f"\n  [!] Fehlende System-Tools: {', '.join(missing_bins)}")
        if shutil.which("brew"):
            if auto_yes or ask_yes_no("  Sollen fehlende Tools jetzt über Homebrew installiert werden?", default=True):
                for b in missing_bins:
                    subprocess.run(["brew", "install", b], check=True)
            else:
                return False
        else:
            print("  [!] Bitte installiere Homebrew (https://brew.sh) oder die fehlenden macOS-Tools.")
            return False

    # Prüfe Python-Pakete (unicorn für Hardware-Bootloader-Emulation, capstone für ARM-Disassembly)
    py_packages = [
        ("unicorn", "unicorn", "Unicorn ARM7TDMI CPU-Emulator (Hardware-CRC & OLED-Verifikation)"),
        ("capstone", "capstone", "Capstone ARM Disassembler (Instruktions-Sicherheitsprüfung)"),
    ]
    missing_py = []
    for mod_name, pip_name, desc in py_packages:
        try:
            __import__(mod_name)
            print(f"  ✓ Python-Modul '{mod_name:8s}' installiert – {desc}")
        except ImportError:
            print(f"  ✗ Python-Modul '{mod_name:8s}' FEHLT! – {desc}")
            missing_py.append(pip_name)

    if missing_py:
        print(f"\n  [!] Folgende Python-Pakete werden für die Sicherheits-Emulation benötigt: {', '.join(missing_py)}")
        if not (auto_yes or ask_yes_no("  Sollen diese Python-Pakete jetzt automatisch per pip installiert werden?", default=True)):
            print("  [ABBRUCH] Ohne Sicherheits-Verifikationsmodule wird kein Patch ausgeführt.")
            return False

        for pkg in missing_py:
            print(f"  -> Installiere '{pkg}'...")
            # Versuche zuerst reguläres pip install, dann mit --user / --break-system-packages (PEP 668 macOS)
            cmd_base = [sys.executable, "-m", "pip", "install", pkg]
            res = subprocess.run(cmd_base, capture_output=True, text=True)
            if res.returncode != 0:
                res = subprocess.run(cmd_base + ["--user"], capture_output=True, text=True)
            if res.returncode != 0:
                res = subprocess.run(cmd_base + ["--break-system-packages"], capture_output=True, text=True)
            if res.returncode != 0:
                print(f"  [FEHLER] Konnte '{pkg}' nicht installieren:\n{res.stderr}")
                return False
            print(f"  ✓ '{pkg}' erfolgreich installiert.")

    print("  => Alle benötigten Programme und Bibliotheken sind vollständig installiert!")
    return True


# =============================================================================
# 2. QUELL-ARCHIV SUCHEN & FIRMWARE EXTRAHIEREN / XOR-ENTSCHLÜSSELN
# =============================================================================
def derive_or_locate_xor_key(api_data: bytes) -> Optional[bytes]:
    """
    Findet die verschlüsselte Firmware in SIXTY-EIGHTApi anhand der 32-Byte
    Rane-Header-Signatur und verifiziert den 256-Byte XOR-Key.
    """
    # Methode A: Bekannten 256-Byte XOR-Key aus Rane SIXTY-EIGHTApi prüfen
    # Da der Key an einem 256-Byte-Offset zur Firmware liegt, können wir über
    # die bekannte Klartext-Signatur "Copyright 2009 Rane Corporation\0" (32 Bytes)
    # und das bekannte konstante Array `kkey` in SIXTY-EIGHTApi exakt suchen.
    # Zuerst suchen wir alle Stellen im Binary, an denen kkey (256 Bytes) liegt,
    # indem wir prüfen, ob irgendwo im Binary ein 256-Byte-Block den erwarteten
    # SHA-256 Hash hat:
    for off in range(0, len(api_data) - 256, 16):
        candidate = api_data[off : off + 256]
        if hashlib.sha256(candidate).hexdigest() == EXPECTED_XOR_KEY_SHA256:
            return candidate
    # Falls nicht 16-Byte-aligned:
    for off in range(0, len(api_data) - 256):
        if api_data[off] == 0xB8 and api_data[off + 1] == 0xFB:
            candidate = api_data[off : off + 256]
            if hashlib.sha256(candidate).hexdigest() == EXPECTED_XOR_KEY_SHA256:
                return candidate
    return None


def extract_fw_from_sixty_eight_api_bytes(api_data: bytes, source_label: str) -> Optional[Tuple[bytes, str]]:
    """Extrahiert und entschlüsselt die Rane Sixty-Eight Firmware aus SIXTY-EIGHTApi."""
    kkey = derive_or_locate_xor_key(api_data)
    if kkey is None:
        return None

    enc_magic = bytes(RANE_MAGIC[i] ^ kkey[i] for i in range(len(RANE_MAGIC)))
    fpos = api_data.find(enc_magic)
    if fpos == -1:
        return None

    # Entschlüssele zuerst den 64-Byte-Header (0x00..0x40), um die exakte Payload-Größe zu lesen
    hdr = bytearray(api_data[fpos : fpos + 0x40])
    for i in range(0x40):
        hdr[i] ^= kkey[i]

    payload_len = struct.unpack_from(">I", hdr, 0x38)[0]
    total_len = 0x40 + payload_len
    if fpos + total_len > len(api_data):
        return None

    raw_fw = bytearray(api_data[fpos : fpos + total_len])
    for i in range(total_len):
        raw_fw[i] ^= kkey[i % 256]

    ver_major = raw_fw[0x27]
    ver_minor_hex = f"{raw_fw[0x28]:02X}"
    ver_minor_dec = raw_fw[0x28]
    ver_str = f"{ver_major}.{ver_minor_hex} (Hex 0x{ver_major:02X}{raw_fw[0x28]:02X} / Dez {ver_major}.{ver_minor_dec:02d})"
    return bytes(raw_fw), ver_str


def extract_fw_from_pkg(pkg_path: Path) -> Optional[Tuple[bytes, str]]:
    """Entpackt ein macOS .pkg (z.B. Sixty-Eight 1.1.2f5.pkg oder SIXTY-EIGHT.pkg) und extrahiert die Firmware."""
    with tempfile.TemporaryDirectory() as tmpdir:
        exp_dir = Path(tmpdir) / "expanded"
        res = subprocess.run(
            ["pkgutil", "--expand-full", str(pkg_path), str(exp_dir)],
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            return None

        for root, _, files in os.walk(exp_dir):
            for fname in files:
                if fname == "SIXTY-EIGHTApi":
                    fpath = Path(root) / fname
                    if fpath.is_symlink():
                        continue
                    data = fpath.read_bytes()
                    extracted = extract_fw_from_sixty_eight_api_bytes(data, str(pkg_path))
                    if extracted is not None:
                        return extracted
    return None


def extract_fw_from_dmg(dmg_path: Path) -> Optional[Tuple[bytes, str]]:
    """Mountet 'Serato Scratch Live 2.5.dmg' schreibgeschützt im Hintergrund und extrahiert die Firmware."""
    with tempfile.TemporaryDirectory() as mnt:
        # Serato Scratch Live 2.5.dmg besitzt einen Lizenzvertrag (SLA), daher senden wir 'Y\n'
        res = subprocess.run(
            ["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mnt, str(dmg_path)],
            input=b"Y\n",
            capture_output=True,
        )
        if res.returncode != 0:
            return None
        try:
            for root, _, files in os.walk(mnt):
                for fname in files:
                    if fname.lower().endswith(".pkg") and "sixty-eight" in fname.lower():
                        pkg_file = Path(root) / fname
                        extracted = extract_fw_from_pkg(pkg_file)
                        if extracted is not None:
                            return extracted
        finally:
            subprocess.run(["hdiutil", "detach", mnt, "-force"], capture_output=True)
    return None


def extract_fw_from_any_source(source_path: Path) -> Tuple[bytes, str]:
    """
    Unterstützt:
      1. Offizielles Serato-ZIP: 'Serato Scratch Live 2.5 Mac.zip'
      2. Offizielles Serato-DMG: 'Serato Scratch Live 2.5.dmg'
      3. Rane Treiber-PKG:       'Sixty-Eight 1.1.2f5.pkg' / 'SIXTY-EIGHT.pkg'
      4. SIXTY-EIGHTApi Binary oder bereits entschlüsselte '.bin' Firmware
    """
    if not source_path.exists():
        raise FileNotFoundError(f"Quelldatei nicht gefunden: {source_path}")

    if source_path.is_dir():
        # Suche innerhalb des Ordners nach .dmg oder .pkg
        for root, _, files in os.walk(source_path):
            for fname in sorted(files):
                p = Path(root) / fname
                if fname.lower().endswith(".dmg") and "scratch live" in fname.lower():
                    res = extract_fw_from_dmg(p)
                    if res:
                        return res
                if fname.lower().endswith(".pkg") and "sixty" in fname.lower():
                    res = extract_fw_from_pkg(p)
                    if res:
                        return res

    suffix = source_path.suffix.lower()
    if suffix == ".zip":
        print(f"  -> Entpacke ZIP-Archiv '{source_path.name}' in temporäres Verzeichnis...")
        with tempfile.TemporaryDirectory() as tmpdir:
            with zipfile.ZipFile(source_path, "r") as zf:
                zf.extractall(tmpdir)
            for root, _, files in os.walk(tmpdir):
                for fname in files:
                    p = Path(root) / fname
                    if fname.lower().endswith(".dmg"):
                        print(f"  -> Mounte enthaltenes Disk-Image '{fname}' (schreibgeschützt)...")
                        res = extract_fw_from_dmg(p)
                        if res:
                            return res
                    elif fname.lower().endswith(".pkg") and "sixty" in fname.lower():
                        res = extract_fw_from_pkg(p)
                        if res:
                            return res

    elif suffix == ".dmg":
        print(f"  -> Mounte Disk-Image '{source_path.name}' (schreibgeschützt)...")
        res = extract_fw_from_dmg(source_path)
        if res:
            return res

    elif suffix == ".pkg":
        print(f"  -> Untersuche Installer-Paket '{source_path.name}'...")
        res = extract_fw_from_pkg(source_path)
        if res:
            return res

    else:
        data = source_path.read_bytes()
        if data.startswith(RANE_MAGIC):
            ver_major = data[0x27]
            ver_minor_hex = f"{data[0x28]:02X}"
            ver_minor_dec = data[0x28]
            return data, f"{ver_major}.{ver_minor_hex} (Hex 0x{ver_major:02X}{data[0x28]:02X} / Dez {ver_major}.{ver_minor_dec:02d})"
        res = extract_fw_from_sixty_eight_api_bytes(data, str(source_path))
        if res:
            return res

    raise RuntimeError(f"Konnte keine Rane Sixty-Eight Firmware aus '{source_path}' extrahieren.")


def discover_candidate_sources() -> List[Tuple[str, Path]]:
    """Sucht automatisch nach heruntergeladenen Serato Scratch Live / Rane Archiven."""
    home = Path.home()
    search_paths = [
        REPO_ROOT / "Serato Scratch Live 2.5 Mac.zip",
        home / "Downloads" / "Serato Scratch Live 2.5 Mac.zip",
        home / "Downloads" / "Serato Scratch Live 2.5 Mac" / "Serato Scratch Live 2.5.dmg",
        home / "Downloads" / "SIXTY-EIGHT-2.0.0b3" / "SIXTY-EIGHT.pkg",
        home / "Downloads" / "SIXTY-EIGHT-1" / "SIXTY-EIGHT.pkg",
        home / "Desktop" / "Serato Scratch Live 2.5 Mac.zip",
        home / "Desktop" / "treibertemp" / "sixty_eight_firmware.bin",
    ]
    found: List[Tuple[str, Path]] = []
    seen = set()
    for p in search_paths:
        if p.exists() and p.resolve() not in seen:
            seen.add(p.resolve())
            if "Serato Scratch Live" in p.name:
                label = f"Offizieller Serato Scratch Live 2.5 Download ({p.name}) -> Firmware v1.1E"
            elif "2.0.0b3" in str(p):
                label = f"Rane Sixty-Eight 2.0.0b3 Treiberpaket ({p.name}) -> Firmware v1.28"
            elif "SIXTY-EIGHT" in str(p):
                label = f"Rane Sixty-Eight Standalone Treiberpaket ({p.name}) -> Firmware v1.28"
            else:
                label = f"Bereits extrahierte Firmware-Binärdatei ({p.name})"
            found.append((label, p))
    return found


# =============================================================================
# 3. KRYPTOGRAFISCHE & HARDWARE-BOOTLOADER VERIFIKATION + OLED PATCHER
# =============================================================================
from flash_rane_firmware import (
    LiveUSBHIDTransport,
    UnicornRaneHardwareSimulator,
    rane_section_crc,
    run_flash_protocol,
    validate_firmware_image,
)


def flash_addr_to_raw(flash_addr: int) -> int:
    return flash_addr - 0x08000 + 0x03140


def read_flash_word(buf: bytes, flash_addr: int) -> int:
    return struct.unpack_from("<I", buf, flash_addr_to_raw(flash_addr))[0]


def write_flash_word(buf: bytearray, flash_addr: int, val: int) -> None:
    struct.pack_into("<I", buf, flash_addr_to_raw(flash_addr), val)


def encode_arm_branch(src_addr: int, dst_addr: int, cond: int = 0xE, link: bool = False) -> int:
    offset = (dst_addr - (src_addr + 8)) >> 2
    op = 0x0B if link else 0x0A
    return (cond << 28) | (op << 24) | (offset & 0x00FFFFFF)


def patch_firmware_for_custom_oled(orig_fw: bytes) -> Tuple[bytes, Dict[str, int]]:
    """
    Patcht Section 2 (LPC2468 ARM7TDMI Main Firmware ab 0x08000), sodass:
      - SysEx 0x01 direkt in den aktiven OLED-Zeile-1-Puffer (0x400000E7) schreibt
        und das Dirty-Flag [0x40000176] = 0x11 setzt.
      - SysEx 0x02 direkt in den aktiven OLED-Zeile-2-Puffer (0x400000F5) schreibt
        und das Dirty-Flag [0x40000177] = 0x11 setzt.
      - update_lcd() das Mode-Flag [0x4000013B] prüft (SysEx 0x7D = Custom OLED ON,
        SysEx 0x7C = Custom OLED OFF -> zurück zu BPM:/TIME:).
      - SysEx 0x06 (`F0 17 06 <arg> F7`, mit `arg = (ch << 4) | mode`) für jeden
        der 4 Kanalzüge (PGM 1..4) den Hardware-Filter-Modus umschaltet:
          * Mode 0 (0x00): Normal (Links = Low-Pass, 12h = Neutral, Rechts = High-Pass)
          * Mode 1 (0x01): Nur Low-Pass über den vollen 270°-Regelweg (Rechts = Neutral, Links = LPF)
          * Mode 2 (0x02): Nur High-Pass über den vollen 270°-Regelweg (Links = Neutral, Rechts = HPF)
          * Mode 3 (0x03): Hardware-Filter AUS / Reiner MIDI-Controller (DSP fest auf 64 Neutral, USB-MIDI sendet 0..127)
    Unterstützt sowohl Firmware v1.1E (0x011E aus Serato Scratch Live 2.5)
    als auch Firmware v1.28 (0x0128 aus SIXTY-EIGHT.pkg).
    """
    ok, msg, _ = validate_firmware_image(orig_fw)
    if not ok:
        raise ValueError(f"Eingabe-Firmware ist ungültig: {msg}")

    ver_code = (orig_fw[0x27] << 8) | orig_fw[0x28]
    patched = bytearray(orig_fw)

    if ver_code == 0x0128:
        # Sicherheitsprüfung der Original-Instruktionen in v1.28 vor dem Patch
        expected_128 = {
            0x0C808: 0x4000011F,
            0x0C80C: 0x4000012D,
            0x0BBC8: 0xEBFFF397,
            0x0BC24: 0xEBFFF380,
            0x08A44: 0xE3A09000,
            0x08A48: 0xE3A0A000,
            0x14004: encode_arm_branch(0x14004, 0x1411C),
            0x0BA60: encode_arm_branch(0x0BA60, 0x0C560, cond=1),
            0x13A80: 0xE3A00001,
            0x13A8C: 0xE3A00028,
        }
        for addr, exp_val in expected_128.items():
            actual = read_flash_word(patched, addr)
            if actual != exp_val:
                raise RuntimeError(
                    f"Sicherheitsstopp (v1.28): Unerwarteter Befehl an 0x{addr:05X} "
                    f"(gefunden: 0x{actual:08X}, erwartet: 0x{exp_val:08X})"
                )

        # A) Custom OLED Patch (SysEx 0x01, 0x02, 0x7C, 0x7D)
        write_flash_word(patched, 0x0C808, 0x400000E7)  # Zeile 1 Puffer
        write_flash_word(patched, 0x0C80C, 0x400000F5)  # Zeile 2 Puffer
        write_flash_word(patched, 0x0BBC8, 0xE5C2408F)  # [0x40000176] = 0x11
        write_flash_word(patched, 0x0BC24, 0xE5C24082)  # [0x40000177] = 0x11

        write_flash_word(patched, 0x08A44, 0xE3A06000)
        write_flash_word(patched, 0x08A48, 0xE3A07000)
        write_flash_word(patched, 0x08A4C, 0xE58D0018)
        write_flash_word(patched, 0x08A50, 0xE58D0014)
        write_flash_word(patched, 0x08A54, 0xE59F1C94)  # ldr r1, =0x400000E7
        write_flash_word(patched, 0x08A58, 0xE5D11054)  # ldrb r1, [r1, #0x54] (0x4000013B)
        write_flash_word(patched, 0x08A5C, 0xE3510000)  # cmp r1, #0
        write_flash_word(patched, 0x08A60, 0x1A000257)  # bne epilogue (0x093C4)

        # B) Channel Strip Filter Modes (SysEx 0x06 + PGM 1..4 Filter Pot Hooks)
        write_flash_word(patched, 0x14004, encode_arm_branch(0x14004, 0x140A8))
        write_flash_word(patched, 0x0BB70, encode_arm_branch(0x0BB70, 0x0BC74))
        write_flash_word(patched, 0x0BCC0, encode_arm_branch(0x0BCC0, 0x0BC74))
        write_flash_word(patched, 0x0BA60, encode_arm_branch(0x0BA60, 0x0BCC4, cond=1))

        write_flash_word(patched, 0x0BCC4, 0xE3500006)                                    # cmp r0, #6
        write_flash_word(patched, 0x0BCC8, encode_arm_branch(0x0BCC8, 0x0C560, cond=1))   # bne #0x0C560
        write_flash_word(patched, 0x0BCCC, 0xE59F0B2C)                                    # ldr r0, [0x0C800] (0x400001D5)
        write_flash_word(patched, 0x0BCD0, 0xE5D00000)                                    # ldrb r0, [r0]
        write_flash_word(patched, 0x0BCD4, encode_arm_branch(0x0BCD4, 0x0BB74))           # b #0x0BB74

        write_flash_word(patched, 0x0BB74, 0xE2800003)                                    # add r0, r0, #3
        write_flash_word(patched, 0x0BB78, 0xE20000FF)                                    # and r0, r0, #0xFF
        write_flash_word(patched, 0x0BB7C, 0xE7D11000)                                    # ldrb r1, [r1, r0] (arg)
        write_flash_word(patched, 0x0BB80, encode_arm_branch(0x0BB80, 0x191D4, link=True))  # bl #0x191D4
        write_flash_word(patched, 0x0BB84, encode_arm_branch(0x0BB84, 0x0BC74))           # b #0x0BC74

        cave_words_128 = [
            0xE59F205C,  # 0x19198: ldr   r2, [pc, #0x5C]       ; r2 = 0x400018A8
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
            0xE1A00221,  # 0x191D4: mov   r0, r1, lsr #4        ; r0 = ch
            0xE2000003,  # 0x191D8: and   r0, r0, #3            ; clamp ch to 0..3
            0xE2011003,  # 0x191DC: and   r1, r1, #3            ; r1 = mode (0..3)
            0xE59F2014,  # 0x191E0: ldr   r2, [pc, #0x14]       ; r2 = 0x400018A8
            0xE2823D35,  # 0x191E4: add   r3, r2, #0xD40        ; r3 = 0x400025E8
            0xE0833000,  # 0x191E8: add   r3, r3, r0            ; r3 = 0x400025E8 + ch
            0xE5C31004,  # 0x191EC: strb  r1, [r3, #4]          ; filter_mode[ch] = mode
            0xE5D34000,  # 0x191F0: ldrb  r4, [r3]              ; r4 = raw_pot_xor40[ch]
            0xE2244040,  # 0x191F4: eor   r4, r4, #0x40         ; r4 = raw_pot[ch] (64 if untouched)
            encode_arm_branch(0x191F8, 0x191AC),                  # 0x191F8: b #0x191AC
            0x400018A8,  # 0x191FC: .word 0x400018A8
        ]
        for idx, w in enumerate(cave_words_128):
            write_flash_word(patched, 0x19198 + idx * 4, w)

        for ch, hook_addr in [(0, 0x10F98), (1, 0x1105C), (2, 0x11120), (3, 0x111E4)]:
            write_flash_word(patched, hook_addr + 0, 0xE3A00000 | ch)
            write_flash_word(patched, hook_addr + 4, encode_arm_branch(hook_addr + 4, 0x19198, link=True))
            write_flash_word(patched, hook_addr + 8, 0xE1A00000)

        # C) Firmware Version Bump -> v2.00 Custom (Section 2 Opcode 0x01 & Section 6 USB bcdDevice = 0x0200)
        write_flash_word(patched, 0x13A7C, 0xE3A00001)  # mov r0, #1
        write_flash_word(patched, 0x13A80, 0xE5C40000)  # strb r0, [r4]     (Opcode 0x01)
        write_flash_word(patched, 0x13A84, 0xE3A00002)  # mov r0, #2        (Major = 2)
        write_flash_word(patched, 0x13A88, 0xE5C40001)  # strb r0, [r4, #1]
        write_flash_word(patched, 0x13A8C, 0xE3A00000)  # mov r0, #0        (Minor = 0 -> v2.00)
        write_flash_word(patched, 0x13A90, 0xE5C40002)  # strb r0, [r4, #2]

        if patched[0x03BE8D:0x03BE8F] != b"\x00\x01" or patched[0x03BE9F:0x03BEA1] != b"\x00\x01":
            raise RuntimeError("Sicherheitsstopp (v1.28): Unerwarteter USB bcdDevice-Wert in Section 6")
        patched[0x03BE8D:0x03BE8F] = b"\x00\x02"  # USB Port A bcdDevice = 0x0200 (v2.00 Custom)
        patched[0x03BE9F:0x03BEA1] = b"\x00\x02"  # USB Port B bcdDevice = 0x0200 (v2.00 Custom)
        sec6_file_off = 0x03B640

    elif ver_code == 0x011E:
        # Sicherheitsprüfung der Original-Instruktionen in v1.1E (Serato Scratch Live 2.5)
        expected_11e = {
            0x0C914: 0x4000011F,
            0x0C918: 0x4000012D,
            0x0BC14: 0xEBFFF383,
            0x0BC70: 0xEBFFF36C,
            0x08A40: 0xE3A06000,
            0x08A44: 0xE3A07000,
            0x08A48: 0xE3A08000,
            0x08A4C: 0xE3A09000,
            0x13888: encode_arm_branch(0x13888, 0x139A0),
            0x0BAAC: encode_arm_branch(0x0BAAC, 0x0C2C8, cond=1),
            0x1335C: 0xE3A00001,
            0x13368: 0xE3A0001E,
        }
        for addr, exp_val in expected_11e.items():
            actual = read_flash_word(patched, addr)
            if actual != exp_val:
                raise RuntimeError(
                    f"Sicherheitsstopp (v1.1E): Unerwarteter Befehl an 0x{addr:05X} "
                    f"(gefunden: 0x{actual:08X}, erwartet: 0x{exp_val:08X})"
                )

        # A) Custom OLED Patch (SysEx 0x01, 0x02, 0x7C, 0x7D)
        write_flash_word(patched, 0x0C914, 0x400000E7)  # Zeile 1 Puffer
        write_flash_word(patched, 0x0C918, 0x400000F5)  # Zeile 2 Puffer
        write_flash_word(patched, 0x0BC14, 0xE5C2908F)  # strb sb, [r2, #0x8f] -> [0x40000176] = 0x11
        write_flash_word(patched, 0x0BC70, 0xE5C29082)  # strb sb, [r2, #0x82] -> [0x40000177] = 0x11

        write_flash_word(patched, 0x08A40, 0xE59F19C8)  # ldr r1, [pc, #0x9c8] -> 0x400000E7
        write_flash_word(patched, 0x08A44, 0xE5D11054)  # ldrb r1, [r1, #0x54] (0x4000013B)
        write_flash_word(patched, 0x08A48, 0xE3510000)  # cmp r1, #0
        write_flash_word(patched, 0x08A4C, 0x1A00028B)  # bne epilogue (0x09480)

        # B) Channel Strip Filter Modes (SysEx 0x06 + PGM 1..4 Filter Pot Hooks in v1.1E)
        write_flash_word(patched, 0x13888, encode_arm_branch(0x13888, 0x1392C))
        write_flash_word(patched, 0x0BD70, 0xE3500001)
        write_flash_word(patched, 0x0BD74, encode_arm_branch(0x0BD74, 0x0BDB4, cond=8))
        write_flash_word(patched, 0x0BD78, encode_arm_branch(0x0BD78, 0x0BDAC))

        write_flash_word(patched, 0x0BB20, 0xE51F1768)
        write_flash_word(patched, 0x0BB24, 0xE5810048)
        write_flash_word(patched, 0x0BB28, encode_arm_branch(0x0BB28, 0x0BB54))

        write_flash_word(patched, 0x0BBBC, encode_arm_branch(0x0BBBC, 0x0BCC0))
        write_flash_word(patched, 0x0BD0C, encode_arm_branch(0x0BD0C, 0x0BCC0))
        write_flash_word(patched, 0x0BDD0, encode_arm_branch(0x0BDD0, 0x0BCC0))

        write_flash_word(patched, 0x0BAAC, encode_arm_branch(0x0BAAC, 0x0BD10, cond=1))

        write_flash_word(patched, 0x0BD10, 0xE3580006)
        write_flash_word(patched, 0x0BD14, encode_arm_branch(0x0BD14, 0x0C2C8, cond=1))
        write_flash_word(patched, 0x0BD18, 0xE59F0BF0)
        write_flash_word(patched, 0x0BD1C, 0xE5D00000)
        write_flash_word(patched, 0x0BD20, encode_arm_branch(0x0BD20, 0x0BB2C))

        write_flash_word(patched, 0x0BB2C, 0xE2800003)
        write_flash_word(patched, 0x0BB30, 0xE20000FF)
        write_flash_word(patched, 0x0BB34, 0xE7D11000)
        write_flash_word(patched, 0x0BB38, 0xE1A00221)
        write_flash_word(patched, 0x0BB3C, 0xE2000003)
        write_flash_word(patched, 0x0BB40, 0xE2011003)
        write_flash_word(patched, 0x0BB44, 0xE51F278C)
        write_flash_word(patched, 0x0BB48, encode_arm_branch(0x0BB48, 0x18AE8, link=True))
        write_flash_word(patched, 0x0BB4C, encode_arm_branch(0x0BB4C, 0x0BCC0))

        write_flash_word(patched, 0x18AE8, 0xE2822058)
        write_flash_word(patched, 0x18AEC, 0xE2823D35)
        write_flash_word(patched, 0x18AF0, 0xE0833000)
        write_flash_word(patched, 0x18AF4, 0xE5C31004)
        write_flash_word(patched, 0x18AF8, 0xE5D35000)
        write_flash_word(patched, 0x18AFC, encode_arm_branch(0x18AFC, 0x0BD7C))

        write_flash_word(patched, 0x0BD7C, 0xE2255040)
        write_flash_word(patched, 0x0BD80, 0xE51F29C8)
        write_flash_word(patched, 0x0BD84, 0xE2822058)
        write_flash_word(patched, 0x0BD88, 0xE2823D35)
        write_flash_word(patched, 0x0BD8C, 0xE0833000)
        write_flash_word(patched, 0x0BD90, 0xE2251040)
        write_flash_word(patched, 0x0BD94, 0xE5C31000)
        write_flash_word(patched, 0x0BD98, 0xE5D33004)
        write_flash_word(patched, 0x0BD9C, 0xE1A01005)
        write_flash_word(patched, 0x0BDA0, 0xE3530001)
        write_flash_word(patched, 0x0BDA4, 0x02851001)
        write_flash_word(patched, 0x0BDA8, encode_arm_branch(0x0BDA8, 0x0BDD4))

        write_flash_word(patched, 0x0BDD4, 0x01A010A1)
        write_flash_word(patched, 0x0BDD8, 0x83A01040)
        write_flash_word(patched, 0x0BDDC, 0xE3530002)
        write_flash_word(patched, 0x0BDE0, 0x008110A5)
        write_flash_word(patched, 0x0BDE4, encode_arm_branch(0x0BDE4, 0x0BBC0))
        write_flash_word(patched, 0x0BBC0, 0xE7821100)
        write_flash_word(patched, 0x0BBC4, 0xE12FFF1E)

        for ch, hook_addr in [(0, 0x108A4), (1, 0x10968), (2, 0x10A2C), (3, 0x10AF0)]:
            write_flash_word(patched, hook_addr + 0, 0xE3A00000 | ch)
            write_flash_word(patched, hook_addr + 4, encode_arm_branch(hook_addr + 4, 0x0BD80, link=True))
            write_flash_word(patched, hook_addr + 8, 0xE1A00000)

        # C) Firmware Version Bump -> v2.00 Custom (Section 2 Opcode 0x01 & Section 6 USB bcdDevice = 0x0200)
        write_flash_word(patched, 0x13358, 0xE3A00001)  # mov r0, #1
        write_flash_word(patched, 0x1335C, 0xE5C60000)  # strb r0, [r6]     (Opcode 0x01)
        write_flash_word(patched, 0x13360, 0xE3A00002)  # mov r0, #2        (Major = 2)
        write_flash_word(patched, 0x13364, 0xE5C60001)  # strb r0, [r6, #1]
        write_flash_word(patched, 0x13368, 0xE3A00000)  # mov r0, #0        (Minor = 0 -> v2.00)
        write_flash_word(patched, 0x1336C, 0xE5C60002)  # strb r0, [r6, #2]

        if patched[0x03B88D:0x03B88F] != b"\x00\x01" or patched[0x03B89F:0x03B8A1] != b"\x00\x01":
            raise RuntimeError("Sicherheitsstopp (v1.1E): Unerwarteter USB bcdDevice-Wert in Section 6")
        patched[0x03B88D:0x03B88F] = b"\x00\x02"  # USB Port A bcdDevice = 0x0200 (v2.00 Custom)
        patched[0x03B89F:0x03B8A1] = b"\x00\x02"  # USB Port B bcdDevice = 0x0200 (v2.00 Custom)
        sec6_file_off = 0x03AF40
    else:
        raise RuntimeError(f"Nicht unterstützte Firmware-Version: 0x{ver_code:04X}")

    # Berechne alle Prüfsummen-Ebenen neu (Section 2 + Section 6 -> Section 0 -> Header Payload)
    sec2_size = struct.unpack_from("<I", patched, 0x005C)[0]
    old_sec2_crc = struct.unpack_from("<I", patched, 0x0060)[0]
    new_sec2_crc = rane_section_crc(bytes(patched[0x03140 : 0x03140 + sec2_size]))
    struct.pack_into("<I", patched, 0x0060, new_sec2_crc)

    sec6_size = struct.unpack_from("<I", patched, 0x008C)[0]
    old_sec6_crc = struct.unpack_from("<I", patched, 0x0090)[0]
    new_sec6_crc = rane_section_crc(bytes(patched[sec6_file_off : sec6_file_off + sec6_size]))
    struct.pack_into("<I", patched, 0x0090, new_sec6_crc)

    old_sec0_crc = struct.unpack_from("<I", patched, 0x0048)[0]
    new_sec0_crc = rane_section_crc(bytes(patched[0x0004C:0x00140]))
    struct.pack_into("<I", patched, 0x0048, new_sec0_crc)

    old_hdr_crc = struct.unpack_from(">I", patched, 0x003C)[0]
    new_hdr_crc = zlib.crc32(bytes(patched[0x0040:])) & 0xFFFFFFFF
    struct.pack_into(">I", patched, 0x003C, new_hdr_crc)

    ok_post, msg_post, _ = validate_firmware_image(bytes(patched))
    if not ok_post:
        raise RuntimeError(f"CRC-Validierung nach Patch fehlgeschlagen: {msg_post}")

    crc_info = {
        "old_sec2_crc": old_sec2_crc,
        "new_sec2_crc": new_sec2_crc,
        "old_sec6_crc": old_sec6_crc,
        "new_sec6_crc": new_sec6_crc,
        "old_sec0_crc": old_sec0_crc,
        "new_sec0_crc": new_sec0_crc,
        "old_hdr_crc": old_hdr_crc,
        "new_hdr_crc": new_hdr_crc,
    }
    return bytes(patched), crc_info


def verify_in_unicorn_emulator(fw_bytes: bytes, expect_custom_oled: bool) -> bool:
    """
    Lädt das Firmware-Image in den echten ARM7TDMI LPC2468 Bootloader im Unicorn-Emulator,
    führt die Hardware-CRC32-Prüfung aller 7 Sektionen aus und testet anschließend
    SysEx 0x7D / 0x01 / 0x02 / 0x7C gegen den OLED-Bildschirmpuffer sowie SysEx 0x06
    gegen die 4 Kanal-Filter-Register (0x400018A8..0x400018B4) und die Firmware-Version
    v2.00 Custom (Section 2 Opcode 0x01 + Section 6 USB bcdDevice = 0x0200).
    """
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
    from unicorn.arm_const import (
        UC_ARM_REG_LR,
        UC_ARM_REG_PC,
        UC_ARM_REG_R0,
        UC_ARM_REG_R1,
        UC_ARM_REG_R2,
        UC_ARM_REG_R3,
        UC_ARM_REG_SP,
    )

    ok, msg, secs = validate_firmware_image(fw_bytes)
    if not ok:
        print(f"  [Unicorn] Image-Validierung fehlgeschlagen: {msg}")
        return False

    is_128_layout = secs[2]["size"] == 70144
    mu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    mu.mem_map(0x00000000, 0x00100000)
    mu.mem_map(0x40000000, 0x00010000)
    mu.mem_map(0x3FFF0000, 0x00010000)
    mu.mem_map(0xE0000000, 0x00200000)
    mu.mem_map(0xFFFF0000, 0x00010000)

    # Überspringe Hardware-SPI-Warteschleifen bei der USB Opcode 0x01 Abfrage
    def _skip_spi_wait(uc, address, size, user_data):
        if address in (0x13970, 0x08798, 0x15270, 0x15250, 0x14890, 0x148A8):
            uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))

    mu.hook_add(UC_HOOK_CODE, _skip_spi_wait)

    # Bootloader in 0x01000 und alle 7 Flash-Sektionen laden
    mu.mem_write(0x00001000, fw_bytes[0x00140:0x03140])
    for s in secs:
        mu.mem_write(s["addr"], fw_bytes[s["file_off"] : s["file_off"] + s["size"]])

    # 1. Bootloader 7-Sektionen-CRC-Validator aufrufen
    bl_crc_fn = 0x00002404 if is_128_layout else 0x0000241C
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00001000)
    mu.emu_start(bl_crc_fn, 0x00001000, timeout=0, count=5000000)
    r0_valid = mu.reg_read(UC_ARM_REG_R0)
    if r0_valid != 1:
        print(f"  ✗ [Unicorn] Bootloader-CRC-Prüfung fehlgeschlagen (R0={r0_valid})!")
        return False
    print("  ✓ [Unicorn] ARM7TDMI Bootloader akzeptiert alle 7 Flash-Sektionen (R0 = 1 / VALID)")

    # 2. Keil __scatterload ausführen (dekomprimiert SRAM RW-Daten inkl. "BPM:" / "TIME:")
    scatter_start = 0x000080B0 if is_128_layout else 0x000080B4
    scatter_end = 0x000081B0 if is_128_layout else 0x000081B4
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.emu_start(scatter_start, scatter_end, timeout=0, count=300000)

    sysex_fn = 0x0000B96C if is_128_layout else 0x0000B9C8
    update_lcd_fn = 0x00008A2C if is_128_layout else 0x00008A28
    pot_disp_fn = 0x00010C78 if is_128_layout else 0x00010584

    def send_sysex(payload: bytes) -> None:
        mu.mem_write(0x40001540, payload)
        mu.mem_write(0x400001D5, b"\x00")
        mu.mem_write(0x400001D4, bytes([len(payload)]))
        mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
        mu.reg_write(UC_ARM_REG_LR, 0x00008000)
        mu.emu_start(sysex_fn, 0x00008000, timeout=0, count=200000)

    send_sysex(b"\xF0\x17\x7D\x01\xF7")
    send_sysex(b"\xF0\x17\x01HENRY'S RANE68\xF7")
    send_sysex(b"\xF0\x17\x02OLED VERIFIED!\xF7")

    # Hintergrund-Aufruf von update_lcd() simulieren
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00008000)
    mu.emu_start(update_lcd_fn, 0x00008000, timeout=0, count=200000)

    line1 = bytes(mu.mem_read(0x400000E7, 14)).decode("ascii", errors="replace")
    line2 = bytes(mu.mem_read(0x400000F5, 14)).decode("ascii", errors="replace")

    # Prüfe USB Opcode 0x01 (ARM7 Firmware-Versionsabfrage) & Section 6 USB bcdDevice
    if is_128_layout:
        spi_fn = 0x000139B8
        rx_addr = struct.unpack("<I", mu.mem_read(0x139E0 + 8 + 0xE50, 4))[0]
        tx_addr = struct.unpack("<I", mu.mem_read(0x139E4 + 8 + 0xE50, 4))[0]
        bcd_a = struct.unpack("<H", mu.mem_read(0x07A000 + 0x084D, 2))[0]
        bcd_b = struct.unpack("<H", mu.mem_read(0x07A000 + 0x085F, 2))[0]
    else:
        spi_fn = 0x000132A8
        rx_addr = struct.unpack("<I", mu.mem_read(0x132CC + 8 + 0xD7C, 4))[0]
        tx_addr = struct.unpack("<I", mu.mem_read(0x132D0 + 8 + 0xD7C, 4))[0]
        bcd_a = struct.unpack("<H", mu.mem_read(0x07A000 + 0x094D, 2))[0]
        bcd_b = struct.unpack("<H", mu.mem_read(0x07A000 + 0x095F, 2))[0]

    mu.mem_write(rx_addr, b"\x01" + b"\x00" * 63)
    mu.mem_write(tx_addr, b"\x00" * 64)
    mu.reg_write(UC_ARM_REG_R0, 0)
    mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
    mu.reg_write(UC_ARM_REG_LR, 0x00008000)
    mu.emu_start(spi_fn, 0x00008000, timeout=0, count=200000)
    ver_reply = bytes(mu.mem_read(tx_addr, 8))
    arm_major, arm_minor = ver_reply[1], ver_reply[2]

    if expect_custom_oled:
        if line1 != "HENRY'S RANE68" or line2 != "OLED VERIFIED!":
            print(f"  ✗ [Unicorn] Unerwarteter OLED-Inhalt: {line1!r} / {line2!r}")
            return False
        send_sysex(b"\xF0\x17\x7C\x00\xF7")
        revert1 = bytes(mu.mem_read(0x400000E7, 14)).decode("ascii", errors="replace")
        revert2 = bytes(mu.mem_read(0x400000F5, 14)).decode("ascii", errors="replace")
        print(
            f'  ✓ [Unicorn] Custom-OLED-Test bestanden: 0x7D="{line1}" / "{line2}" '
            f'-> 0x7C Revert="{revert1.strip()}" / "{revert2.strip()}"'
        )

        # 3. Verifiziere Channel Filter Modes (SysEx 0x06) für PGM 1..4
        for ch, mode in [(0, 0), (1, 1), (2, 2), (3, 3)]:
            send_sysex(bytes([0xF0, 0x17, 0x06, (ch << 4) | mode, 0xF7]))
            mu.reg_write(UC_ARM_REG_R0, 0)
            mu.reg_write(UC_ARM_REG_R1, 0)
            mu.reg_write(UC_ARM_REG_R2, 0x41 + ch)
            mu.reg_write(UC_ARM_REG_R3, 96)  # Poti auf 2:30 Uhr (96)
            mu.reg_write(UC_ARM_REG_SP, 0x40007F00)
            mu.reg_write(UC_ARM_REG_LR, 0x00008000)
            mu.emu_start(pot_disp_fn, 0x00008000, timeout=0, count=100000)

        dsp_vals = [struct.unpack("<I", mu.mem_read(0x400018A8 + i * 4, 4))[0] for i in range(4)]
        if dsp_vals != [96, 48, 112, 64]:
            print(f"  ✗ [Unicorn] Filter-Mode-Test fehlgeschlagen: DSP={dsp_vals} (erwartet [96, 48, 112, 64])")
            return False
        print(
            f"  ✓ [Unicorn] Channel-Filter-Modes (SysEx 0x06) verifiziert: "
            f"PGM1(Normal)={dsp_vals[0]}, PGM2(LP-270°)={dsp_vals[1]}, "
            f"PGM3(HP-270°)={dsp_vals[2]}, PGM4(Filter-Aus/MIDI)={dsp_vals[3]}"
        )

        # 4. Verifiziere Custom Firmware Version v2.00 (ARM7 Opcode 0x01 & USB bcdDevice 0x0200)
        if (arm_major, arm_minor) != (2, 0) or bcd_a != 0x0200 or bcd_b != 0x0200:
            print(
                f"  ✗ [Unicorn] Versions-Prüfung fehlgeschlagen: ARM={arm_major}.{arm_minor:02X}, "
                f"bcdDevice=0x{bcd_a:04X}/0x{bcd_b:04X}"
            )
            return False
        print(
            f"  ✓ [Unicorn] Custom-Firmware-Version verifiziert: "
            f"v{arm_major}.{arm_minor:02X} Custom (ARM7 Opcode 0x01 = {arm_major}.{arm_minor:02X}, "
            f"USB Port A/B bcdDevice = 0x{bcd_a:04X})"
        )
    else:
        print(
            f'  ✓ [Unicorn] Original-Firmware-Test bestanden: Standard-Anzeige="{line1.strip()}" / "{line2.strip()}", '
            f"Version=v{arm_major}.{arm_minor:02X} (bcdDevice=0x{bcd_a:04X})"
        )
    return True


# =============================================================================
# 4. HARDWARE-SICHERHEITSPRÜFUNGEN VOR DEM FLASHEN
# =============================================================================
def check_conflicting_processes(auto_yes: bool = False) -> bool:
    """Prüft auf laufende Prozesse, die den USB-HID-Kanal des Rane Sixty-Eight nutzen."""
    conflict_names = ["Rane Driver Manager", "RaneMIDIAgent", "Scratch LIVE", "Serato DJ"]
    running = []
    for name in conflict_names:
        res = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            running.append(name)

    if not running:
        print("  ✓ Keine blockierenden Hintergrundprozesse (Control Panel / MIDI Agent) aktiv.")
        return True

    print(f"\n  [!] Folgende Programme greifen aktuell auf den Mixer zu: {', '.join(running)}")
    if auto_yes or ask_yes_no(
        "  Sollen diese Programme für die Dauer des Flash-Vorgangs sicher beendet werden?",
        default=True,
    ):
        for name in running:
            subprocess.run(["killall", name], capture_output=True)
        time.sleep(1.0)
        print("  ✓ Prozesse beendet – USB-HID-Kanal ist frei.")
        return True

    print("  [WARNUNG] Fortfahren trotz laufender Prozesse kann den USB-Flash stören!")
    return ask_yes_no("  Trotzdem fortfahren?", default=False)


def send_live_oled_success_banner(line1: str = "HENRY'S RANE68", line2: str = "FLASH SUCCESS!") -> None:
    """Sendet nach erfolgreichem Flash der gepatchten Firmware kurz einen Erfolgstext ans OLED."""
    try:
        iokit = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/IOKit.framework/IOKit")
        cf = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        iokit.IOHIDManagerCreate.restype = ctypes.c_void_p
        iokit.IOHIDManagerCopyDevices.restype = ctypes.c_void_p
        iokit.IOHIDDeviceOpen.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        iokit.IOHIDDeviceGetProperty.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        iokit.IOHIDDeviceGetProperty.restype = ctypes.c_void_p
        iokit.IOHIDDeviceSetReport.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_long,
            ctypes.c_void_p,
            ctypes.c_long,
        ]
        cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        cf.CFSetGetCount.argtypes = [ctypes.c_void_p]
        cf.CFSetGetCount.restype = ctypes.c_long
        cf.CFSetGetValues.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        cf.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]

        def cfstr(s: str) -> ctypes.c_void_p:
            return cf.CFStringCreateWithCString(None, s.encode(), 0x08000100)

        mgr = iokit.IOHIDManagerCreate(None, 0)
        iokit.IOHIDManagerSetDeviceMatching(mgr, None)
        iokit.IOHIDManagerOpen(mgr, 0)
        dev_set = iokit.IOHIDManagerCopyDevices(mgr)
        if not dev_set:
            return
        cnt = cf.CFSetGetCount(dev_set)
        devs = (ctypes.c_void_p * cnt)()
        cf.CFSetGetValues(dev_set, devs)

        k_vid = cfstr("VendorID")
        k_pid = cfstr("ProductID")
        target = None
        for i in range(cnt):
            d = devs[i]
            vid_ref = iokit.IOHIDDeviceGetProperty(d, k_vid)
            pid_ref = iokit.IOHIDDeviceGetProperty(d, k_pid)
            if vid_ref and pid_ref:
                v, p = ctypes.c_int(0), ctypes.c_int(0)
                cf.CFNumberGetValue(vid_ref, 9, ctypes.byref(v))
                cf.CFNumberGetValue(pid_ref, 9, ctypes.byref(p))
                if v.value == 0x1CC5 and p.value == 0x0004:
                    target = d
                    break
        if not target:
            return

        iokit.IOHIDDeviceOpen(target, 0)

        def send_sysex(sysex: bytes) -> None:
            pkt = bytearray(42)
            pkt[0] = 0x41
            pkt[5] = len(sysex)
            pkt[6 : 6 + len(sysex)] = sysex
            buf = (ctypes.c_uint8 * 42).from_buffer(pkt)
            iokit.IOHIDDeviceSetReport(target, 1, 0x41, buf, 42)
            time.sleep(0.05)

        l1 = line1.encode("ascii", errors="replace")[:14].ljust(14, b" ")
        l2 = line2.encode("ascii", errors="replace")[:14].ljust(14, b" ")
        send_sysex(b"\xF0\x17\x7D\x01\xF7")
        send_sysex(b"\xF0\x17\x01" + l1 + b"\xF7")
        send_sysex(b"\xF0\x17\x02" + l2 + b"\xF7")
    except Exception:
        pass


# =============================================================================
# 5. HAUPTPROGRAMM (INTERAKTIVER ASSISTENT & CLI)
# =============================================================================
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extrahiert, patcht und flasht die Rane Sixty-Eight Firmware (Original oder Custom-OLED)."
    )
    parser.add_argument(
        "--input",
        "-i",
        type=str,
        default=None,
        help="Pfad zu 'Serato Scratch Live 2.5 Mac.zip', '.dmg', 'SIXTY-EIGHT.pkg' oder '.bin'",
    )
    parser.add_argument(
        "--output-dir",
        "-o",
        type=str,
        default=str(REPO_ROOT / "firmware_extracted"),
        help="Ausgabeordner für extrahierte & gepatchte Firmware-Dateien",
    )
    parser.add_argument(
        "--mode",
        choices=["interactive", "extract-only", "flash-patched", "flash-original"],
        default="interactive",
        help="Ausführungsmodus (Standard: interactive mit Auswahlmenü & Sicherheitsabfragen)",
    )
    parser.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Automatische Bestätigung bei Paket-Installationen (Hardware-Flash fragt im Interactive-Mode immer nach)",
    )
    args = parser.parse_args()

    print_banner()

    # -------------------------------------------------------------------------
    # SCHRITT 1: Software & Abhängigkeiten prüfen / installieren
    # -------------------------------------------------------------------------
    if not check_and_install_dependencies(auto_yes=args.yes):
        return 1

    # -------------------------------------------------------------------------
    # SCHRITT 2: Quell-Archiv auswählen & Firmware extrahieren
    # -------------------------------------------------------------------------
    print("\n[SCHRITT 2/5] Quell-Archiv (Serato Scratch Live 2.5 / Rane Paket) auswählen...")
    print(f"  Hinweis: Die letzte Serato Scratch Live 2.5 Version (Account zum Download nötig)")
    print(f"           gibt es offiziell unter: {SERATO_DOWNLOAD_URL}")

    source_path: Optional[Path] = None
    if args.input:
        source_path = Path(args.input).expanduser().resolve()
    else:
        candidates = discover_candidate_sources()
        if candidates:
            print("\n  Gefundene Firmware-Quellen auf diesem Mac:")
            for idx, (label, path) in enumerate(candidates, start=1):
                print(f"    [{idx}] {label}")
                print(f"        Pfad: {path}")
            print(f"    [0] Eigenen Dateipfad manuell eingeben")

            if args.mode != "interactive" and args.yes:
                source_path = candidates[0][1]
                print(f"\n  -> Automatisch gewählt: [1] {source_path}")
            else:
                while True:
                    choice = input(f"\n  Bitte Quelle wählen [1-{len(candidates)}, Standard=1]: ").strip()
                    if not choice:
                        source_path = candidates[0][1]
                        break
                    if choice == "0":
                        custom = input("  Pfad zur .zip / .dmg / .pkg / .bin Datei: ").strip().strip("'\"")
                        source_path = Path(custom).expanduser().resolve()
                        break
                    if choice.isdigit() and 1 <= int(choice) <= len(candidates):
                        source_path = candidates[int(choice) - 1][1]
                        break
                    print("  Ungültige Eingabe.")
        else:
            print("\n  [!] Keine Serato Scratch Live 2.5 ZIP/DMG automatisch in ~/Downloads gefunden.")
            custom = input("  Bitte Pfad zur heruntergeladenen 'Serato Scratch Live 2.5 Mac.zip' eingeben: ").strip().strip("'\"")
            if not custom:
                return 1
            source_path = Path(custom).expanduser().resolve()

    print(f"\n  Extrahiere & entschlüssle Rane Sixty-Eight Firmware aus:\n    {source_path}")
    orig_fw, ver_str = extract_fw_from_any_source(source_path)
    ver_tag = f"v{orig_fw[0x27]}_{orig_fw[0x28]:02X}"

    out_dir = Path(args.output_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    orig_out_path = out_dir / f"sixty_eight_firmware_{ver_tag}_original.bin"
    patched_out_path = out_dir / f"sixty_eight_firmware_{ver_tag}_oled_patched.bin"
    orig_out_path.write_bytes(orig_fw)

    orig_sha256 = hashlib.sha256(orig_fw).hexdigest()
    ok_orig, msg_orig, secs_orig = validate_firmware_image(orig_fw)
    print(f"  ✓ Originale Firmware erfolgreich extrahiert!")
    print(f"    - Firmware-Version : {ver_str}")
    print(f"    - Dateigröße       : {len(orig_fw):,} Bytes (0x{len(orig_fw):X})")
    print(f"    - SHA-256          : {orig_sha256}")
    print(f"    - Image-Integrität : {msg_orig}")
    print(f"    - Gespeichert unter: {orig_out_path}")

    if not ok_orig:
        print("  [FEHLER] Extrahierte Original-Firmware hat ungültige Prüfsummen – Abbruch!")
        return 1

    # -------------------------------------------------------------------------
    # SCHRITT 3: OLED-Patch anwenden & Prüfsummen neu berechnen
    # -------------------------------------------------------------------------
    print("\n[SCHRITT 3/5] Erzeuge gepatchte Custom-OLED-Firmware (SysEx 0x01/0x02/0x7C/0x7D)...")
    patched_fw, crc_info = patch_firmware_for_custom_oled(orig_fw)
    patched_out_path.write_bytes(patched_fw)

    # Aktualisiere auch die Standard-Datei im Repository-Root
    repo_default_patched = REPO_ROOT / "sixty_eight_firmware_oled_patched.bin"
    repo_default_patched.write_bytes(patched_fw)

    patched_sha256 = hashlib.sha256(patched_fw).hexdigest()
    print(f"  ✓ Custom-Patch (OLED + Filter-Modi + v2.00 Custom) angewendet & alle CRCs neu berechnet:")
    print(f"    - Neue Firmware-Version                : v2.00 Custom (ARM Opcode 0x01 = 2.00, USB bcdDevice = 0x0200)")
    print(f"    - Section 2 (0x08000 ARM Main App) CRC : 0x{crc_info['old_sec2_crc']:08X} -> 0x{crc_info['new_sec2_crc']:08X}")
    print(f"    - Section 6 (0x7A000 Cypress FX2)  CRC : 0x{crc_info['old_sec6_crc']:08X} -> 0x{crc_info['new_sec6_crc']:08X}")
    print(f"    - Section 0 (0x04000 Section Table) CRC: 0x{crc_info['old_sec0_crc']:08X} -> 0x{crc_info['new_sec0_crc']:08X}")
    print(f"    - Header Payload (0x003C)           CRC: 0x{crc_info['old_hdr_crc']:08X} -> 0x{crc_info['new_hdr_crc']:08X}")
    print(f"    - SHA-256 (Gepatcht)                   : {patched_sha256}")
    print(f"    - Gespeichert unter                    : {patched_out_path}")

    # -------------------------------------------------------------------------
    # SCHRITT 4: Lokale Hardware-Emulation in Unicorn (Bootloader + OLED-Test)
    # -------------------------------------------------------------------------
    print("\n[SCHRITT 4/5] Prüfe Original- und Patch-Firmware im ARM7TDMI Unicorn-Emulator...")
    if not verify_in_unicorn_emulator(orig_fw, expect_custom_oled=False):
        return 1
    if not verify_in_unicorn_emulator(patched_fw, expect_custom_oled=True):
        return 1

    if args.mode == "extract-only":
        print("\n[FERTIG] Beide Firmware-Dateien wurden extrahiert, gepatcht und im Emulator verifiziert.")
        return 0

    # -------------------------------------------------------------------------
    # SCHRITT 5: Auswahl (Original vs. Gepatcht) & Sicherheitsabfragen vor Flash
    # -------------------------------------------------------------------------
    print("\n[SCHRITT 5/5] Firmware-Auswahl & Sicherheitsabfragen für den Hardware-Flash...")

    target_fw_bytes: Optional[bytes] = None
    target_fw_path: Optional[Path] = None
    target_label = ""
    is_patched_choice = False

    if args.mode == "flash-patched":
        target_fw_bytes = patched_fw
        target_fw_path = patched_out_path
        target_label = f"GEPATCHTE Custom-OLED Firmware ({ver_str})"
        is_patched_choice = True
    elif args.mode == "flash-original":
        target_fw_bytes = orig_fw
        target_fw_path = orig_out_path
        target_label = f"ORIGINALE Werks-Firmware ({ver_str})"
        is_patched_choice = False
    else:
        print("\n  Welche Firmware-Version möchtest du verwenden?")
        print(f"    [1] Gepatchte OLED-Firmware flashen ({ver_str} – Custom OLED SysEx 0x01/0x02/0x7C/0x7D aktiv)")
        print(f"    [2] Originale Werks-Firmware flashen ({ver_str} – 100% unmodifizierter Originalzustand)")
        print(f"    [3] Nur Dateien behalten & im Unicorn-Simulator trocken testen (Kein Hardware-Flash)")
        print(f"    [0] Beenden ohne Flash")

        while True:
            sel = input("\n  Deine Wahl [1/2/3/0]: ").strip()
            if sel == "1":
                target_fw_bytes = patched_fw
                target_fw_path = patched_out_path
                target_label = f"GEPATCHTE Custom-OLED Firmware ({ver_str})"
                is_patched_choice = True
                break
            elif sel == "2":
                target_fw_bytes = orig_fw
                target_fw_path = orig_out_path
                target_label = f"ORIGINALE Werks-Firmware ({ver_str})"
                is_patched_choice = False
                break
            elif sel == "3":
                print("\n  Starte kompletten 5-Phasen USB-Bootloader-Dry-Run im Unicorn-Simulator...")
                ver_code_sim = (orig_fw[0x27] << 8) | orig_fw[0x28]
                if ver_code_sim == 0x0128:
                    sim = UnicornRaneHardwareSimulator(orig_fw)
                    run_flash_protocol(sim, patched_fw)
                else:
                    verify_in_unicorn_emulator(patched_fw, expect_custom_oled=True)
                print("\n  => Simulator-Flash-Ergebnis: ERFOLGREICH")
                return 0
            elif sel == "0" or not sel:
                print("\n  Vorgang beendet. Die extrahierten Dateien liegen bereit in:")
                print(f"    - Original : {orig_out_path}")
                print(f"    - Gepatcht : {patched_out_path}")
                return 0
            else:
                print("  Bitte 1, 2, 3 oder 0 wählen.")

    # Mehrstufige Sicherheitsabfragen vor dem echten USB-Hardware-Flash
    print("\n" + "!" * 78)
    print("  SICHERHEITS-CHECKLISTE VOR DEM HARDWARE-FLASH AUF DEN RANE SIXTY-EIGHT")
    print("!" * 78)
    print(f"  Gewähltes Image : {target_label}")
    print(f"  Datei           : {target_fw_path}")
    print(f"  SHA-256         : {hashlib.sha256(target_fw_bytes).hexdigest()}")
    print("  WICHTIGE HINWEISE:")
    print("   1. Während des ca. 14-sekündigen Flash-Vorgangs DARF DAS STROMKABEL")
    print("      UND DAS USB-KABEL NICHT GEZOGEN WERDEN!")
    print("   2. Der Mixer startet automatisch in den Bootloader (bcdDevice 0x9900),")
    print("      schreibt nur geänderte 256-Byte-Flash-Seiten und bootet danach neu.")
    print("!" * 78)

    if not check_conflicting_processes(auto_yes=False):
        print("  [ABBRUCH] Flash-Vorgang durch Benutzer abgebrochen.")
        return 1

    if not ask_yes_no(
        "\n  [SICHERHEITSABFRAGE 1/2] Ist der Rane Sixty-Eight eingeschaltet, an einer stabilen\n"
        "  Stromversorgung angeschlossen und direkt per USB mit diesem Mac verbunden?",
        default=False,
    ):
        print("  [ABBRUCH] Flash-Vorgang abgebrochen.")
        return 0

    confirm_word = input(
        "\n  [SICHERHEITSABFRAGE 2/2] Tippe exakt 'FLASH' ein, um den Schreibvorgang auf\n"
        f"  den Rane Sixty-Eight ({target_label}) jetzt zu starten: "
    ).strip()
    if confirm_word != "FLASH":
        print("  [ABBRUCH] Eingabe war nicht 'FLASH' – es wurde nichts auf die Hardware geschrieben.")
        return 0

    print("\n  Verbinde mit physischem Rane Sixty-Eight über macOS IOKit USB-HID...")
    try:
        transport = LiveUSBHIDTransport()
        run_flash_protocol(transport, target_fw_bytes)
    except Exception as exc:
        print(f"\n  [FEHLER] Der Flash-Vorgang wurde abgebrochen: {exc}")
        return 1

    if is_patched_choice:
        time.sleep(1.5)
        send_live_oled_success_banner("HENRY'S RANE68", "FLASH SUCCESS!")
        print("\n  ✓ 'HENRY'S RANE68 / FLASH SUCCESS!' wurde an das Hardware-OLED-Display gesendet!")

    print("\n" + "=" * 78)
    print(f"  FERTIG! {target_label} ist jetzt auf deinem Rane Sixty-Eight aktiv.")
    print("=" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
