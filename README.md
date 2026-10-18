<p align="center">
  <img src="docs/screenshots/app_icon.png" width="128" height="128" alt="Rane Sixty-Eight App Icon">
</p>

# 🎧 Rane Sixty-Eight macOS Driver (Apple Silicon M1–M4 & Intel)

[![macOS](https://img.shields.io/badge/macOS-Sonoma%20%7C%20Sequoia%20(15)-black.svg?style=flat&logo=apple)](https://github.com/cmdl77/rane-sixty-eight-driver)
[![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20(M1--M4)%20%7C%20Intel-blue.svg)](https://github.com/cmdl77/rane-sixty-eight-driver)
[![Driver](https://img.shields.io/badge/Type-100%25%20User--Space%20CoreAudio%20HAL-green.svg)](https://github.com/cmdl77/rane-sixty-eight-driver)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-orange.svg?logo=buy-me-a-coffee)](https://buymeacoffee.com/cmdl77)

A modern, high-performance, **100% User-Space CoreAudio HAL Driver** and **MIDI LaunchAgent** for the **Rane Sixty-Eight** DJ mixer on modern macOS versions (macOS 11 Big Sur through macOS 15 Sequoia).

> [!NOTE]
> **Zero Kernel Extensions (Kexts) required!** Runs completely in user-space inside macOS `coreaudiod`. No need to disable System Integrity Protection (SIP) or lower system security on Apple Silicon.

📖 **[Ausführliches Benutzerhandbuch & Dokumentation (User Guide)](docs/USER_GUIDE.md)** mit Schritt-für-Schritt-Anleitungen für alle Tabs, VST2-Effekte, Ableton Link und DJ-Software-Einrichtung (Traktor / Serato / Ableton).

---

## 📸 Screenshots & Interface-Übersicht

| 🎛 Mixer Audio & CoreAudio Latenz | 🎚 PGM Kanäle 1–4 Preamp & Resonanz |
| :---: | :---: |
| [![Mixer Audio](docs/screenshots/tab1_mixer_audio.png)](docs/USER_GUIDE.md#2-tab-1-🎛-mixer-audio--globale-einstellungen) | [![PGM Channels](docs/screenshots/tab2_pgm_channels.png)](docs/USER_GUIDE.md#3-tab-2-🎚-pgm-kanäle-1–4-preamp--phono-setup) |

| ⚡️ FlexFX VST-Host & Ableton Link | 🎹 Controller & Live MIDI-Monitor |
| :---: | :---: |
| [![FlexFX Engine](docs/screenshots/tab3_flexfx_engine.png)](docs/USER_GUIDE.md#4-tab-3-⚡️-flexfx-engine-vst-plugins--ableton-link) | [![Live MIDI](docs/screenshots/tab4_controller_midi.png)](docs/USER_GUIDE.md#5-tab-4-🎹-controller--live-midi-monitor) |

| ⚙️ System Status & Hardware-Diagnose | 🎛 Mini-HUD Modus (Floating Live-Overlay) |
| :---: | :---: |
| [![System Status](docs/screenshots/tab5_system_status.png)](docs/USER_GUIDE.md#6-tab-5-⚙️-system-status-cpu--hardware-diagnose) | [![Mini HUD](docs/screenshots/mini_hud.png)](docs/USER_GUIDE.md#7-mini-hud-modus-floating-live-overlay) |

---

## 🚀 Easy 3-Step Visual Installation (For DJs)

```mermaid
flowchart LR
    A["1. Download Zip<br/>from Releases"] --> B["2. Double-Click<br/>Install.command"]
    B --> C["3. Open Control Panel<br/>& Start Mixing!"]
```

### Step 1: Download Release
Download the pre-compiled **`Rane-Sixty-Eight-macOS-Driver.zip`** from the [Releases](https://github.com/cmdl77/rane-sixty-eight-driver/releases) section and extract it.

### Step 2: One-Click Installation
Double-click **`Install.command`** in the extracted folder. 
Enter your Mac administrator password when prompted. The installer will:
1. Install the CoreAudio HAL audio plugin to `/Library/Audio/Plug-Ins/HAL/`.
2. Clear macOS quarantine flags (`xattr -cr`) to bypass Gatekeeper warnings.
3. Register the background MIDI daemon and launch the Control Panel.

### Step 3: Verified in macOS Audio MIDI Setup
Your **Rane Sixty-Eight** appears immediately in **Traktor Pro, Serato DJ, Ableton Live**, and macOS **Audio MIDI Setup** with **16 Inputs and 16 Outputs** (48.000 Hz, 32-Bit Floating Point):

![macOS Audio-MIDI-Setup](docs/screenshots/audio_midi_setup_rane.png)

---

## 💡 Troubleshooting Gatekeeper on macOS 14 / 15

If macOS shows an alert stating *"Developer cannot be verified"*:
- **macOS Sonoma / Ventura:** Right-click `Rane Sixty-Eight Control Panel.app` → Click **Open** → Confirm **Open**.
- **macOS Sequoia (15):** Open **System Settings** → **Privacy & Security** → Scroll down and click **"Open Anyway"**.

---

## 🛠 Features & Highlights (v2.0.0)

- **22-Kanal Live Audio Pegelanzeige (12 IN / 10 OUT):** Echtzeit VU-Meter für alle 12 Aufnahme-Kanäle (PGM 1–4, FlexFX Send, Main Mix) und 10 Playback-Kanäle (Decks 1–4, FlexFX Return) direkt im Control Panel bei 48 kHz / 32-Bit Float.
- **Vollständige PGM 1–4 Hardware-Synchronisation:**
  - **Feld 1:** Physischer Rückseiten-Schalter (`LINE (CD)` vs. `PHONO` vs. `S/PDIF` – CC 112–115).
  - **Feld 2:** Exakte Drehschalter-Quellenwahl (`PH/CD 1–4`, `USB 1–4`, `AUX 1–4` – CC 116–119).
  - **Feld 3:** Crossfader-Zuweisung (`CROSSFADER A` vs. `POST` vs. `CROSSFADER B` – CC 120–123) im einheitlichen zentrierten Hardware-Badge-Stil.
- **Echtzeit CPU-Auslastungsanzeige:**
  - Kompaktes, farbcodiertes Hardware-Badge mit Micro-Meter-Balken direkt im Header (auf allen Tabs sichtbar, 1-Klick-Sprung zur Systemdiagnose).
  - Detaillierte Systemauslastung mit CPU-Modell- und Kern-Erkennung in Tab 4 (*System Status*).
  - Live CPU-Anzeige im macOS Menüleisten-Widget.
- **Anti-Stutter MIDI-Quittierung & Slider-Drosselung:** Schützt den USB-Bus vor Überlastung beim schnellen Bewegen von Reglern (Phones Tone, LCD-Kontrast).
- **macOS Menüleisten-Widget (Status Item):** Schneller Zugriff auf Puffergröße/Latenz, Verbindungsstatus und Audio MIDI Setup direkt aus der oberen macOS-Menüleiste.
- **Zweisprachig (Deutsch & Englisch):** Vollständige Lokalisierung aller Tabs, Tooltips und Systemmenüs inklusive Versionsanzeige `v2.0.0`.
- **Native Apple Silicon (M1–M4) & Intel:** Kompiliert als Universal 2 Binary für maximale Effizienz und minimale Latenz ohne Rosetta 2.
- **Integrierte Hardware-Diagnose:** LED-Chaser-Lichtcheck und Stresstest direkt im Control Panel.
- **Custom Hardware-OLED-Display & Firmware-Patcher (NEU):**
  - **5 Sekunden Begrüßungstext beim App-Start & Preset-Laden:** Frei konfigurierbarer 2×14-Zeichen-Begrüßungstext im Tab *System Status* (wird auch in den Mixer-Presets gespeichert), der beim Starten der App für 5 Sekunden auf dem physischen Rane Sixty-Eight OLED-Display erscheint und danach automatisch zur originalen `BPM:` / `TIME:`-Anzeige zurückkehrt.
  - **2 Sekunden Ableton Link Status-Toast auf dem Mixer-Display:** Zeigt beim Umschalten von Ableton Link für 2 Sekunden `"AbletonLink on"` bzw. `"AbletonLinkoff"` in Zeile 2 des Hardware-OLEDs an.
  - **Vollautomatischer Firmware-Extractor, OLED-Patcher & USB-Flasher (`./patch_and_flash_firmware.sh`):** Extrahiert und entschlüsselt die originale Firmware direkt aus dem offiziellen Serato Scratch Live 2.5 Download (`Serato Scratch Live 2.5 Mac.zip`) oder `SIXTY-EIGHT.pkg`, patcht das Image, verifiziert alle 7 Sektions-CRCs im lokalen ARM7TDMI-Emulator (`Unicorn`) und lässt den Nutzer mit mehrstufigen Sicherheitsabfragen zwischen **Original-Firmware** und **Gepatchter OLED-Firmware** wählen.

---

## 📺 Custom OLED Firmware Patcher & Hardware Flasher

Um eigene Texte (Start-Begrüßung & Ableton Link Status) auf dem physischen OLED-Display des Rane Sixty-Eight freizuschalten, enthält dieses Repository ein komplettes Patch- und Flash-Skript mit automatischer Abhängigkeitsprüfung und Sicherheitsabfragen:

1. **Offizielles Archiv herunterladen (kostenloser Serato-Account erforderlich):**
   Lade **`Serato Scratch Live 2.5 Mac.zip`** von der offiziellen Serato-Seite herunter:
   👉 **[https://serato.com/scratchlive/downloads](https://serato.com/scratchlive/downloads)**
2. **Patch- & Flash-Assistent starten:**
   ```bash
   ./patch_and_flash_firmware.sh
   ```
3. **Funktionen des Skripts:**
   - Prüft automatisch benötigte Tools (`python3`, `unzip`, `hdiutil`, `pkgutil`, Xcode Command Line Tools, `unicorn`, `capstone`) und installiert fehlende Pakete nach Rückfrage.
   - Extrahiert und entschlüsselt die originale Rane-Firmware (`v1.1E` aus Serato Scratch Live 2.5 bzw. `v1.28` aus `SIXTY-EIGHT.pkg`).
   - Erstellt die gepatchte Custom-OLED-Firmware und prüft beide Versionen vorab im lokalen **ARM7TDMI Unicorn-Emulator** gegen den originalen Hardware-Bootloader.
   - Bietet die Wahl zwischen **[1] Gepatchte OLED-Firmware flashen**, **[2] Originale Werks-Firmware flashen (Rollback)** und **[3] Nur Extrahieren & im Simulator testen**.

📖 **Ausführliche Dokumentation & technische Details zum OLED-Patch:** [**docs/FIRMWARE_PATCH_AND_FLASH.md**](docs/FIRMWARE_PATCH_AND_FLASH.md)

---

## 🏗 Building from Source

For developers who wish to compile the driver themselves:

```bash
git clone https://github.com/cmdl77/rane-sixty-eight-driver.git
cd rane-sixty-eight-driver
./build.sh
```

Prerequisites: Xcode Command Line Tools (`xcode-select --install`) and CMake (`brew install cmake`).

Detailed pipeline explanations, audio codec formulas, and ring buffer internals can be found in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/FIRMWARE_PATCH_AND_FLASH.md](docs/FIRMWARE_PATCH_AND_FLASH.md).

---

## 🙏 Acknowledgments & Credits

Special thanks to the open-source audio & DJ community:
- **[mischa85/Ozzy](https://github.com/mischa85/Ozzy)** for pioneering research into macOS user-space audio drivers and USB reverse engineering for vintage DJ gear.
- **[MCDShema/xone](https://github.com/MCDShema/xone)** for architectural inspiration on isochronous audio streaming and HAL buffer scheduling.
- **[Mixxx Project](https://github.com/mixxxdj/mixxx)** for controller protocol research and community DJ mapping knowledge.

---

## ☕ Support the Project

If this driver brought your Rane Sixty-Eight back to life, consider buying a coffee to support continued development and maintenance:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow.svg?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/cmdl77)

---

## 🤝 Contributing

Contributions, bug reports, and hardware testing on other Rane devices (e.g., Sixty-Four, Sixty-Two, SL4) are warmly welcome! Please feel free to open an Issue or submit a Pull Request.

---

## ⚖️ License & Disclaimer

This project is licensed under the [MIT License](LICENSE).

*Disclaimer: This project is an independent open-source driver developed for hardware interoperability. It is not affiliated with, endorsed by, or sponsored by Rane Corporation or inMusic Brands.*
