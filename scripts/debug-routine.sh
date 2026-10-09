#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

echo "========================================================="
echo "   Rane Sixty-Eight Comprehensive End-to-End Debugger    "
echo "========================================================="

echo ""
echo "[Step 1/5] Building all driver components..."
cd "${PROJECT_DIR}"
./build.sh

echo ""
echo "[Step 2/5] Checking connected USB devices for Rane Sixty-Eight..."
system_profiler SPUSBDataType | grep -A 10 "Rane SIXTY-EIGHT" || echo "[WARN] Rane Sixty-Eight USB device not detected by system_profiler!"

echo ""
echo "[Step 3/5] Installing HAL Driver & MIDI Agent (requires sudo)..."
if [ "$EUID" -ne 0 ]; then
    echo "Running install with sudo..."
    sudo "${PROJECT_DIR}/scripts/install.sh"
else
    "${PROJECT_DIR}/scripts/install.sh"
fi

echo ""
echo "[Step 4/5] Monitoring System Logs for RaneHAL & CoreAudio (5 seconds)..."
/usr/bin/log show --style syslog --predicate 'process CONTAINS "coreaudio" or message CONTAINS "Rane"' --last 1m | tail -n 40

echo ""
echo "[Step 5/5] Verifying CoreAudio & CoreMIDI Driver Status..."
cat << 'EOF' > /tmp/rane_system_verify.cpp
#include <CoreAudio/AudioHardware.h>
#include <CoreMIDI/CoreMIDI.h>
#include <CoreFoundation/CoreFoundation.h>
#include <iostream>

int main() {
    std::cout << "--- 1. CoreAudio Driver Inspection ---" << std::endl;
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &dataSize);
    if (status != noErr) {
        std::cout << "[FAIL] AudioObjectGetPropertyDataSize failed: " << status << std::endl;
        return 1;
    }

    UInt32 numDevices = dataSize / sizeof(AudioObjectID);
    AudioObjectID devices[64];
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &dataSize, devices);

    bool raneAudioFound = false;
    for (UInt32 i = 0; i < numDevices; i++) {
        CFStringRef name = nullptr, uid = nullptr;
        UInt32 sz = sizeof(name);
        AudioObjectPropertyAddress nAddr = { kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        AudioObjectPropertyAddress uAddr = { kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };

        AudioObjectGetPropertyData(devices[i], &nAddr, 0, nullptr, &sz, &name);
        sz = sizeof(uid);
        AudioObjectGetPropertyData(devices[i], &uAddr, 0, nullptr, &sz, &uid);

        char nameBuf[128] = "Unknown", uidBuf[128] = "Unknown";
        if (name) CFStringGetCString(name, nameBuf, sizeof(nameBuf), kCFStringEncodingUTF8);
        if (uid) CFStringGetCString(uid, uidBuf, sizeof(uidBuf), kCFStringEncodingUTF8);

        if (uid && (CFEqual(uid, CFSTR("org.openrane.sixtyeight")) || CFEqual(uid, CFSTR("de.dieckmann.rane.sixtyeight")))) {
            raneAudioFound = true;
            std::cout << "  [SUCCESS] Audio Device Registered: Name=\"" << nameBuf << "\", UID=\"" << uidBuf << "\", ID=" << devices[i] << std::endl;
        }

        if (name) CFRelease(name);
        if (uid) CFRelease(uid);
    }

    std::cout << "\n--- 2. CoreMIDI Driver Inspection ---" << std::endl;
    ItemCount numSources = MIDIGetNumberOfSources();
    ItemCount numDests = MIDIGetNumberOfDestinations();
    bool raneSourceFound = false, raneDestFound = false;

    for (ItemCount i = 0; i < numSources; i++) {
        MIDIEndpointRef ep = MIDIGetSource(i);
        CFStringRef name = nullptr;
        MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &name);
        if (name && CFStringFind(name, CFSTR("Rane"), 0).location != kCFNotFound) {
            raneSourceFound = true;
            char buf[128];
            CFStringGetCString(name, buf, sizeof(buf), kCFStringEncodingUTF8);
            std::cout << "  [SUCCESS] MIDI Virtual Source Registered: \"" << buf << "\"" << std::endl;
        }
        if (name) CFRelease(name);
    }

    for (ItemCount i = 0; i < numDests; i++) {
        MIDIEndpointRef ep = MIDIGetDestination(i);
        CFStringRef name = nullptr;
        MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &name);
        if (name && CFStringFind(name, CFSTR("Rane"), 0).location != kCFNotFound) {
            raneDestFound = true;
            char buf[128];
            CFStringGetCString(name, buf, sizeof(buf), kCFStringEncodingUTF8);
            std::cout << "  [SUCCESS] MIDI Virtual Destination Registered: \"" << buf << "\"" << std::endl;
        }
        if (name) CFRelease(name);
    }

    if (raneAudioFound && raneSourceFound && raneDestFound) {
        std::cout << "\n=========================================================" << std::endl;
        std::cout << "   ALL VERIFICATIONS PASSED 100%! DRIVER IS FULLY ACTIVE   " << std::endl;
        std::cout << "=========================================================" << std::endl;
        return 0;
    } else {
        std::cout << "\n[FAIL] Driver component missing: Audio=" << raneAudioFound << " MIDI_Source=" << raneSourceFound << " MIDI_Dest=" << raneDestFound << std::endl;
        return 1;
    }
}
EOF
clang++ -std=c++17 -framework CoreAudio -framework CoreMIDI -framework CoreFoundation /tmp/rane_system_verify.cpp -o /tmp/rane_system_verify
/tmp/rane_system_verify

echo ""
echo "========================================================="
echo "   All Diagnostic Checks Finished Successfully!          "
echo "========================================================="
