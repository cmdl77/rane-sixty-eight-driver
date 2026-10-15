/* SPDX-License-Identifier: MIT */
/* RaneVstBridge.h - Universal VST 2.4 C Bridge for Rane Sixty-Eight Host */

#ifndef RANE_VST_BRIDGE_H
#define RANE_VST_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

struct AEffect;
typedef intptr_t (*audioMasterCallback)(struct AEffect* effect, int32_t opcode, int32_t index, intptr_t value, void* ptr, float opt);

typedef struct {
    int16_t top;
    int16_t left;
    int16_t bottom;
    int16_t right;
} ERect;

typedef struct AEffect {
    int32_t magic;
    int32_t (*dispatcher)(struct AEffect* effect, int32_t opcode, int32_t index, intptr_t value, void* ptr, float opt);
    void (*process)(struct AEffect* effect, float** inputs, float** outputs, int32_t sampleframes);
    void (*setParameter)(struct AEffect* effect, int32_t index, float parameter);
    float (*getParameter)(struct AEffect* effect, int32_t index);
    int32_t numPrograms;
    int32_t numParams;
    int32_t numInputs;
    int32_t numOutputs;
    int32_t flags;
    void* resvd1;
    void* resvd2;
    int32_t initialDelay;
    int32_t realQualities;
    int32_t offQualities;
    float ioRatio;
    void* object;
    void* user;
    int32_t uniqueID;
    int32_t version;
    void (*processReplacing)(struct AEffect* effect, float** inputs, float** outputs, int32_t sampleframes);
    void (*processDoubleReplacing)(struct AEffect* effect, double** inputs, double** outputs, int32_t sampleframes);
    char future[56];
} AEffect;

typedef AEffect* (*vstPluginFuncPtr)(audioMasterCallback audioMaster);

// Inspection: Scans a bundle on disk without keeping it open
bool rane_vst_inspect(const char* bundlePath, char* outName, int nameLen, char* outVendor, int vendorLen, int* outInputs, int* outOutputs);

// Lifecycle: Load, initialize, and activate plugin for real-time processing
AEffect* rane_vst_load(const char* bundlePath, void** outBundle, double sampleRate, int blockSize);

// Real-time audio processing (stereo)
void rane_vst_process(AEffect* effect, const float* inL, const float* inR, float* outL, float* outR, int32_t frames);

// Editor / GUI controls
bool rane_vst_get_editor_rect(AEffect* effect, int* outW, int* outH);
void rane_vst_open_editor(AEffect* effect, void* nsViewPtr);
void rane_vst_close_editor(AEffect* effect);

// Cleanup and teardown
void rane_vst_close(AEffect* effect, void* bundle);

#ifdef __cplusplus
}
#endif

#endif /* RANE_VST_BRIDGE_H */
