/* SPDX-License-Identifier: MIT */
/* rane_packet.h - USB packet packer/unpacker for Rane Sixty-Eight */
#ifndef RANE_PACKET_H
#define RANE_PACKET_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "rane_defs.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Packs 48 frames of Float32 audio (16 channels per frame) into a 2304-byte USB OUT packet.
 */
void rane_pack_out_packet(uint8_t *pkt, const float *floatFrames48, size_t frameCount);

/*
 * Unpacks a 2304-byte USB IN packet into 48 frames of Float32 audio (16 channels per frame).
 */
void rane_unpack_in_packet(float *floatFrames48, const uint8_t *pkt, size_t frameCount);

#ifdef __cplusplus
}
#endif

#endif /* RANE_PACKET_H */
