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
 * Packs up to 48 frames of Float32 audio (10 channels per frame) into a USB OUT packet (up to 1440 bytes).
 */
void rane_pack_out_packet(uint8_t *pkt, const float *floatFrames48, size_t frameCount);

/*
 * Unpacks a USB IN packet (up to 1728 bytes) into up to 48 frames of Float32 audio (12 channels per frame).
 */
void rane_unpack_in_packet(float *floatFrames48, const uint8_t *pkt, size_t frameCount);

#ifdef __cplusplus
}
#endif

#endif /* RANE_PACKET_H */
