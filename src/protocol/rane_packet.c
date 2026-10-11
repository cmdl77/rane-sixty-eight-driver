/* SPDX-License-Identifier: MIT */
/* rane_packet.c - USB packet layout implementation */

#include "rane_packet.h"
#include "rane_codec.h"

void rane_pack_out_packet(uint8_t *pkt, const float *floatFrames48, size_t frameCount) {
    if (frameCount > RANE_FRAMES_PER_PACKET) frameCount = RANE_FRAMES_PER_PACKET;

    for (size_t f = 0; f < frameCount; ++f) {
        uint8_t *dstFrame = pkt + (f * RANE_OUT_FRAME_SIZE);
        const float *srcFloatFrame = floatFrames48 + (f * RANE_CHANNELS_OUT);
        rane_encode_frame_float_to_s24(dstFrame, srcFloatFrame, RANE_CHANNELS_OUT);
    }
}

void rane_unpack_in_packet(float *floatFrames48, const uint8_t *pkt, size_t frameCount) {
    if (frameCount > RANE_FRAMES_PER_PACKET) frameCount = RANE_FRAMES_PER_PACKET;

    for (size_t f = 0; f < frameCount; ++f) {
        const uint8_t *srcFrame = pkt + (f * RANE_IN_FRAME_SIZE);
        float *dstFloatFrame = floatFrames48 + (f * RANE_CHANNELS_IN);
        rane_decode_frame_s24_to_float(dstFloatFrame, srcFrame, RANE_CHANNELS_IN);
    }
}
