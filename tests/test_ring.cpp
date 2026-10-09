/* SPDX-License-Identifier: MIT */
/* test_ring.cpp - Unit test for RaneRing atomic ring buffer */

#include "../src/engine/RaneRing.h"
#include <cassert>
#include <iostream>

void test_rane_ring_basic() {
    std::cout << "[TEST] Running RaneRing basic test..." << std::endl;

    RaneRing ring;
    assert(ring.init(1024));

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

    std::cout << "[PASS] RaneRing basic test passed." << std::endl;
}

int main() {
    test_rane_ring_basic();
    return 0;
}
