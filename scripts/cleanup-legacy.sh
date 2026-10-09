#!/bin/bash
set -e

echo "========================================="
echo "   Cleaning Legacy Rane Drivers          "
echo "========================================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo ./scripts/cleanup-legacy.sh"
  exit 1
fi

echo "[1/4] Unloading legacy Rane kernel extensions..."
kextunload -f -b com.rane.driver.sixtyeight || true
kextunload -b com.rane.driver.sixtyeight || true
kextunload -p /Library/Extensions/SIXTY-EIGHT.10.9.kext || true
kextunload -b com.rane.driver.coreaudio || true
kmutil unload -f -b com.rane.driver.sixtyeight || true
kmutil unload -b com.rane.driver.sixtyeight || true
kmutil unload -p /Library/Extensions/SIXTY-EIGHT.10.9.kext || true
kmutil unload -b com.rane.driver.coreaudio || true

echo "[2/4] Clearing staging and AuxKC caches..."
kmutil clear-staging || true

echo "[3/4] Removing legacy Kexts, MIDI plugins, frameworks, and helper tools..."
rm -rf /Library/Extensions/SIXTY-EIGHT.10.9.kext || true
rm -rf /Library/Extensions/SIXTY-EIGHT* || true
rm -rf /Library/Extensions/*Sixty* || true
rm -rf /Library/Extensions/*sixty* || true
rm -rf /Library/Extensions/*Rane* || true
rm -rf /Library/Extensions/*rane* || true
rm -rf /Library/StagedExtensions/Library/Extensions/*SIXTY* || true
rm -rf /Library/StagedExtensions/Library/Extensions/*Rane* || true
rm -rf /System/Library/Extensions/RaneSixtyEight.kext || true
rm -rf /Library/Audio/Plug-Ins/HAL/RaneCoreAudio.driver || true
rm -rf "/Library/Audio/MIDI Drivers/SixtyEightMidiDriver.plugin" || true
rm -rf "/Library/Audio/MIDI Drivers/SixtyFourMidiDriver.plugin" || true
rm -rf "/Library/PreferencePanes/SIXTY-EIGHT Audio Control Panel.prefPane" || true
rm -rf "/Library/PreferencePanes/SIXTY-FOUR Audio Control Panel.prefPane" || true
rm -rf "/Library/Frameworks/SIXTY-EIGHTApi.framework" || true
rm -rf "/Library/Frameworks/SixtyFourApi.framework" || true
rm -rf "/Library/LaunchDaemons/com.rane.sixtyeight.daemon.plist" || true
rm -rf "/Library/LaunchDaemons/com.rane.sixtyfour.daemon.plist" || true
rm -rf "/Library/PrivilegedHelperTools/SixtyEightSettingsService" || true
rm -rf "/Library/PrivilegedHelperTools/SixtyFourSettingsService" || true

echo "[4/4] Restarting coreaudiod..."
killall -9 coreaudiod com.apple.audio.Core-Audio-Driver-Service 2>/dev/null || true

echo "========================================="
echo "   Legacy Cleanup Complete!              "
echo "========================================="
