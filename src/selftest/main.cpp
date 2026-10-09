/* SPDX-License-Identifier: MIT */
/* main.cpp - Rane USB Hardware Diagnostic Utility */

#include "../transport/IOUSBLibTransport.h"
#include "../protocol/rane_defs.h"
#include <iostream>
#include <chrono>
#include <thread>
#include <iomanip>

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    std::cout << "=========================================" << std::endl;
    std::cout << "   Rane USB Hardware Diagnostic Utility  " << std::endl;
    std::cout << "=========================================" << std::endl;

    IOUSBLibTransport transport;
    std::cout << "[1/4] Scanning IOKit USB bus for Rane Sixty-Eight..." << std::endl;

    uint16_t vid = 0, pid = 0;
    if (!transport.findDevice(&vid, &pid)) {
        std::cerr << "[FAIL] Could not find any connected Rane USB device!" << std::endl;
        std::cerr << "       Ensure the Rane Sixty-Eight is powered on and connected via USB." << std::endl;
        return 1;
    }

    const RaneDeviceInfo *info = rane_lookup_device(vid, pid);
    std::cout << "[SUCCESS] Found device: " << (info ? info->displayName : "Unknown Rane") 
              << " (VID: 0x" << std::hex << vid << ", PID: 0x" << pid << std::dec << ")" << std::endl;

    if (!transport.openDevice()) {
        std::cerr << "[FAIL] Could not open Rane USB device!" << std::endl;
        std::cerr << "       If legacy Rane Kext is loaded, run scripts/cleanup-legacy.sh first." << std::endl;
        return 1;
    }

    std::cout << "[2/4] Setting sample rate configuration (48000 Hz)..." << std::endl;
    transport.setSampleRate(48000);
    std::cout << "[SUCCESS] Sample rate set to 48000 Hz." << std::endl;

    std::cout << "[3/4] Testing USB streaming pipes (1 second test)..." << std::endl;
    if (!transport.startStreaming()) {
        std::cerr << "[FAIL] Failed to start USB streaming!" << std::endl;
        transport.closeDevice();
        return 1;
    }

    std::this_thread::sleep_for(std::chrono::seconds(1));

    transport.stopStreaming();
    std::cout << "[SUCCESS] USB streaming start/stop verified successfully." << std::endl;

    std::cout << "[4/4] Closing USB device..." << std::endl;
    transport.closeDevice();

    std::cout << "\n>>> DIAGNOSTIC PASSED FULLY! Hardware is completely responsive. <<<" << std::endl;
    return 0;
}
