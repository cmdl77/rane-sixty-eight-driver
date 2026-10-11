/* SPDX-License-Identifier: MIT */
/* test_codec.cpp - Unit tests for Rane PCM codec */

#include "../src/protocol/rane_codec.h"
#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>

void test_rane_codec_roundtrip() {
    std::cout << "[TEST] Running Rane multi-channel (12 In / 10 Out) PCM codec roundtrip test..." << std::endl;

    // Test 12 Channels (IN)
    {
        float original[RANE_CHANNELS_IN];
        for (int ch = 0; ch < RANE_CHANNELS_IN; ++ch) {
            original[ch] = (float)(ch - 6) / 6.0f;
        }

        uint8_t wireFrame[RANE_IN_FRAME_SIZE];
        std::memset(wireFrame, 0, sizeof(wireFrame));

        rane_encode_frame_float_to_s24(wireFrame, original, RANE_CHANNELS_IN);

        float decoded[RANE_CHANNELS_IN];
        std::memset(decoded, 0, sizeof(decoded));

        rane_decode_frame_s24_to_float(decoded, wireFrame, RANE_CHANNELS_IN);

        for (int ch = 0; ch < RANE_CHANNELS_IN; ++ch) {
            float diff = std::fabs(original[ch] - decoded[ch]);
            assert(diff < 0.0001f);
        }
    }

    // Test 10 Channels (OUT)
    {
        float original[RANE_CHANNELS_OUT];
        for (int ch = 0; ch < RANE_CHANNELS_OUT; ++ch) {
            original[ch] = (float)(ch - 5) / 5.0f;
        }

        uint8_t wireFrame[RANE_OUT_FRAME_SIZE];
        std::memset(wireFrame, 0, sizeof(wireFrame));

        rane_encode_frame_float_to_s24(wireFrame, original, RANE_CHANNELS_OUT);

        float decoded[RANE_CHANNELS_OUT];
        std::memset(decoded, 0, sizeof(decoded));

        rane_decode_frame_s24_to_float(decoded, wireFrame, RANE_CHANNELS_OUT);

        for (int ch = 0; ch < RANE_CHANNELS_OUT; ++ch) {
            float diff = std::fabs(original[ch] - decoded[ch]);
            assert(diff < 0.0001f);
        }
    }

    std::cout << "[PASS] Rane 12 In / 10 Out PCM codec roundtrip test passed." << std::endl;
}

int main() {
    test_rane_codec_roundtrip();
    return 0;
}
