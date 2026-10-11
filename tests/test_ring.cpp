/* SPDX-License-Identifier: MIT */
/* test_ring.cpp - Unit test for RaneRing atomic ring buffer */

#include "../src/engine/RaneRing.h"
#include <cassert>
#include <iostream>

void test_rane_ring_basic() {
    std::cout << "[TEST] Running RaneRing basic test..." << std::endl;

    RaneRing ring;
    assert(ring.init(1024, 1));

    uint8_t writeBuf[128];
    for (int i = 0; i < 128; ++i) writeBuf[i] = (uint8_t)(i + 1);

    size_t pushed = ring.push(writeBuf, 128);
    assert(pushed == 128);
    assert(ring.availableRead() == 128);

    uint8_t readBuf[128];
    size_t popped = ring.pop(readBuf, 128);
    assert(popped == 128);
    assert(ring.availableRead() == 0);

    for (int i = 0; i < 128; ++i) {
        assert(readBuf[i] == (uint8_t)(i + 1));
    }

    // Test byte-level push/pop (MIDI simulation)
    uint8_t midiIn[3] = { 0x90, 0x3C, 0x7F };
    assert(ring.push(midiIn, 3) == 3);
    uint8_t midiByte = 0;
    assert(ring.pop(&midiByte, 1) == 1);
    assert(midiByte == 0x90);
    assert(ring.pop(&midiByte, 1) == 1);
    assert(midiByte == 0x3C);
    assert(ring.pop(&midiByte, 1) == 1);
    assert(midiByte == 0x7F);

    // Test 12-channel frame alignment (48 bytes)
    RaneRing inRing;
    assert(inRing.init(2048, 48));
    uint8_t inFrame[50]; // 50 bytes -> should only push 48 bytes
    assert(inRing.push(inFrame, 50) == 48);
    assert(inRing.availableRead() == 48);
    assert(inRing.pop(inFrame, 50) == 48);

    // Test 10-channel frame alignment (40 bytes)
    RaneRing outRing;
    assert(outRing.init(2048, 40));
    uint8_t outFrame[85]; // 85 bytes -> should only push 80 bytes (2 frames)
    assert(outRing.push(outFrame, 85) == 80);
    assert(outRing.availableRead() == 80);
    assert(outRing.pop(outFrame, 85) == 80);

    std::cout << "[PASS] RaneRing basic and frame alignment tests passed." << std::endl;
}

int main() {
    test_rane_ring_basic();
    return 0;
}
