#!/bin/bash
set -e
echo "Installiere aktualisierten RaneHAL.driver nach /Library/Audio/Plug-Ins/HAL/ ..."
sudo cp -R build/RaneHAL.driver /Library/Audio/Plug-Ins/HAL/
echo "Starte CoreAudio Dienst neu..."
sudo killall -9 coreaudiod || true
echo "Fertig! RaneHAL.driver ist aktiv mit direkter DSP-Engine."
