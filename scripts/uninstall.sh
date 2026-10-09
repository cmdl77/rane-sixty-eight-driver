#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo ./scripts/uninstall.sh"
  exit 1
fi

echo "========================================="
echo "   Uninstalling Rane User-Space Driver   "
echo "========================================="

CONSOLE_USER=$(stat -f "%Su" /dev/console)
if [ -n "${CONSOLE_USER}" ] && [ "${CONSOLE_USER}" != "root" ]; then
    USER_ID=$(id -u "${CONSOLE_USER}")
    echo "Unloading LaunchAgent for user ${CONSOLE_USER}..."
    launchctl bootout "gui/${USER_ID}/org.openrane.sixtyeight.midi-agent" 2>/dev/null || true
    launchctl bootout "gui/${USER_ID}/com.dieckmann.rane.midi-agent" 2>/dev/null || true
fi

echo "Removing driver files..."
rm -rf /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
rm -rf "/Library/Application Support/RaneDriver"
rm -f /Library/LaunchAgents/org.openrane.sixtyeight.midi-agent.plist
rm -f /Library/LaunchAgents/com.dieckmann.rane.midi-agent.plist

echo "Restarting coreaudiod..."
killall -9 coreaudiod || true

echo "========================================="
echo "   Uninstallation Complete!              "
echo "========================================="
