#!/bin/bash
set -e
echo "Entferne alten Treiber..."
sudo rm -rf /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
echo "Installiere aktualisierten RaneHAL.driver nach /Library/Audio/Plug-Ins/HAL/ ..."
sudo cp -R build/RaneHAL.driver /Library/Audio/Plug-Ins/HAL/
echo "Setze korrekte Berechtigungen..."
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
sudo chmod -R 755 /Library/Audio/Plug-Ins/HAL/RaneHAL.driver
echo "Starte CoreAudio Dienst neu..."
sudo killall -9 coreaudiod || true
echo "Warte auf CoreAudio Initialisierung..."
sleep 2
echo "Fertig! RaneHAL.driver ist aktiv."
