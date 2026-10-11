/* SPDX-License-Identifier: MIT */
/* test_packet.cpp - Unit tests for Rane USB packet packing */

#include "../src/protocol/rane_packet.h"
#include <cassert>
#include <cstring>
#include <iostream>

void test_rane_packet_packing() {
    std::cout << "[TEST] Running Rane packet packing test (10 Out / 12 In)..." << std::endl;

    // Test OUT packing (10 channels)
    {
        uint8_t packet[RANE_OUT_PKT_SIZE];
        std::memset(packet, 0, sizeof(packet));

        float floatFrames[RANE_FRAMES_PER_PACKET * RANE_CHANNELS_OUT];
        for (size_t i = 0; i < sizeof(floatFrames)/sizeof(floatFrames[0]); ++i) {
            floatFrames[i] = 0.5f;
        }

        rane_pack_out_packet(packet, floatFrames, RANE_FRAMES_PER_PACKET);

        // Verify that the packet was filled
        bool hasNonZero = false;
        for (size_t i = 0; i < sizeof(packet); ++i) {
            if (packet[i] != 0) { hasNonZero = true; break; }
        }
        assert(hasNonZero);
    }

    // Test IN unpacking (12 channels)
    {
        uint8_t inPacket[RANE_IN_PKT_SIZE];
        std::memset(inPacket, 0x40, sizeof(inPacket)); // synthetic data

        float decodedFrames[RANE_FRAMES_PER_PACKET * RANE_CHANNELS_IN];
        std::memset(decodedFrames, 0, sizeof(decodedFrames));

        rane_unpack_in_packet(decodedFrames, inPacket, RANE_FRAMES_PER_PACKET);

        // Verify decoded values are non-zero
        assert(decodedFrames[0] != 0.0f);
    }

    std::cout << "[PASS] Rane packet packing test passed." << std::endl;
}

int main() {
    test_rane_packet_packing();
    return 0;
}
