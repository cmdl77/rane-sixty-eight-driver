/* SPDX-License-Identifier: MIT */
/* test_packet.cpp - Unit tests for Rane USB packet packing */

#include "../src/protocol/rane_packet.h"
#include <cassert>
#include <cstring>
#include <iostream>

void test_rane_packet_packing() {
    std::cout << "[TEST] Running Rane packet packing test..." << std::endl;

    uint8_t packet[RANE_OUT_PKT_SIZE];
    std::memset(packet, 0, sizeof(packet));

    float floatFrames[RANE_FRAMES_PER_PACKET * RANE_CHANNELS];
    for (size_t i = 0; i < sizeof(floatFrames)/sizeof(floatFrames[0]); ++i) {
        floatFrames[i] = 0.5f;
    }

    rane_pack_out_packet(packet, floatFrames, RANE_FRAMES_PER_PACKET);

    float decodedFrames[RANE_FRAMES_PER_PACKET * RANE_CHANNELS];
    rane_unpack_in_packet(decodedFrames, packet, RANE_FRAMES_PER_PACKET);

    assert(std::fabs(decodedFrames[0] - 0.5f) < 0.001f);

    std::cout << "[PASS] Rane packet packing test passed." << std::endl;
}

int main() {
    test_rane_packet_packing();
    return 0;
}
