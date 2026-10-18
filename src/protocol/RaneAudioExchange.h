/* SPDX-License-Identifier: MIT */
/* RaneAudioExchange.h - Low-Latency Shared Memory Audio Exchange between HAL Driver and Manager App */

#ifndef RANE_AUDIO_EXCHANGE_H
#define RANE_AUDIO_EXCHANGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define RANE_AUDIO_EXCHANGE_PATH "/var/tmp/rane_audio_exchange.bin"
#define RANE_AUDIO_EXCHANGE_MAGIC 0x52414E45U
#define RANE_AUDIO_EXCHANGE_MAX_FRAMES 4096
#define RANE_AUDIO_EXCHANGE_CHANNELS 10
#define RANE_AUDIO_EXCHANGE_NUM_BUFFERS 2

#pragma pack(push, 4)
typedef struct RaneAudioExchange {
    uint32_t magic;
    uint32_t version;
    uint32_t vstActive;
    uint32_t sampleRate;
    uint32_t bufferFrameSize;
    uint32_t driverBufferIdx;
    uint32_t managerBufferIdx;
    uint32_t reserved;
    uint64_t driverCycleCount;
    uint64_t managerCycleCount;
    uint64_t timestampNs;
    float dawOut[RANE_AUDIO_EXCHANGE_NUM_BUFFERS][RANE_AUDIO_EXCHANGE_MAX_FRAMES * RANE_AUDIO_EXCHANGE_CHANNELS];
    float processedOut[RANE_AUDIO_EXCHANGE_NUM_BUFFERS][RANE_AUDIO_EXCHANGE_MAX_FRAMES * RANE_AUDIO_EXCHANGE_CHANNELS];
} RaneAudioExchange;
#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif

static inline float* rane_exchange_get_daw_buffer(RaneAudioExchange* ex, uint32_t bufferIdx) {
    if (!ex) return NULL;
    return ex->dawOut[bufferIdx % RANE_AUDIO_EXCHANGE_NUM_BUFFERS];
}

static inline float* rane_exchange_get_processed_buffer(RaneAudioExchange* ex, uint32_t bufferIdx) {
    if (!ex) return NULL;
    return ex->processedOut[bufferIdx % RANE_AUDIO_EXCHANGE_NUM_BUFFERS];
}

#ifdef __cplusplus
}
#endif

#endif /* RANE_AUDIO_EXCHANGE_H */
