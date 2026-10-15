/* SPDX-License-Identifier: MIT */
/* RaneLinkBridge.h - C Interface for Ableton Link in Swift */

#ifndef RANE_LINK_BRIDGE_H
#define RANE_LINK_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include "RaneVstBridge.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*RaneLinkPeersCallback)(uint64_t peers);
typedef void (*RaneLinkTempoCallback)(double bpm);

bool rane_link_init(double initial_bpm);
void rane_link_enable(bool enable);
bool rane_link_is_enabled(void);
uint64_t rane_link_get_num_peers(void);
double rane_link_get_tempo(void);
void rane_link_set_tempo(double bpm);
void rane_link_set_callbacks(RaneLinkPeersCallback peers_cb, RaneLinkTempoCallback tempo_cb);
void rane_link_destroy(void);

#ifdef __cplusplus
}
#endif

#endif /* RANE_LINK_BRIDGE_H */
