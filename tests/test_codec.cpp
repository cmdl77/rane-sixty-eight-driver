/* SPDX-License-Identifier: MIT */
/* test_codec.cpp - Unit tests for Rane PCM codec */

#include "../src/protocol/rane_codec.h"
#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>

void test_rane_codec_roundtrip() {
    std::cout << "[TEST] Running Rane 16-channel PCM codec roundtrip test..." << std::endl;

    float original[RANE_CHANNELS];
    for (int ch = 0; ch < RANE_CHANNELS; ++ch) {
        original[ch] = (float)(ch - 8) / 8.0f;
    }

    uint8_t wireFrame[RANE_OUT_FRAME_SIZE];
    std::memset(wireFrame, 0, sizeof(wireFrame));

    rane_encode_frame_float_to_s24(wireFrame, original);

    float decoded[RANE_CHANNELS];
    std::memset(decoded, 0, sizeof(decoded));

    rane_decode_frame_s24_to_float(decoded, wireFrame);

    for (int ch = 0; ch < RANE_CHANNELS; ++ch) {
        float diff = std::fabs(original[ch] - decoded[ch]);
        assert(diff < 0.0001f);
    }

    std::cout << "[PASS] Rane 16-channel PCM codec roundtrip test passed." << std::endl;
}

int main() {
    test_rane_codec_roundtrip();
    return 0;
}
