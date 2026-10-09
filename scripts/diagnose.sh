#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

echo "========================================="
echo "   Rane Driver System Diagnostics        "
echo "========================================="

echo "\n--- [1] Checking Connected Rane USB Devices ---"
ioreg -p IOUSB -l -b | grep -i -E "rane|13e5|29e2" || echo "No Rane USB devices found in IOKit registry tree."

echo "\n--- [2] Checking Legacy Kext Conflicts ---"
if kextstat | grep -i -E "rane|sixtyeight"; then
    echo "WARNING: Legacy Rane Kernel Extension detected! Please run sudo ./scripts/cleanup-legacy.sh"
else
    echo "OK: No conflicting kernel extensions loaded."
fi

echo "\n--- [3] Checking HAL Driver Installation ---"
if [ -d "/Library/Audio/Plug-Ins/HAL/RaneHAL.driver" ]; then
    echo "OK: /Library/Audio/Plug-Ins/HAL/RaneHAL.driver is installed."
else
    echo "WARNING: Driver not installed. Run sudo ./scripts/install.sh"
fi

echo "\n--- [4] Checking MIDI Agent Status ---"
pgrep -fl RaneMIDIAgent || echo "WARNING: RaneMIDIAgent process is not running."

echo "\n--- [5] CoreAudio System Logs (Last 20 entries) ---"
log show --predicate 'process == "coreaudiod" OR process == "RaneMIDIAgent"' --last 5m | tail -n 20 || true

echo "\n--- [6] Running Hardware Selftest Utility ---"
if [ -f "${SCRIPT_DIR}/build/rane-selftest" ]; then
    "${SCRIPT_DIR}/build/rane-selftest" || true
else
    echo "rane-selftest binary not found. Build first using ./build.sh"
fi

echo "\n========================================="
echo "   Diagnostics Completed                 "
echo "========================================="
