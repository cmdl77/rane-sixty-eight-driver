/* SPDX-License-Identifier: MIT */
/* rane_codec.c - Multi-channel 24-bit PCM codec implementation */

#include "rane_codec.h"
#include <math.h>

static const float kInvS24Scale = 1.0f / 8388608.0f;
static const float kS24Scale    = 8388607.0f;

static inline int32_t float_to_s24(float v) {
    if (v >= 1.0f) return 8388607;       /*  0x7FFFFF */
    if (v <= -1.0f) return -8388608;     /* -0x800000 */
    return (int32_t)lrintf(v * kS24Scale);
}

static inline float s24_to_float(int32_t v) {
    /* Fast branchless sign extension from 24-bit to 32-bit arithmetic integer */
    int32_t extended = (v << 8) >> 8;
    return (float)extended * kInvS24Scale;
}

void rane_encode_frame_float_to_s24(uint8_t *dstS24Frame, const float *srcFloat, int channels) {
    for (int ch = 0; ch < channels; ++ch) {
        int32_t val = float_to_s24(srcFloat[ch]);
        dstS24Frame[ch * 3 + 0] = (uint8_t)(val & 0xFF);
        dstS24Frame[ch * 3 + 1] = (uint8_t)((val >> 8) & 0xFF);
        dstS24Frame[ch * 3 + 2] = (uint8_t)((val >> 16) & 0xFF);
    }
}

void rane_decode_frame_s24_to_float(float *dstFloat, const uint8_t *srcS24Frame, int channels) {
    for (int ch = 0; ch < channels; ++ch) {
        int32_t val = (int32_t)srcS24Frame[ch * 3 + 0] |
                      ((int32_t)srcS24Frame[ch * 3 + 1] << 8) |
                      ((int32_t)srcS24Frame[ch * 3 + 2] << 16);
        dstFloat[ch] = s24_to_float(val);
    }
}
