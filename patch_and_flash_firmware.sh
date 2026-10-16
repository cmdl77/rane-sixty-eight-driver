#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rane Sixty-Eight Firmware Extractor, OLED Patcher & Hardware Flasher Wrapper
#
# Offizieller Download von Serato Scratch Live 2.5 (Account erforderlich):
#   https://serato.com/scratchlive/downloads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "[FEHLER] python3 wurde nicht gefunden. Bitte Xcode Command Line Tools installieren:"
    echo "         xcode-select --install"
    exit 1
fi

exec python3 "${SCRIPT_DIR}/tools/rane_firmware_patcher_and_flasher.py" "$@"
