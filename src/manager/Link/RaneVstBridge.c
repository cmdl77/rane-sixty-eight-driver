/* SPDX-License-Identifier: MIT */
/* RaneVstBridge.c - Universal VST 2.4 C Bridge Implementation */

#include "RaneVstBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <math.h>
#include <mach/mach_time.h>

// VST 2.4 Standard Opcodes
#define effOpen                 0
#define effClose                1
#define effSetProgram           2
#define effGetProgram           3
#define effSetProgramName       4
#define effGetProgramName       5
#define effGetParamLabel        6
#define effGetParamDisplay      7
#define effGetParamName         8
#define effSetSampleRate        10
#define effSetBlockSize         11
#define effMainsChanged         12
#define effEditGetRect          13
#define effEditOpen             14
#define effEditClose            15
#define effEditIdle             19
#define effProcessEvents        25
#define effGetEffectName        45
#define effGetVendorString      47
#define effGetProductString     48
#define effGetVendorVersion     49
#define effCanDo                51

// Host opcodes
#define audioMasterAutomate               0
#define audioMasterVersion                1
#define audioMasterGetTime                7
#define audioMasterSizeWindow             15
#define audioMasterGetSampleRate          16
#define audioMasterGetBlockSize           17
#define audioMasterGetCurrentProcessLevel 23
#define audioMasterGetVendorString        32
#define audioMasterGetProductString       33
#define audioMasterGetVendorVersion       34
#define audioMasterCanDo                  37

// VstTimeInfo Flags (VST 2.4 Spec)
#define kVstTransportChanged      (1 << 0)
#define kVstTransportPlaying      (1 << 1)
#define kVstTransportCycleActive  (1 << 2)
#define kVstNanosValid            (1 << 8)
#define kVstPpqPosValid           (1 << 9)
#define kVstTempoValid            (1 << 10)
#define kVstBarsValid             (1 << 11)
#define kVstTimeSigValid          (1 << 13)
#define kVstClockValid            (1 << 15)

// VstEvent Types
#define kVstMidiType              1
#define kVstMidiEventIsRealtime   1

typedef struct VstTimeInfo {
    double samplePos;           // current Position in audio samples
    double sampleRate;          // current Sample Rate in Hz
    double nanoSeconds;         // System Time in nanoseconds
    double ppqPos;              // Musical Position, in Quarter Note (1.0 = 1 Quarter Note)
    double tempo;               // current Tempo in BPM
    double barStartPos;         // last Bar Start Position, in Quarter Note
    double cycleStartPos;       // Cycle Start, in Quarter Note
    double cycleEndPos;         // Cycle End, in Quarter Note
    int32_t timeSigNumerator;   // Time Signature Numerator (e.g. 4 for 4/4)
    int32_t timeSigDenominator; // Time Signature Denominator (e.g. 4 for 4/4)
    int32_t smpteOffset;        // SMPTE offset
    int32_t smpteFrameRate;     // VstSmpteFrameRate
    int32_t samplesToNextClock; // MIDI Clock Resolution (24 Per Quarter Note)
    int32_t flags;              // VstTimeInfoFlags
} VstTimeInfo;

typedef struct VstEvent {
    int32_t type;
    int32_t byteSize;
    int32_t deltaFrames;
    int32_t flags;
    char data[16];
} VstEvent;

typedef struct VstMidiEvent {
    int32_t type;               // kVstMidiType = 1
    int32_t byteSize;           // sizeof(VstMidiEvent)
    int32_t deltaFrames;        // sample frames offset inside current block
    int32_t flags;              // kVstMidiEventIsRealtime = 1
    int32_t noteLength;
    int32_t noteOffset;
    char midiData[4];           // [status, data1, data2, 0]
    char detune;
    char noteOffVelocity;
    char reserved1;
    char reserved2;
} VstMidiEvent;

#define MAX_VST_MIDI_EVENTS 64

typedef struct VstEventsBlock {
    int32_t numEvents;
    intptr_t reserved;
    VstEvent* events[MAX_VST_MIDI_EVENTS];
} VstEventsBlock;

typedef struct VstSlotMidiQueue {
    AEffect* effect;
    VstMidiEvent ring[MAX_VST_MIDI_EVENTS];
    VstMidiEvent localEvents[MAX_VST_MIDI_EVENTS];
    VstEventsBlock block;
    volatile uint32_t writeIdx;
    volatile uint32_t readIdx;
    double clockPhaseSamples;
    double samplePos;
    double ppqPos;
} VstSlotMidiQueue;

#define MAX_TRACKED_VST_SLOTS 16
static VstSlotMidiQueue g_vstQueues[MAX_TRACKED_VST_SLOTS];

#define MAX_VST_CHANNELS 32
static float g_vstSilenceIn[8192] = {0};
static float g_vstDiscardOut[MAX_VST_CHANNELS][8192] = {{0}};

static VstTimeInfo g_hostTimeInfo = {
    .samplePos = 0.0,
    .sampleRate = 48000.0,
    .nanoSeconds = 0.0,
    .ppqPos = 0.0,
    .tempo = 124.0,
    .barStartPos = 0.0,
    .cycleStartPos = 0.0,
    .cycleEndPos = 4.0,
    .timeSigNumerator = 4,
    .timeSigDenominator = 4,
    .smpteOffset = 0,
    .smpteFrameRate = 0,
    .samplesToNextClock = 0,
    .flags = kVstTransportPlaying | kVstTempoValid | kVstPpqPosValid | kVstBarsValid | kVstTimeSigValid | kVstClockValid
};

static bool g_sendMidiClock = true;

static VstSlotMidiQueue* get_or_create_queue(AEffect* effect) {
    if (!effect) return NULL;
    for (int i = 0; i < MAX_TRACKED_VST_SLOTS; i++) {
        if (g_vstQueues[i].effect == effect) {
            return &g_vstQueues[i];
        }
    }
    for (int i = 0; i < MAX_TRACKED_VST_SLOTS; i++) {
        if (g_vstQueues[i].effect == NULL) {
            memset(&g_vstQueues[i], 0, sizeof(VstSlotMidiQueue));
            g_vstQueues[i].effect = effect;
            return &g_vstQueues[i];
        }
    }
    return &g_vstQueues[0];
}

static void release_queue(AEffect* effect) {
    if (!effect) return;
    for (int i = 0; i < MAX_TRACKED_VST_SLOTS; i++) {
        if (g_vstQueues[i].effect == effect) {
            g_vstQueues[i].effect = NULL;
            g_vstQueues[i].writeIdx = 0;
            g_vstQueues[i].readIdx = 0;
        }
    }
}

void rane_vst_set_tempo(double bpm, double sampleRate, bool isPlaying, bool sendMidiClock) {
    if (bpm >= 30.0 && bpm <= 300.0) {
        g_hostTimeInfo.tempo = bpm;
    }
    if (sampleRate >= 8000.0) {
        g_hostTimeInfo.sampleRate = sampleRate;
    }
    int32_t flags = kVstTempoValid | kVstPpqPosValid | kVstBarsValid | kVstTimeSigValid | kVstClockValid;
    if (isPlaying) {
        flags |= kVstTransportPlaying;
    }
    g_hostTimeInfo.flags = flags;
    g_sendMidiClock = sendMidiClock;
}

void rane_vst_send_midi(AEffect* effect, uint8_t status, uint8_t data1, uint8_t data2, int32_t deltaFrames) {
    VstSlotMidiQueue* q = get_or_create_queue(effect);
    if (!q) return;

    uint32_t w = q->writeIdx;
    uint32_t nextW = (w + 1) % MAX_VST_MIDI_EVENTS;
    if (nextW == q->readIdx) {
        return; // Ring buffer full
    }

    VstMidiEvent* ev = &q->ring[w];
    memset(ev, 0, sizeof(VstMidiEvent));
    ev->type = kVstMidiType;
    ev->byteSize = sizeof(VstMidiEvent);
    ev->deltaFrames = deltaFrames >= 0 ? deltaFrames : 0;
    ev->flags = kVstMidiEventIsRealtime;
    ev->midiData[0] = (char)status;
    ev->midiData[1] = (char)data1;
    ev->midiData[2] = (char)data2;
    ev->midiData[3] = 0;

    q->writeIdx = nextW;
}

static intptr_t rane_vst_host_callback(AEffect* effect, int32_t opcode, int32_t index, intptr_t value, void* ptr, float opt) {
    switch (opcode) {
        case audioMasterVersion:
            return 2400; // VST 2.4
        case audioMasterGetTime: {
            static mach_timebase_info_data_t tb = {0, 0};
            if (tb.denom == 0) mach_timebase_info(&tb);
            g_hostTimeInfo.nanoSeconds = (double)((mach_absolute_time() * tb.numer) / tb.denom);
            return (intptr_t)&g_hostTimeInfo;
        }
        case audioMasterGetSampleRate:
            return (intptr_t)g_hostTimeInfo.sampleRate;
        case audioMasterGetBlockSize:
            return 512;
        case audioMasterGetCurrentProcessLevel:
            return 2; // Realtime audio thread
        case audioMasterGetVendorString:
            if (ptr) strncpy((char*)ptr, "Rane", 64);
            return 1;
        case audioMasterGetProductString:
            if (ptr) strncpy((char*)ptr, "Rane Sixty-Eight Host", 64);
            return 1;
        case audioMasterGetVendorVersion:
            return 2000;
        case audioMasterCanDo:
            if (ptr) {
                const char* canDo = (const char*)ptr;
                if (strcmp(canDo, "sendVstEvents") == 0 ||
                    strcmp(canDo, "sendVstMidiEvent") == 0 ||
                    strcmp(canDo, "sendVstTimeInfo") == 0 ||
                    strcmp(canDo, "receiveVstEvents") == 0 ||
                    strcmp(canDo, "receiveVstMidiEvent") == 0 ||
                    strcmp(canDo, "supplyIdle") == 0 ||
                    strcmp(canDo, "sizeWindow") == 0 ||
                    strcmp(canDo, "openFileSelector") == 0) {
                    return 1;
                }
            }
            return 0;
        default:
            return 0;
    }
}

bool rane_vst_inspect(const char* bundlePath, char* outName, int nameLen, char* outVendor, int vendorLen, int* outInputs, int* outOutputs) {
    if (!bundlePath) return false;
    CFStringRef str = CFStringCreateWithCString(NULL, bundlePath, kCFStringEncodingUTF8);
    if (!str) return false;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, str, kCFURLPOSIXPathStyle, true);
    CFRelease(str);
    if (!url) return false;
    CFBundleRef bundle = CFBundleCreate(NULL, url);
    CFRelease(url);
    if (!bundle) return false;

    if (!CFBundleLoadExecutable(bundle)) {
        CFRelease(bundle);
        return false;
    }

    vstPluginFuncPtr mainFunc = (vstPluginFuncPtr)CFBundleGetFunctionPointerForName(bundle, CFSTR("VSTPluginMain"));
    if (!mainFunc) {
        mainFunc = (vstPluginFuncPtr)CFBundleGetFunctionPointerForName(bundle, CFSTR("main_macho"));
    }
    if (!mainFunc) {
        CFRelease(bundle);
        return false;
    }

    AEffect* effect = mainFunc(rane_vst_host_callback);
    if (!effect || effect->magic != 0x56737450) {
        CFRelease(bundle);
        return false;
    }

    if (outInputs) *outInputs = effect->numInputs;
    if (outOutputs) *outOutputs = effect->numOutputs;

    // Call effOpen
    effect->dispatcher(effect, effOpen, 0, 0, NULL, 0.0f);

    if (outName && nameLen > 0) {
        char buf[256] = {0};
        effect->dispatcher(effect, effGetEffectName, 0, 0, buf, 0.0f);
        if (buf[0] == '\0') {
            // Fallback: extract filename without .vst
            const char* slash = strrchr(bundlePath, '/');
            const char* base = slash ? slash + 1 : bundlePath;
            strncpy(buf, base, sizeof(buf) - 1);
            char* dot = strstr(buf, ".vst");
            if (dot) *dot = '\0';
        }
        strncpy(outName, buf, nameLen - 1);
        outName[nameLen - 1] = '\0';
    }

    if (outVendor && vendorLen > 0) {
        char vBuf[256] = {0};
        effect->dispatcher(effect, effGetVendorString, 0, 0, vBuf, 0.0f);
        if (vBuf[0] == '\0') {
            strncpy(vBuf, "VST Plugin", sizeof(vBuf) - 1);
        }
        strncpy(outVendor, vBuf, vendorLen - 1);
        outVendor[vendorLen - 1] = '\0';
    }

    // Call effClose
    effect->dispatcher(effect, effClose, 0, 0, NULL, 0.0f);
    CFRelease(bundle);
    return true;
}

AEffect* rane_vst_load(const char* bundlePath, void** outBundle, double sampleRate, int blockSize) {
    if (!bundlePath) return NULL;
    CFStringRef str = CFStringCreateWithCString(NULL, bundlePath, kCFStringEncodingUTF8);
    if (!str) return NULL;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, str, kCFURLPOSIXPathStyle, true);
    CFRelease(str);
    if (!url) return NULL;
    CFBundleRef bundle = CFBundleCreate(NULL, url);
    CFRelease(url);
    if (!bundle) return NULL;

    if (!CFBundleLoadExecutable(bundle)) {
        CFRelease(bundle);
        return NULL;
    }

    vstPluginFuncPtr mainFunc = (vstPluginFuncPtr)CFBundleGetFunctionPointerForName(bundle, CFSTR("VSTPluginMain"));
    if (!mainFunc) {
        mainFunc = (vstPluginFuncPtr)CFBundleGetFunctionPointerForName(bundle, CFSTR("main_macho"));
    }
    if (!mainFunc) {
        CFRelease(bundle);
        return NULL;
    }

    AEffect* effect = mainFunc(rane_vst_host_callback);
    if (!effect || effect->magic != 0x56737450) {
        CFRelease(bundle);
        return NULL;
    }

    // Initialize MIDI queue for this instance
    get_or_create_queue(effect);

    // 1. effOpen
    effect->dispatcher(effect, effOpen, 0, 0, NULL, 0.0f);

    // 2. Set sample rate & block size
    effect->dispatcher(effect, effSetSampleRate, 0, 0, NULL, (float)(sampleRate > 0 ? sampleRate : 48000.0));
    effect->dispatcher(effect, effSetBlockSize, 0, (blockSize > 0 ? blockSize : 512), NULL, 0.0f);

    // 3. effMainsChanged (power on)
    effect->dispatcher(effect, effMainsChanged, 0, 1, NULL, 0.0f);

    if (outBundle) *outBundle = bundle;
    return effect;
}

void rane_vst_process(AEffect* effect, const float* inL, const float* inR, float* outL, float* outR, int32_t frames) {
    if (!effect || frames <= 0) return;

    VstSlotMidiQueue* q = get_or_create_queue(effect);
    if (q) {
        double sr = g_hostTimeInfo.sampleRate > 8000.0 ? g_hostTimeInfo.sampleRate : 48000.0;
        double bpm = g_hostTimeInfo.tempo > 30.0 ? g_hostTimeInfo.tempo : 124.0;
        double samplesPerBeat = (60.0 / bpm) * sr;
        double samplesPerClock = samplesPerBeat / 24.0; // 24 PPQN MIDI Timing Clock (0xF8)

        // Update Host VstTimeInfo from this slot's timeline
        g_hostTimeInfo.samplePos = q->samplePos;
        g_hostTimeInfo.ppqPos = q->ppqPos;
        g_hostTimeInfo.barStartPos = ((int32_t)(q->ppqPos / 4.0)) * 4.0;
        g_hostTimeInfo.samplesToNextClock = (int32_t)(samplesPerClock - q->clockPhaseSamples);

        q->samplePos += (double)frames;
        q->ppqPos += ((double)frames) / samplesPerBeat;

        // Flush queued MIDI events (Note On/Off, CC) to plugin via effProcessEvents
        if (q->readIdx != q->writeIdx) {
            memset(&q->block, 0, sizeof(q->block));
            int32_t count = 0;
            while (q->readIdx != q->writeIdx && count < MAX_VST_MIDI_EVENTS) {
                q->localEvents[count] = q->ring[q->readIdx];
                q->block.events[count] = (VstEvent*)&q->localEvents[count];
                q->readIdx = (q->readIdx + 1) % MAX_VST_MIDI_EVENTS;
                count++;
            }
            if (count > 0) {
                q->block.numEvents = count;
                effect->dispatcher(effect, effProcessEvents, 0, 0, &q->block, 0.0f);
            }
        }
    }

    int numIn = effect->numInputs > 0 ? effect->numInputs : 2;
    int numOut = effect->numOutputs > 0 ? effect->numOutputs : 2;
    if (numIn > MAX_VST_CHANNELS) numIn = MAX_VST_CHANNELS;
    if (numOut > MAX_VST_CHANNELS) numOut = MAX_VST_CHANNELS;

    float* inBuffers[MAX_VST_CHANNELS];
    float* outBuffers[MAX_VST_CHANNELS];

    inBuffers[0] = (float*)inL;
    inBuffers[1] = (float*)inR;
    for (int i = 2; i < numIn; i++) {
        inBuffers[i] = g_vstSilenceIn;
    }

    outBuffers[0] = outL;
    outBuffers[1] = outR;
    for (int i = 2; i < numOut; i++) {
        outBuffers[i] = g_vstDiscardOut[i];
    }

    if (effect->processReplacing) {
        effect->processReplacing(effect, inBuffers, outBuffers, frames);
    } else if (effect->process) {
        effect->process(effect, inBuffers, outBuffers, frames);
    }

    // Protect mixer bus & DAC from any NaN or Inf outputs produced by plugin algorithms
    for (int32_t f = 0; f < frames; f++) {
        if (isnan(outL[f]) || isinf(outL[f])) outL[f] = 0.0f;
        if (isnan(outR[f]) || isinf(outR[f])) outR[f] = 0.0f;
    }
}

bool rane_vst_get_editor_rect(AEffect* effect, int* outW, int* outH) {
    if (!effect) return false;
    ERect* rect = NULL;
    effect->dispatcher(effect, effEditGetRect, 0, 0, &rect, 0.0f);
    if (rect) {
        int w = rect->right - rect->left;
        int h = rect->bottom - rect->top;
        if (w > 0 && h > 0) {
            if (outW) *outW = w;
            if (outH) *outH = h;
            return true;
        }
    }
    return false;
}

void rane_vst_open_editor(AEffect* effect, void* nsViewPtr) {
    if (!effect || !nsViewPtr) return;
    effect->dispatcher(effect, effEditOpen, 0, 0, nsViewPtr, 0.0f);
}

void rane_vst_close_editor(AEffect* effect) {
    if (!effect) return;
    effect->dispatcher(effect, effEditClose, 0, 0, NULL, 0.0f);
}

void rane_vst_edit_idle(AEffect* effect) {
    if (!effect) return;
    effect->dispatcher(effect, effEditIdle, 0, 0, NULL, 0.0f);
}

void rane_vst_close(AEffect* effect, void* bundle) {
    if (!effect) return;
    release_queue(effect);
    effect->dispatcher(effect, effMainsChanged, 0, 0, NULL, 0.0f);
    effect->dispatcher(effect, effClose, 0, 0, NULL, 0.0f);
    if (bundle) {
        CFBundleRef cfBundle = (CFBundleRef)bundle;
        CFBundleUnloadExecutable(cfBundle);
        CFRelease(cfBundle);
    }
}

// ============================================================================
// VST 3 C ABI HOST ENGINE (IComponent, IAudioProcessor, IEditController, IPlugView)
// ============================================================================

#define VST3_UID(l1, l2, l3, l4) { \
    (uint8_t)(((uint32_t)(l1) >> 24) & 0xFF), (uint8_t)(((uint32_t)(l1) >> 16) & 0xFF), (uint8_t)(((uint32_t)(l1) >> 8) & 0xFF), (uint8_t)((uint32_t)(l1) & 0xFF), \
    (uint8_t)(((uint32_t)(l2) >> 24) & 0xFF), (uint8_t)(((uint32_t)(l2) >> 16) & 0xFF), (uint8_t)(((uint32_t)(l2) >> 8) & 0xFF), (uint8_t)((uint32_t)(l2) & 0xFF), \
    (uint8_t)(((uint32_t)(l3) >> 24) & 0xFF), (uint8_t)(((uint32_t)(l3) >> 16) & 0xFF), (uint8_t)(((uint32_t)(l3) >> 8) & 0xFF), (uint8_t)((uint32_t)(l3) & 0xFF), \
    (uint8_t)(((uint32_t)(l4) >> 24) & 0xFF), (uint8_t)(((uint32_t)(l4) >> 16) & 0xFF), (uint8_t)(((uint32_t)(l4) >> 8) & 0xFF), (uint8_t)((uint32_t)(l4) & 0xFF)  \
}

static const uint8_t VST3_IID_FUnknown[16]            = VST3_UID(0x00000000, 0x00000000, 0xC0000000, 0x00000046);
static const uint8_t VST3_IID_IBStream[16]            = VST3_UID(0xC3BF6EA2, 0x30994752, 0x9B6BF990, 0x1EE33E9B);
static const uint8_t VST3_IID_IHostApplication[16]    = VST3_UID(0x58E595CC, 0xDB2D4969, 0x8B6AAF8C, 0x36A664E5);
static const uint8_t VST3_IID_IComponent[16]          = VST3_UID(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802);
static const uint8_t VST3_IID_IAudioProcessor[16]     = VST3_UID(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D);
static const uint8_t VST3_IID_IEditController[16]     = VST3_UID(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E);
static const uint8_t VST3_IID_IComponentHandler[16]   = VST3_UID(0x93A0BEA3, 0x0BD045DB, 0x8E890B0C, 0xC1E46AC6);
static const uint8_t VST3_IID_IConnectionPoint[16]    = VST3_UID(0x70A4156F, 0x6E6E4026, 0x989148BF, 0xAA60D8D1);
static const uint8_t VST3_IID_IMidiMapping[16]        = VST3_UID(0xDF0FF9F7, 0x49B74669, 0xB63AB732, 0x7ADBF5E5);
static const uint8_t VST3_IID_IPlugView[16]           = VST3_UID(0x5BC32507, 0xD06049EA, 0xA6151B52, 0x2B755B29);
static const uint8_t VST3_IID_IPlugFrame[16]          = VST3_UID(0x367FAF01, 0xAFA94693, 0x8D4DA2A0, 0xED0882A3);
static const uint8_t VST3_IID_IParamValueQueue[16]    = VST3_UID(0x01263A18, 0xED074F6F, 0x98C9D356, 0x4686F9BA);
static const uint8_t VST3_IID_IParameterChanges[16]   = VST3_UID(0xA4779663, 0x0BB64A56, 0xB44384A8, 0x466FEB9D);
static const uint8_t VST3_IID_IEventList[16]          = VST3_UID(0x3A2C4214, 0x346349FE, 0xB2C4F397, 0xB9695A44);

#pragma pack(push, 16)
typedef struct Vst3PFactoryInfo {
    char vendor[64];
    char url[256];
    char email[128];
    int32_t flags;
} Vst3PFactoryInfo;

typedef struct Vst3PClassInfo {
    uint8_t cid[16];
    int32_t cardinality;
    char category[32];
    char name[64];
} Vst3PClassInfo;
#pragma pack(pop)

typedef struct Vst3PluginFactoryVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*getFactoryInfo)(void* thisPtr, Vst3PFactoryInfo* info);
    int32_t (*countClasses)(void* thisPtr);
    int32_t (*getClassInfo)(void* thisPtr, int32_t index, Vst3PClassInfo* info);
    int32_t (*createInstance)(void* thisPtr, const uint8_t* cid, const uint8_t* iid, void** obj);
} Vst3PluginFactoryVtbl;
typedef struct Vst3PluginFactory { Vst3PluginFactoryVtbl* lpVtbl; } Vst3PluginFactory;

typedef struct Vst3ComponentVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*initialize)(void* thisPtr, void* context);
    int32_t (*terminate)(void* thisPtr);
    int32_t (*getControllerClassId)(void* thisPtr, uint8_t classId[16]);
    int32_t (*setIoMode)(void* thisPtr, int32_t mode);
    int32_t (*getBusCount)(void* thisPtr, int32_t type, int32_t dir);
    int32_t (*getBusInfo)(void* thisPtr, int32_t type, int32_t dir, int32_t index, void* bus);
    int32_t (*getRoutingInfo)(void* thisPtr, void* inInfo, void* outInfo);
    int32_t (*activateBus)(void* thisPtr, int32_t type, int32_t dir, int32_t index, uint8_t state);
    int32_t (*setActive)(void* thisPtr, uint8_t state);
    int32_t (*setState)(void* thisPtr, void* state);
    int32_t (*getState)(void* thisPtr, void* state);
} Vst3ComponentVtbl;
typedef struct Vst3Component { Vst3ComponentVtbl* lpVtbl; } Vst3Component;

typedef struct Vst3ProcessSetup {
    int32_t processMode;        // 0 = kRealtime
    int32_t symbolicSampleSize; // 0 = kSample32
    int32_t maxSamplesPerBlock;
    double sampleRate;
} Vst3ProcessSetup;

typedef struct Vst3AudioBusBuffers {
    int32_t numChannels;
    uint64_t silenceFlags;
    union {
        float** channelBuffers32;
        double** channelBuffers64;
    };
} Vst3AudioBusBuffers;

typedef struct Vst3ProcessContext {
    uint32_t state;
    double sampleRate;
    int64_t projectTimeSamples;
    int64_t systemTime;
    int64_t continousTimeSamples;
    double projectTimeMusic;
    double barPositionMusic;
    double cycleStartMusic;
    double cycleEndMusic;
    double tempo;
    int32_t timeSigNumerator;
    int32_t timeSigDenominator;
    int32_t chord;
    int32_t smpteOffsetSubframes;
    int32_t frameRate;
    int32_t samplesToNextClock;
} Vst3ProcessContext;

typedef struct Vst3ProcessData {
    int32_t processMode;
    int32_t symbolicSampleSize;
    int32_t numSamples;
    int32_t numInputs;
    int32_t numOutputs;
    Vst3AudioBusBuffers* inputs;
    Vst3AudioBusBuffers* outputs;
    void* inputParameterChanges;
    void* outputParameterChanges;
    void* inputEvents;
    void* outputEvents;
    Vst3ProcessContext* processContext;
} Vst3ProcessData;

typedef struct Vst3AudioProcessorVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*setBusArrangements)(void* thisPtr, uint64_t* inputs, int32_t numIns, uint64_t* outputs, int32_t numOuts);
    int32_t (*getBusArrangement)(void* thisPtr, int32_t dir, int32_t index, uint64_t* arr);
    int32_t (*canProcessSampleSize)(void* thisPtr, int32_t symbolicSampleSize);
    uint32_t (*getLatencySamples)(void* thisPtr);
    int32_t (*setupProcessing)(void* thisPtr, Vst3ProcessSetup* setup);
    int32_t (*setProcessing)(void* thisPtr, uint8_t state);
    int32_t (*process)(void* thisPtr, Vst3ProcessData* data);
    uint32_t (*getTailSamples)(void* thisPtr);
} Vst3AudioProcessorVtbl;
typedef struct Vst3AudioProcessor { Vst3AudioProcessorVtbl* lpVtbl; } Vst3AudioProcessor;

typedef struct Vst3EditControllerVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*initialize)(void* thisPtr, void* context);
    int32_t (*terminate)(void* thisPtr);
    int32_t (*setComponentState)(void* thisPtr, void* state);
    int32_t (*setState)(void* thisPtr, void* state);
    int32_t (*getState)(void* thisPtr, void* state);
    int32_t (*getParameterCount)(void* thisPtr);
    int32_t (*getParameterInfo)(void* thisPtr, int32_t paramIndex, void* info);
    int32_t (*getParamStringByValue)(void* thisPtr, uint32_t id, double valueNormalized, void* string);
    int32_t (*getParamValueByString)(void* thisPtr, uint32_t id, void* string, double* valueNormalized);
    double (*normalizedParamToPlain)(void* thisPtr, uint32_t id, double valueNormalized);
    double (*plainParamToNormalized)(void* thisPtr, uint32_t id, double plainValue);
    double (*getParamNormalized)(void* thisPtr, uint32_t id);
    int32_t (*setParamNormalized)(void* thisPtr, uint32_t id, double value);
    int32_t (*setComponentHandler)(void* thisPtr, void* handler);
    void* (*createView)(void* thisPtr, const char* name);
} Vst3EditControllerVtbl;
typedef struct Vst3EditController { Vst3EditControllerVtbl* lpVtbl; } Vst3EditController;

typedef struct Vst3ConnectionPointVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*connect)(void* thisPtr, void* other);
    int32_t (*disconnect)(void* thisPtr, void* other);
    int32_t (*notify)(void* thisPtr, void* message);
} Vst3ConnectionPointVtbl;
typedef struct Vst3ConnectionPoint { Vst3ConnectionPointVtbl* lpVtbl; } Vst3ConnectionPoint;

typedef struct Vst3MidiMappingVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*getMidiControllerAssignment)(void* thisPtr, int32_t busIndex, int16_t channel, int16_t midiControllerNumber, uint32_t* id);
} Vst3MidiMappingVtbl;
typedef struct Vst3MidiMapping { Vst3MidiMappingVtbl* lpVtbl; } Vst3MidiMapping;

typedef struct Vst3ViewRect {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
} Vst3ViewRect;

typedef struct Vst3PlugViewVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*isPlatformTypeSupported)(void* thisPtr, const char* type);
    int32_t (*attached)(void* thisPtr, void* parent, const char* type);
    int32_t (*removed)(void* thisPtr);
    int32_t (*onWheel)(void* thisPtr, float distance);
    int32_t (*onKeyDown)(void* thisPtr, uint16_t key, int16_t keyCode, int16_t modifiers);
    int32_t (*onKeyUp)(void* thisPtr, uint16_t key, int16_t keyCode, int16_t modifiers);
    int32_t (*getSize)(void* thisPtr, Vst3ViewRect* size);
    int32_t (*onSize)(void* thisPtr, Vst3ViewRect* newSize);
    int32_t (*onFocus)(void* thisPtr, uint8_t state);
    int32_t (*setFrame)(void* thisPtr, void* frame);
    int32_t (*canResize)(void* thisPtr);
    int32_t (*checkSizeConstraint)(void* thisPtr, Vst3ViewRect* rect);
} Vst3PlugViewVtbl;
typedef struct Vst3PlugView { Vst3PlugViewVtbl* lpVtbl; } Vst3PlugView;

// 1. HostApplication implementation
typedef struct Vst3HostAppVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*getName)(void* thisPtr, uint16_t name[128]);
    int32_t (*createInstance)(void* thisPtr, uint8_t* cid, uint8_t* iid, void** obj);
} Vst3HostAppVtbl;
typedef struct Vst3HostApp { Vst3HostAppVtbl* lpVtbl; } Vst3HostApp;

static int32_t vst3_host_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IHostApplication, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static uint32_t vst3_host_ref(void* thisPtr) { (void)thisPtr; return 1; }
static int32_t vst3_host_getName(void* thisPtr, uint16_t name[128]) {
    (void)thisPtr;
    const char* s = "Rane Sixty-Eight FlexFX Host";
    int i = 0;
    for (; s[i] && i < 127; i++) name[i] = (uint16_t)s[i];
    name[i] = 0;
    return 0;
}
static int32_t vst3_host_createInstance(void* thisPtr, uint8_t* cid, uint8_t* iid, void** obj) {
    (void)thisPtr; (void)cid; (void)iid;
    *obj = NULL;
    return -1;
}
static Vst3HostAppVtbl g_vst3HostVtbl = { vst3_host_qi, vst3_host_ref, vst3_host_ref, vst3_host_getName, vst3_host_createInstance };
static Vst3HostApp g_vst3HostApp = { &g_vst3HostVtbl };

// 2. In-Memory IBStream for syncing state from IComponent -> IEditController
typedef struct Vst3MemStreamVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*read)(void* thisPtr, void* buffer, int32_t numBytes, int32_t* numBytesRead);
    int32_t (*write)(void* thisPtr, void* buffer, int32_t numBytes, int32_t* numBytesWritten);
    int32_t (*seek)(void* thisPtr, int64_t pos, int32_t mode, int64_t* result);
    int32_t (*tell)(void* thisPtr, int64_t* pos);
} Vst3MemStreamVtbl;

typedef struct Vst3MemStream {
    Vst3MemStreamVtbl* lpVtbl;
    uint8_t* data;
    int64_t size;
    int64_t capacity;
    int64_t cursor;
} Vst3MemStream;

static int32_t vst3_stream_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IBStream, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static uint32_t vst3_stream_ref(void* thisPtr) { (void)thisPtr; return 1; }
static int32_t vst3_stream_read(void* thisPtr, void* buffer, int32_t numBytes, int32_t* numBytesRead) {
    Vst3MemStream* s = (Vst3MemStream*)thisPtr;
    if (!buffer || numBytes < 0) return -1;
    int64_t avail = s->size - s->cursor;
    int32_t toRead = (numBytes < avail) ? numBytes : (int32_t)(avail > 0 ? avail : 0);
    if (toRead > 0) {
        memcpy(buffer, s->data + s->cursor, toRead);
        s->cursor += toRead;
    }
    if (numBytesRead) *numBytesRead = toRead;
    return 0;
}
static int32_t vst3_stream_write(void* thisPtr, void* buffer, int32_t numBytes, int32_t* numBytesWritten) {
    Vst3MemStream* s = (Vst3MemStream*)thisPtr;
    if (!buffer || numBytes < 0) return -1;
    if (s->cursor + numBytes > s->capacity) {
        int64_t newCap = (s->capacity == 0) ? 4096 : s->capacity * 2;
        while (newCap < s->cursor + numBytes) newCap *= 2;
        uint8_t* newBuf = (uint8_t*)realloc(s->data, (size_t)newCap);
        if (!newBuf) return -1;
        s->data = newBuf;
        s->capacity = newCap;
    }
    memcpy(s->data + s->cursor, buffer, numBytes);
    s->cursor += numBytes;
    if (s->cursor > s->size) s->size = s->cursor;
    if (numBytesWritten) *numBytesWritten = numBytes;
    return 0;
}
static int32_t vst3_stream_seek(void* thisPtr, int64_t pos, int32_t mode, int64_t* result) {
    Vst3MemStream* s = (Vst3MemStream*)thisPtr;
    int64_t target = pos;
    if (mode == 1) target = s->cursor + pos;      // kIBSeekCur
    else if (mode == 2) target = s->size + pos;   // kIBSeekEnd
    if (target < 0) target = 0;
    if (target > s->size) target = s->size;
    s->cursor = target;
    if (result) *result = s->cursor;
    return 0;
}
static int32_t vst3_stream_tell(void* thisPtr, int64_t* pos) {
    Vst3MemStream* s = (Vst3MemStream*)thisPtr;
    if (pos) *pos = s->cursor;
    return 0;
}
static Vst3MemStreamVtbl g_vst3StreamVtbl = {
    vst3_stream_qi, vst3_stream_ref, vst3_stream_ref,
    vst3_stream_read, vst3_stream_write, vst3_stream_seek, vst3_stream_tell
};

// 3. IPlugFrame implementation
typedef struct Vst3PlugFrameVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*resizeView)(void* thisPtr, Vst3PlugView* view, Vst3ViewRect* newSize);
} Vst3PlugFrameVtbl;

typedef struct Vst3PlugFrame {
    Vst3PlugFrameVtbl* lpVtbl;
    struct RaneVst3Instance* inst;
} Vst3PlugFrame;

static int32_t vst3_frame_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IPlugFrame, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static int32_t vst3_frame_resizeView(void* thisPtr, Vst3PlugView* view, Vst3ViewRect* newSize);
static Vst3PlugFrameVtbl g_vst3FrameVtbl = { vst3_frame_qi, vst3_host_ref, vst3_host_ref, vst3_frame_resizeView };

// 4. Parameter Changes & Events queues for real-time audio processing
#define MAX_VST3_PARAM_CHANGES 128
#define MAX_VST3_EVENTS 128

typedef struct Vst3ParamChangeItem {
    uint32_t paramId;
    double value;
    int32_t sampleOffset;
} Vst3ParamChangeItem;

typedef struct Vst3SingleParamQueueVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    uint32_t (*getParameterId)(void* thisPtr);
    int32_t (*getPointCount)(void* thisPtr);
    int32_t (*getPoint)(void* thisPtr, int32_t index, int32_t* sampleOffset, double* value);
    int32_t (*addPoint)(void* thisPtr, int32_t sampleOffset, double value, int32_t* index);
} Vst3SingleParamQueueVtbl;

typedef struct Vst3SingleParamQueue {
    Vst3SingleParamQueueVtbl* lpVtbl;
    uint32_t paramId;
    int32_t sampleOffset;
    double value;
} Vst3SingleParamQueue;

static int32_t vst3_pq_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IParamValueQueue, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static uint32_t vst3_pq_getParamId(void* thisPtr) { return ((Vst3SingleParamQueue*)thisPtr)->paramId; }
static int32_t vst3_pq_getPointCount(void* thisPtr) { (void)thisPtr; return 1; }
static int32_t vst3_pq_getPoint(void* thisPtr, int32_t index, int32_t* sampleOffset, double* value) {
    if (index != 0) return -1;
    Vst3SingleParamQueue* q = (Vst3SingleParamQueue*)thisPtr;
    if (sampleOffset) *sampleOffset = q->sampleOffset;
    if (value) *value = q->value;
    return 0;
}
static int32_t vst3_pq_addPoint(void* thisPtr, int32_t sampleOffset, double value, int32_t* index) {
    Vst3SingleParamQueue* q = (Vst3SingleParamQueue*)thisPtr;
    q->sampleOffset = sampleOffset;
    q->value = value;
    if (index) *index = 0;
    return 0;
}
static Vst3SingleParamQueueVtbl g_vst3SingleParamQueueVtbl = {
    vst3_pq_qi, vst3_host_ref, vst3_host_ref,
    vst3_pq_getParamId, vst3_pq_getPointCount, vst3_pq_getPoint, vst3_pq_addPoint
};

typedef struct Vst3ParamChangesBlockVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*getParameterCount)(void* thisPtr);
    void* (*getParameterData)(void* thisPtr, int32_t index);
    void* (*addParameterData)(void* thisPtr, const uint32_t* id, int32_t* index);
} Vst3ParamChangesBlockVtbl;

typedef struct Vst3ParamChangesBlock {
    Vst3ParamChangesBlockVtbl* lpVtbl;
    int32_t count;
    Vst3SingleParamQueue queues[MAX_VST3_PARAM_CHANGES];
} Vst3ParamChangesBlock;

static int32_t vst3_pc_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IParameterChanges, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static int32_t vst3_pc_getCount(void* thisPtr) { return ((Vst3ParamChangesBlock*)thisPtr)->count; }
static void* vst3_pc_getData(void* thisPtr, int32_t index) {
    Vst3ParamChangesBlock* b = (Vst3ParamChangesBlock*)thisPtr;
    if (index < 0 || index >= b->count) return NULL;
    return &b->queues[index];
}
static void* vst3_pc_addData(void* thisPtr, const uint32_t* id, int32_t* index) {
    Vst3ParamChangesBlock* b = (Vst3ParamChangesBlock*)thisPtr;
    if (!id || b->count >= MAX_VST3_PARAM_CHANGES) return NULL;
    int32_t idx = b->count++;
    b->queues[idx].lpVtbl = &g_vst3SingleParamQueueVtbl;
    b->queues[idx].paramId = *id;
    b->queues[idx].sampleOffset = 0;
    b->queues[idx].value = 0.0;
    if (index) *index = idx;
    return &b->queues[idx];
}
static Vst3ParamChangesBlockVtbl g_vst3ParamChangesVtbl = {
    vst3_pc_qi, vst3_host_ref, vst3_host_ref,
    vst3_pc_getCount, vst3_pc_getData, vst3_pc_addData
};

// VST3 Event List (Note On/Off & Legacy MIDI CC)
typedef struct Vst3Event {
    int32_t busIndex;
    int32_t sampleOffset;
    double ppqPosition;
    uint16_t flags;
    uint16_t type; // 0 = kNoteOnEvent, 1 = kNoteOffEvent, 65535 = kLegacyMIDICCOutEvent
    union {
        struct {
            int16_t channel;
            int16_t pitch;
            float tuning;
            float velocity;
            int32_t length;
            int32_t noteId;
        } noteOn;
        struct {
            int16_t channel;
            int16_t pitch;
            float velocity;
            int32_t noteId;
            float tuning;
        } noteOff;
        struct {
            uint8_t controlNumber;
            int8_t channel;
            int8_t value;
            int8_t value2;
        } midiCCOut;
    };
} Vst3Event;

typedef struct Vst3EventListVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*getEventCount)(void* thisPtr);
    int32_t (*getEvent)(void* thisPtr, int32_t index, Vst3Event* e);
    int32_t (*addEvent)(void* thisPtr, Vst3Event* e);
} Vst3EventListVtbl;

typedef struct Vst3EventList {
    Vst3EventListVtbl* lpVtbl;
    int32_t count;
    Vst3Event events[MAX_VST3_EVENTS];
} Vst3EventList;

static int32_t vst3_el_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IEventList, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static int32_t vst3_el_getCount(void* thisPtr) { return ((Vst3EventList*)thisPtr)->count; }
static int32_t vst3_el_getEvent(void* thisPtr, int32_t index, Vst3Event* e) {
    Vst3EventList* l = (Vst3EventList*)thisPtr;
    if (!e || index < 0 || index >= l->count) return -1;
    *e = l->events[index];
    return 0;
}
static int32_t vst3_el_addEvent(void* thisPtr, Vst3Event* e) {
    Vst3EventList* l = (Vst3EventList*)thisPtr;
    if (!e || l->count >= MAX_VST3_EVENTS) return -1;
    l->events[l->count++] = *e;
    return 0;
}
static Vst3EventListVtbl g_vst3EventListVtbl = {
    vst3_el_qi, vst3_host_ref, vst3_host_ref,
    vst3_el_getCount, vst3_el_getEvent, vst3_el_addEvent
};

// ComponentHandler embedded in RaneVst3Instance
typedef struct Vst3ComponentHandlerVtbl {
    int32_t (*queryInterface)(void* thisPtr, const uint8_t* iid, void** obj);
    uint32_t (*addRef)(void* thisPtr);
    uint32_t (*release)(void* thisPtr);
    int32_t (*beginEdit)(void* thisPtr, uint32_t id);
    int32_t (*performEdit)(void* thisPtr, uint32_t id, double valueNormalized);
    int32_t (*endEdit)(void* thisPtr, uint32_t id);
    int32_t (*restartComponent)(void* thisPtr, int32_t flags);
} Vst3ComponentHandlerVtbl;

struct RaneVst3Instance {
    Vst3ComponentHandlerVtbl* handlerVtbl; // First field so RaneVst3Instance* IS IComponentHandler*
    CFBundleRef bundle;
    Vst3PluginFactory* factory;
    Vst3Component* component;
    Vst3AudioProcessor* processor;
    Vst3EditController* controller;
    bool controllerIsSeparate;
    Vst3ConnectionPoint* cpComp;
    Vst3ConnectionPoint* cpCtrl;
    Vst3MidiMapping* midiMapping;
    Vst3PlugView* activeView;
    Vst3PlugFrame plugFrame;
    RaneVstResizeCallback resizeCallback;
    void* resizeContext;

    // Lock-free parameter change ring buffer (GUI performEdit & MIDI CC -> DSP process)
    Vst3ParamChangeItem paramRing[MAX_VST3_PARAM_CHANGES];
    volatile uint32_t paramWriteIdx;
    volatile uint32_t paramReadIdx;

    // Lock-free MIDI event ring buffer
    Vst3Event eventRing[MAX_VST3_EVENTS];
    volatile uint32_t eventWriteIdx;
    volatile uint32_t eventReadIdx;

    double samplePos;
    double ppqPos;
    double clockPhaseSamples;
};

static int32_t vst3_frame_resizeView(void* thisPtr, Vst3PlugView* view, Vst3ViewRect* newSize) {
    if (!view || !newSize) return -1;
    Vst3PlugFrame* frame = (Vst3PlugFrame*)thisPtr;
    struct RaneVst3Instance* inst = frame ? frame->inst : NULL;
    if (inst && inst->resizeCallback) {
        int32_t w = newSize->right - newSize->left;
        int32_t h = newSize->bottom - newSize->top;
        inst->resizeCallback(inst->resizeContext, w, h);
    }
    view->lpVtbl->onSize(view, newSize);
    return 0;
}

static void vst3_push_param_change(RaneVst3Instance* inst, uint32_t paramId, double value, int32_t sampleOffset) {
    if (!inst) return;
    uint32_t w = inst->paramWriteIdx;
    uint32_t nextW = (w + 1) % MAX_VST3_PARAM_CHANGES;
    if (nextW == inst->paramReadIdx) return;
    inst->paramRing[w].paramId = paramId;
    inst->paramRing[w].value = value;
    inst->paramRing[w].sampleOffset = sampleOffset;
    inst->paramWriteIdx = nextW;
}

#pragma pack(push, 8)
typedef struct Vst3ParameterInfo {
    uint32_t id;
    uint16_t title[128];
    uint16_t shortTitle[128];
    uint16_t units[128];
    int32_t stepCount;
    double defaultNormalizedValue;
    int32_t unitId;
    int32_t flags;
} Vst3ParameterInfo;
#pragma pack(pop)

void rane_vst3_sync_all_params_to_processor(RaneVst3Instance* inst) {
    if (!inst || !inst->controller) return;
    int32_t count = inst->controller->lpVtbl->getParameterCount(inst->controller);
    for (int32_t i = 0; i < count; i++) {
        Vst3ParameterInfo info;
        memset(&info, 0, sizeof(info));
        if (inst->controller->lpVtbl->getParameterInfo(inst->controller, i, &info) == 0) {
            double val = inst->controller->lpVtbl->getParamNormalized(inst->controller, info.id);
            vst3_push_param_change(inst, info.id, val, 0);
        }
    }
}

static int32_t vst3_ch_qi(void* thisPtr, const uint8_t* iid, void** obj) {
    if (memcmp(iid, VST3_IID_FUnknown, 16) == 0 || memcmp(iid, VST3_IID_IComponentHandler, 16) == 0) {
        *obj = thisPtr;
        return 0;
    }
    *obj = NULL;
    return -1;
}
static int32_t vst3_ch_beginEdit(void* thisPtr, uint32_t id) { (void)thisPtr; (void)id; return 0; }
static int32_t vst3_ch_performEdit(void* thisPtr, uint32_t id, double valueNormalized) {
    RaneVst3Instance* inst = (RaneVst3Instance*)thisPtr;
    vst3_push_param_change(inst, id, valueNormalized, 0);
    if (inst->controllerIsSeparate && inst->controller) {
        inst->controller->lpVtbl->setParamNormalized(inst->controller, id, valueNormalized);
    }
    return 0;
}
static int32_t vst3_ch_endEdit(void* thisPtr, uint32_t id) { (void)thisPtr; (void)id; return 0; }
static int32_t vst3_ch_restartComponent(void* thisPtr, int32_t flags) {
    RaneVst3Instance* inst = (RaneVst3Instance*)thisPtr;
    if (!inst) return 0;
    if ((flags & ((1 << 0) | (1 << 2))) || flags == 0) {
        rane_vst3_sync_all_params_to_processor(inst);
    }
    return 0;
}

static Vst3ComponentHandlerVtbl g_vst3ComponentHandlerVtbl = {
    vst3_ch_qi, vst3_host_ref, vst3_host_ref,
    vst3_ch_beginEdit, vst3_ch_performEdit, vst3_ch_endEdit, vst3_ch_restartComponent
};

RaneVst3Instance* rane_vst3_load(const char* bundlePath, double sampleRate, int blockSize) {
    if (!bundlePath) return NULL;
    CFStringRef str = CFStringCreateWithCString(NULL, bundlePath, kCFStringEncodingUTF8);
    if (!str) return NULL;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, str, kCFURLPOSIXPathStyle, true);
    CFRelease(str);
    if (!url) return NULL;
    CFBundleRef bundle = CFBundleCreate(NULL, url);
    CFRelease(url);
    if (!bundle) return NULL;

    if (!CFBundleLoadExecutable(bundle)) {
        CFRelease(bundle);
        return NULL;
    }

    typedef bool (*BundleEntryFunc)(CFBundleRef);
    typedef Vst3PluginFactory* (*GetFactoryFunc)(void);

    BundleEntryFunc bundleEntry = (BundleEntryFunc)CFBundleGetFunctionPointerForName(bundle, CFSTR("bundleEntry"));
    if (bundleEntry) {
        bundleEntry(bundle);
    }

    GetFactoryFunc getFactory = (GetFactoryFunc)CFBundleGetFunctionPointerForName(bundle, CFSTR("GetPluginFactory"));
    if (!getFactory) {
        CFRelease(bundle);
        return NULL;
    }

    Vst3PluginFactory* factory = getFactory();
    if (!factory) {
        CFRelease(bundle);
        return NULL;
    }

    Vst3Component* comp = NULL;
    int32_t classCount = factory->lpVtbl->countClasses(factory);
    for (int32_t i = 0; i < classCount; i++) {
        Vst3PClassInfo cinfo;
        memset(&cinfo, 0, sizeof(cinfo));
        if (factory->lpVtbl->getClassInfo(factory, i, &cinfo) == 0) {
            if (strcmp(cinfo.category, "Audio Module Class") == 0) {
                if (factory->lpVtbl->createInstance(factory, cinfo.cid, VST3_IID_IComponent, (void**)&comp) == 0 && comp) {
                    break;
                }
            }
        }
    }

    if (!comp) {
        CFRelease(bundle);
        return NULL;
    }

    if (comp->lpVtbl->initialize(comp, &g_vst3HostApp) != 0) {
        comp->lpVtbl->release(comp);
        CFRelease(bundle);
        return NULL;
    }

    Vst3AudioProcessor* proc = NULL;
    if (comp->lpVtbl->queryInterface(comp, VST3_IID_IAudioProcessor, (void**)&proc) != 0 || !proc) {
        comp->lpVtbl->terminate(comp);
        comp->lpVtbl->release(comp);
        CFRelease(bundle);
        return NULL;
    }

    RaneVst3Instance* inst = (RaneVst3Instance*)calloc(1, sizeof(RaneVst3Instance));
    inst->handlerVtbl = &g_vst3ComponentHandlerVtbl;
    inst->plugFrame.lpVtbl = &g_vst3FrameVtbl;
    inst->plugFrame.inst = inst;
    inst->bundle = bundle;
    inst->factory = factory;
    inst->component = comp;
    inst->processor = proc;

    // Query or instantiate IEditController
    Vst3EditController* ctrl = NULL;
    if (comp->lpVtbl->queryInterface(comp, VST3_IID_IEditController, (void**)&ctrl) == 0 && ctrl) {
        inst->controller = ctrl;
        inst->controllerIsSeparate = false;
    } else {
        uint8_t ctrlCid[16] = {0};
        if (comp->lpVtbl->getControllerClassId(comp, ctrlCid) == 0) {
            if (factory->lpVtbl->createInstance(factory, ctrlCid, VST3_IID_IEditController, (void**)&ctrl) == 0 && ctrl) {
                if (ctrl->lpVtbl->initialize(ctrl, &g_vst3HostApp) == 0) {
                    inst->controller = ctrl;
                    inst->controllerIsSeparate = true;
                } else {
                    ctrl->lpVtbl->release(ctrl);
                    ctrl = NULL;
                }
            }
        }
    }

    if (inst->controller) {
        inst->controller->lpVtbl->setComponentHandler(inst->controller, (void*)inst);

        // Connect IConnectionPoint between component and controller if separate
        if (inst->controllerIsSeparate) {
            comp->lpVtbl->queryInterface(comp, VST3_IID_IConnectionPoint, (void**)&inst->cpComp);
            inst->controller->lpVtbl->queryInterface(inst->controller, VST3_IID_IConnectionPoint, (void**)&inst->cpCtrl);
            if (inst->cpComp && inst->cpCtrl) {
                inst->cpComp->lpVtbl->connect(inst->cpComp, inst->cpCtrl);
                inst->cpCtrl->lpVtbl->connect(inst->cpCtrl, inst->cpComp);
            }
        }

        // Sync initial component state to controller via in-memory IBStream
        Vst3MemStream stream = { &g_vst3StreamVtbl, NULL, 0, 0, 0 };
        if (comp->lpVtbl->getState(comp, &stream) == 0 && stream.size > 0) {
            stream.cursor = 0;
            inst->controller->lpVtbl->setComponentState(inst->controller, &stream);
        }
        if (stream.data) free(stream.data);

        // Query optional IMidiMapping for automatic MIDI CC -> Parameter translation
        inst->controller->lpVtbl->queryInterface(inst->controller, VST3_IID_IMidiMapping, (void**)&inst->midiMapping);
    }

    // Configure Stereo Bus Arrangements and Activate Audio/Event Buses
    uint64_t stereoArr = 3; // kSpeakerArrStereo (L | R)
    proc->lpVtbl->setBusArrangements(proc, &stereoArr, 1, &stereoArr, 1);

    comp->lpVtbl->activateBus(comp, 0, 0, 0, 1); // Audio Input Bus 0
    comp->lpVtbl->activateBus(comp, 0, 1, 0, 1); // Audio Output Bus 0
    if (comp->lpVtbl->getBusCount(comp, 1, 0) > 0) {
        comp->lpVtbl->activateBus(comp, 1, 0, 0, 1); // Event (MIDI) Input Bus 0
    }

    Vst3ProcessSetup setup;
    setup.processMode = 0;        // kRealtime
    setup.symbolicSampleSize = 0; // kSample32
    setup.maxSamplesPerBlock = (blockSize > 0) ? blockSize : 1024;
    setup.sampleRate = (sampleRate > 8000.0) ? sampleRate : 48000.0;

    proc->lpVtbl->setupProcessing(proc, &setup);
    comp->lpVtbl->setActive(comp, 1);
    proc->lpVtbl->setProcessing(proc, 1);

    // Initial parameter sync to audio processor queue
    rane_vst3_sync_all_params_to_processor(inst);

    return inst;
}

void rane_vst3_send_midi(RaneVst3Instance* inst, uint8_t status, uint8_t data1, uint8_t data2, int32_t deltaFrames) {
    if (!inst) return;
    if (status >= 0xF8) return; // Tempo/Clock is delivered directly via ProcessContext in VST3

    uint8_t typeNib = status & 0xF0;
    int16_t channel = (int16_t)(status & 0x0F);

    if (typeNib == 0xB0) {
        // Control Change: map via IMidiMapping if supported by the plugin
        if (inst->midiMapping) {
            uint32_t paramId = 0;
            if (inst->midiMapping->lpVtbl->getMidiControllerAssignment(inst->midiMapping, 0, channel, (int16_t)data1, &paramId) == 0) {
                double normVal = (double)data2 / 127.0;
                vst3_push_param_change(inst, paramId, normVal, deltaFrames >= 0 ? deltaFrames : 0);
                if (inst->controller) {
                    inst->controller->lpVtbl->setParamNormalized(inst->controller, paramId, normVal);
                }
            }
        }
        // Also queue kLegacyMIDICCOutEvent into IEventList
        uint32_t w = inst->eventWriteIdx;
        uint32_t nextW = (w + 1) % MAX_VST3_EVENTS;
        if (nextW != inst->eventReadIdx) {
            Vst3Event* ev = &inst->eventRing[w];
            memset(ev, 0, sizeof(Vst3Event));
            ev->busIndex = 0;
            ev->sampleOffset = deltaFrames >= 0 ? deltaFrames : 0;
            ev->type = 65535; // kLegacyMIDICCOutEvent
            ev->midiCCOut.controlNumber = data1;
            ev->midiCCOut.channel = (int8_t)channel;
            ev->midiCCOut.value = (int8_t)data2;
            inst->eventWriteIdx = nextW;
        }
    } else if (typeNib == 0x90 || typeNib == 0x80) {
        bool isNoteOn = (typeNib == 0x90 && data2 > 0);
        uint32_t w = inst->eventWriteIdx;
        uint32_t nextW = (w + 1) % MAX_VST3_EVENTS;
        if (nextW != inst->eventReadIdx) {
            Vst3Event* ev = &inst->eventRing[w];
            memset(ev, 0, sizeof(Vst3Event));
            ev->busIndex = 0;
            ev->sampleOffset = deltaFrames >= 0 ? deltaFrames : 0;
            if (isNoteOn) {
                ev->type = 0; // kNoteOnEvent
                ev->noteOn.channel = channel;
                ev->noteOn.pitch = (int16_t)data1;
                ev->noteOn.velocity = (float)data2 / 127.0f;
                ev->noteOn.noteId = -1;
            } else {
                ev->type = 1; // kNoteOffEvent
                ev->noteOff.channel = channel;
                ev->noteOff.pitch = (int16_t)data1;
                ev->noteOff.velocity = (float)data2 / 127.0f;
                ev->noteOff.noteId = -1;
            }
            inst->eventWriteIdx = nextW;
        }
    }
}

void rane_vst3_process(RaneVst3Instance* inst, const float* inL, const float* inR, float* outL, float* outR, int32_t frames) {
    if (!inst || !inst->processor || frames <= 0) return;

    double sr = g_hostTimeInfo.sampleRate > 8000.0 ? g_hostTimeInfo.sampleRate : 48000.0;
    double bpm = g_hostTimeInfo.tempo > 30.0 ? g_hostTimeInfo.tempo : 124.0;
    double samplesPerBeat = (60.0 / bpm) * sr;
    double samplesPerClock = samplesPerBeat / 24.0;

    // 1. Drain queued Parameter Changes
    Vst3ParamChangesBlock inParams;
    inParams.lpVtbl = &g_vst3ParamChangesVtbl;
    inParams.count = 0;
    while (inst->paramReadIdx != inst->paramWriteIdx) {
        Vst3ParamChangeItem item = inst->paramRing[inst->paramReadIdx];
        inst->paramReadIdx = (inst->paramReadIdx + 1) % MAX_VST3_PARAM_CHANGES;

        int32_t found = -1;
        for (int32_t k = 0; k < inParams.count; k++) {
            if (inParams.queues[k].paramId == item.paramId) {
                found = k;
                break;
            }
        }
        if (found >= 0) {
            inParams.queues[found].sampleOffset = item.sampleOffset;
            inParams.queues[found].value = item.value;
        } else if (inParams.count < MAX_VST3_PARAM_CHANGES) {
            int32_t idx = inParams.count++;
            inParams.queues[idx].lpVtbl = &g_vst3SingleParamQueueVtbl;
            inParams.queues[idx].paramId = item.paramId;
            inParams.queues[idx].sampleOffset = item.sampleOffset;
            inParams.queues[idx].value = item.value;
        }
    }

    Vst3ParamChangesBlock outParams;
    outParams.lpVtbl = &g_vst3ParamChangesVtbl;
    outParams.count = 0;

    // 2. Drain queued MIDI Events
    Vst3EventList inEvents;
    inEvents.lpVtbl = &g_vst3EventListVtbl;
    inEvents.count = 0;
    while (inst->eventReadIdx != inst->eventWriteIdx && inEvents.count < MAX_VST3_EVENTS) {
        inEvents.events[inEvents.count++] = inst->eventRing[inst->eventReadIdx];
        inst->eventReadIdx = (inst->eventReadIdx + 1) % MAX_VST3_EVENTS;
    }

    // 3. Populate ProcessContext (Host Tempo, PPQ Beat Position & 24 PPQN Clock)
    Vst3ProcessContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    // kPlaying (1<<1) | kProjectTimeMusicValid (1<<9) | kBarPositionValid (1<<11) | kTempoValid (1<<10) | kTimeSigValid (1<<13) | kClockValid (1<<15)
    ctx.state = (1 << 1) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 13) | (1 << 15);
    ctx.sampleRate = sr;
    ctx.projectTimeSamples = (int64_t)inst->samplePos;
    ctx.continousTimeSamples = (int64_t)inst->samplePos;
    ctx.projectTimeMusic = inst->ppqPos;
    ctx.barPositionMusic = ((int32_t)(inst->ppqPos / 4.0)) * 4.0;
    ctx.tempo = bpm;
    ctx.timeSigNumerator = 4;
    ctx.timeSigDenominator = 4;
    ctx.samplesToNextClock = (int32_t)(samplesPerClock - inst->clockPhaseSamples);

    inst->samplePos += (double)frames;
    inst->ppqPos += ((double)frames) / samplesPerBeat;
    inst->clockPhaseSamples = fmod(inst->clockPhaseSamples + (double)frames, samplesPerClock);

    float* inChans[2] = { (float*)inL, (float*)inR };
    float* outChans[2] = { outL, outR };
    Vst3AudioBusBuffers inBus = { 2, 0, .channelBuffers32 = inChans };
    Vst3AudioBusBuffers outBus = { 2, 0, .channelBuffers32 = outChans };

    Vst3ProcessData data;
    memset(&data, 0, sizeof(data));
    data.processMode = 0;
    data.symbolicSampleSize = 0;
    data.numSamples = frames;
    data.numInputs = 1;
    data.numOutputs = 1;
    data.inputs = &inBus;
    data.outputs = &outBus;
    data.inputParameterChanges = &inParams;
    data.outputParameterChanges = &outParams;
    data.inputEvents = &inEvents;
    data.processContext = &ctx;

    inst->processor->lpVtbl->process(inst->processor, &data);

    if (inst->controller && outParams.count > 0) {
        for (int32_t i = 0; i < outParams.count; i++) {
            uint32_t pid = outParams.queues[i].paramId;
            double pval = outParams.queues[i].value;
            inst->controller->lpVtbl->setParamNormalized(inst->controller, pid, pval);
        }
    }
}

bool rane_vst3_get_editor_rect(RaneVst3Instance* inst, int* outW, int* outH) {
    if (!inst || !inst->controller) return false;
    if (!inst->activeView) {
        inst->activeView = (Vst3PlugView*)inst->controller->lpVtbl->createView(inst->controller, "editor");
    }
    if (!inst->activeView) return false;
    Vst3ViewRect rect = {0, 0, 0, 0};
    if (inst->activeView->lpVtbl->getSize(inst->activeView, &rect) == 0) {
        int w = rect.right - rect.left;
        int h = rect.bottom - rect.top;
        if (w > 0 && h > 0) {
            if (outW) *outW = w;
            if (outH) *outH = h;
            return true;
        }
    }
    return false;
}

bool rane_vst3_open_editor(RaneVst3Instance* inst, void* nsViewPtr) {
    if (!inst || !inst->controller || !nsViewPtr) return false;
    if (!inst->activeView) {
        inst->activeView = (Vst3PlugView*)inst->controller->lpVtbl->createView(inst->controller, "editor");
    }
    if (!inst->activeView) return false;
    if (inst->activeView->lpVtbl->isPlatformTypeSupported(inst->activeView, "NSView") != 0) {
        return false;
    }
    inst->activeView->lpVtbl->setFrame(inst->activeView, &inst->plugFrame);
    if (inst->activeView->lpVtbl->attached(inst->activeView, nsViewPtr, "NSView") == 0) {
        inst->activeView->lpVtbl->onFocus(inst->activeView, 1);
        return true;
    }
    return false;
}

void rane_vst3_set_focus(RaneVst3Instance* inst, bool hasFocus) {
    if (!inst || !inst->activeView) return;
    inst->activeView->lpVtbl->onFocus(inst->activeView, hasFocus ? 1 : 0);
}

bool rane_vst3_check_can_resize(RaneVst3Instance* inst) {
    if (!inst || !inst->activeView) return false;
    return (inst->activeView->lpVtbl->canResize(inst->activeView) == 0);
}

void rane_vst3_set_resize_callback(RaneVst3Instance* inst, RaneVstResizeCallback cb, void* context) {
    if (!inst) return;
    inst->resizeCallback = cb;
    inst->resizeContext = context;
}

void rane_vst3_close_editor(RaneVst3Instance* inst) {
    if (!inst || !inst->activeView) return;
    inst->activeView->lpVtbl->onFocus(inst->activeView, 0);
    inst->activeView->lpVtbl->removed(inst->activeView);
    inst->activeView->lpVtbl->setFrame(inst->activeView, NULL);
    inst->activeView->lpVtbl->release(inst->activeView);
    inst->activeView = NULL;
}

void rane_vst3_close(RaneVst3Instance* inst) {
    if (!inst) return;
    if (inst->activeView) {
        rane_vst3_close_editor(inst);
    }
    if (inst->processor) {
        inst->processor->lpVtbl->setProcessing(inst->processor, 0);
    }
    if (inst->component) {
        inst->component->lpVtbl->setActive(inst->component, 0);
    }
    if (inst->cpComp && inst->cpCtrl) {
        inst->cpComp->lpVtbl->disconnect(inst->cpComp, inst->cpCtrl);
        inst->cpCtrl->lpVtbl->disconnect(inst->cpCtrl, inst->cpComp);
    }
    if (inst->cpComp) inst->cpComp->lpVtbl->release(inst->cpComp);
    if (inst->cpCtrl) inst->cpCtrl->lpVtbl->release(inst->cpCtrl);
    if (inst->midiMapping) inst->midiMapping->lpVtbl->release(inst->midiMapping);

    if (inst->controller) {
        if (inst->controllerIsSeparate) {
            inst->controller->lpVtbl->terminate(inst->controller);
        }
        inst->controller->lpVtbl->release(inst->controller);
    }
    if (inst->processor) {
        inst->processor->lpVtbl->release(inst->processor);
    }
    if (inst->component) {
        inst->component->lpVtbl->terminate(inst->component);
        inst->component->lpVtbl->release(inst->component);
    }
    free(inst);
}

