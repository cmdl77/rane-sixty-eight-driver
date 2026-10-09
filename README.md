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

---

## 📸 Screenshots

| 🎛 Mixer Audio & Buffer Latency | 🎚 PGM Channels 1–4 Routing |
| :---: | :---: |
| ![Mixer Audio](docs/screenshots/tab1_mixer_audio.png) | ![PGM Channels](docs/screenshots/tab2_pgm_channels.png) |

| 🎹 Live MIDI Monitor & Channel Setup | ⚙️ System Status & Hardware LED Check |
| :---: | :---: |
| ![Live MIDI](docs/screenshots/tab3_live_midi.png) | ![System Status](docs/screenshots/tab4_system_status.png) |

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

## 🛠 Features & Highlights

- **16-Channel Audio (16 In / 16 Out):** Full support for all 4 stereo PGM decks, Aux, Mic, Session In/Out, and Sampler.
- **Ultra-Low Latency:** Dynamic buffer scaling from **64 samples (~1.3 ms)** for turntablism and fast scratching up to 2048 samples.
- **Dual-USB Port Support:** Connect computer to USB Port A or USB Port B for seamless DJ handoffs.
- **Bidirectional MIDI:** Complete control mapping and hardware LED feedback (Cue buttons, FlexFX, side control strips).
- **Native Apple Silicon & Intel:** Built as a Universal 2 binary running natively on M1, M2, M3, M4 and Intel Macs.
- **Built-in Hardware LED Diagnostic Check:** Integrated chaser and full-board light check tool in the Control Panel.

---

## 🏗 Building from Source

For developers who wish to compile the driver themselves:

```bash
git clone https://github.com/cmdl77/rane-sixty-eight-driver.git
cd rane-sixty-eight-driver
./build.sh
```

Prerequisites: Xcode Command Line Tools (`xcode-select --install`) and CMake (`brew install cmake`).

Detailed pipeline explanations, audio codec formulas, and ring buffer internals can be found in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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
