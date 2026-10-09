#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo ./scripts/install.sh"
  exit 1
fi

PRODUCT_DIR=""
if [ -d "${PARENT_DIR}/build/RaneHAL.driver" ]; then
    PRODUCT_DIR="${PARENT_DIR}/build"
elif [ -d "${PARENT_DIR}/RaneHAL.driver" ]; then
    PRODUCT_DIR="${PARENT_DIR}"
elif [ -d "${SCRIPT_DIR}/RaneHAL.driver" ]; then
    PRODUCT_DIR="${SCRIPT_DIR}"
else
    echo "Build products missing. Please run ./build.sh first!"
    exit 1
fi

PLIST_PATH=""
if [ -f "${PARENT_DIR}/src/midi-agent/org.openrane.sixtyeight.midi-agent.plist" ]; then
    PLIST_PATH="${PARENT_DIR}/src/midi-agent/org.openrane.sixtyeight.midi-agent.plist"
elif [ -f "${PARENT_DIR}/org.openrane.sixtyeight.midi-agent.plist" ]; then
    PLIST_PATH="${PARENT_DIR}/org.openrane.sixtyeight.midi-agent.plist"
elif [ -f "${PRODUCT_DIR}/org.openrane.sixtyeight.midi-agent.plist" ]; then
    PLIST_PATH="${PRODUCT_DIR}/org.openrane.sixtyeight.midi-agent.plist"
elif [ -f "${SCRIPT_DIR}/org.openrane.sixtyeight.midi-agent.plist" ]; then
    PLIST_PATH="${SCRIPT_DIR}/org.openrane.sixtyeight.midi-agent.plist"
fi

echo "========================================="
echo "   Installing Rane User-Space Driver     "
echo "========================================="

echo "[1/4] Installing HAL Audio Plugin..."
mkdir -p /Library/Audio/Plug-Ins/HAL
rm -rf /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
cp -R "${PRODUCT_DIR}/RaneHAL.driver" /Library/Audio/Plug-Ins/HAL/
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
chmod -R 755 /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
xattr -cr /Library/Audio/Plug-Ins/HAL/RaneHAL.driver || true
codesign --force --deep --sign - /Library/Audio/Plug-Ins/HAL/RaneHAL.driver || true

echo "[2/4] Installing MIDI LaunchAgent & Test Utilities..."
mkdir -p "/Library/Application Support/RaneDriver"
cp "${PRODUCT_DIR}/RaneMIDIAgent" "/Library/Application Support/RaneDriver/RaneMIDIAgent"
chmod 755 "/Library/Application Support/RaneDriver/RaneMIDIAgent"
if [ -f "${PRODUCT_DIR}/rane-stresstest" ]; then
    cp "${PRODUCT_DIR}/rane-stresstest" "/Library/Application Support/RaneDriver/rane-stresstest"
    chmod 755 "/Library/Application Support/RaneDriver/rane-stresstest"
fi
if [ -f "${PRODUCT_DIR}/rane-selftest" ]; then
    cp "${PRODUCT_DIR}/rane-selftest" "/Library/Application Support/RaneDriver/rane-selftest"
    chmod 755 "/Library/Application Support/RaneDriver/rane-selftest"
fi

echo "[3/4] Installing Control Panel & LaunchAgent..."
if [ -d "${PRODUCT_DIR}/Rane Sixty-Eight Control Panel.app" ]; then
    rm -rf "/Applications/Rane Sixty-Eight Control Panel.app"
    cp -R "${PRODUCT_DIR}/Rane Sixty-Eight Control Panel.app" "/Applications/"
fi
mkdir -p /Library/LaunchAgents
rm -f /Library/LaunchAgents/com.dieckmann.rane.midi-agent.plist
if [ -n "${PLIST_PATH}" ]; then
    cp "${PLIST_PATH}" /Library/LaunchAgents/org.openrane.sixtyeight.midi-agent.plist
    chmod 644 /Library/LaunchAgents/org.openrane.sixtyeight.midi-agent.plist
fi

CONSOLE_USER=$(stat -f "%Su" /dev/console)
if [ -n "${CONSOLE_USER}" ] && [ "${CONSOLE_USER}" != "root" ]; then
    USER_ID=$(id -u "${CONSOLE_USER}")
    echo "Loading LaunchAgent for user ${CONSOLE_USER} (UID: ${USER_ID})..."
    launchctl bootout "gui/${USER_ID}/com.dieckmann.rane.midi-agent" 2>/dev/null || true
    launchctl bootout "gui/${USER_ID}/org.openrane.sixtyeight.midi-agent" 2>/dev/null || true
    pkill -9 -x RaneMIDIAgent 2>/dev/null || true
    sleep 1
    launchctl bootstrap "gui/${USER_ID}" /Library/LaunchAgents/org.openrane.sixtyeight.midi-agent.plist 2>/dev/null || true
fi

echo "[4/4] Restarting CoreAudio driver service & coreaudiod..."
killall -9 coreaudiod com.apple.audio.Core-Audio-Driver-Service 2>/dev/null || true
launchctl kickstart -k system/com.apple.audio.coreaudiod 2>/dev/null || true

echo "========================================="
echo "   Installation Completed Successfully!  "
echo "========================================="
echo "Check Audio MIDI Setup to select your Rane Sixty-Eight Mixer."
