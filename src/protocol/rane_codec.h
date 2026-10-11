/* SPDX-License-Identifier: MIT */
/* rane_codec.h - Multi-channel 24-bit PCM codec for Rane Sixty-Eight USB audio. */
#ifndef RANE_CODEC_H
#define RANE_CODEC_H

#include <stdint.h>
#include <stddef.h>
#include "rane_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Convert Float32 audio samples to S24_3LE wire frame */
void rane_encode_frame_float_to_s24(uint8_t *dstS24Frame, const float *srcFloat, int channels);

/* Convert S24_3LE wire frame to Float32 audio samples */
void rane_decode_frame_s24_to_float(float *dstFloat, const uint8_t *srcS24Frame, int channels);

#ifdef __cplusplus
}
#endif

#endif /* RANE_CODEC_H */
