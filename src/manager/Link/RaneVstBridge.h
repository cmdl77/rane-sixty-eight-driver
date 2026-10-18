/* SPDX-License-Identifier: MIT */
/* RaneVstBridge.h - Universal VST 2.4 & VST 3 C Bridge for Rane Sixty-Eight Host */

#ifndef RANE_VST_BRIDGE_H
#define RANE_VST_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// VST 2.4 C ABI
// ============================================================================
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

// Lifecycle: Load, initialize, and activate VST2 plugin for real-time processing
AEffect* rane_vst_load(const char* bundlePath, void** outBundle, double sampleRate, int blockSize);

// Real-time audio processing (stereo)
void rane_vst_process(AEffect* effect, const float* inL, const float* inR, float* outL, float* outR, int32_t frames);

// Real-time MIDI event & MIDI Clock (0xF8) delivery to VST2 plugin (effProcessEvents)
void rane_vst_send_midi(AEffect* effect, uint8_t status, uint8_t data1, uint8_t data2, int32_t deltaFrames);

// Host Tempo (BPM) & Transport synchronization (shared by VST2 & VST3)
void rane_vst_set_tempo(double bpm, double sampleRate, bool isPlaying, bool sendMidiClock);

// Editor / GUI controls (VST2)
bool rane_vst_get_editor_rect(AEffect* effect, int* outW, int* outH);
void rane_vst_open_editor(AEffect* effect, void* nsViewPtr);
void rane_vst_close_editor(AEffect* effect);
void rane_vst_edit_idle(AEffect* effect);

// Cleanup and teardown (VST2)
void rane_vst_close(AEffect* effect, void* bundle);

// ============================================================================
// VST 3 C ABI (Opaque Instance Handle)
// ============================================================================
typedef struct RaneVst3Instance RaneVst3Instance;
typedef void (*RaneVstResizeCallback)(void* context, int32_t width, int32_t height);

// Lifecycle: Load, initialize, and activate VST3 plugin (.vst3) for real-time processing
RaneVst3Instance* rane_vst3_load(const char* bundlePath, double sampleRate, int blockSize);

// Real-time audio processing (stereo 32-bit float) with ProcessContext (BPM/PPQ), ParameterChanges & Events
void rane_vst3_process(RaneVst3Instance* inst, const float* inL, const float* inR, float* outL, float* outR, int32_t frames);

// Real-time MIDI event delivery to VST3 plugin (Note On/Off, CC -> IMidiMapping / LegacyCCOut)
void rane_vst3_send_midi(RaneVst3Instance* inst, uint8_t status, uint8_t data1, uint8_t data2, int32_t deltaFrames);

// Editor / GUI controls (VST3 IPlugView NSView attachment)
bool rane_vst3_get_editor_rect(RaneVst3Instance* inst, int* outW, int* outH);
bool rane_vst3_open_editor(RaneVst3Instance* inst, void* nsViewPtr);
void rane_vst3_close_editor(RaneVst3Instance* inst);
void rane_vst3_set_focus(RaneVst3Instance* inst, bool hasFocus);
bool rane_vst3_check_can_resize(RaneVst3Instance* inst);
void rane_vst3_set_resize_callback(RaneVst3Instance* inst, RaneVstResizeCallback cb, void* context);
void rane_vst3_sync_all_params_to_processor(RaneVst3Instance* inst);

// Cleanup and teardown (VST3)
void rane_vst3_close(RaneVst3Instance* inst);

#ifdef __cplusplus
}
#endif

#endif /* RANE_VST_BRIDGE_H */
