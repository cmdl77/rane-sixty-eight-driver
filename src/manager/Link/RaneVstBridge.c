/* SPDX-License-Identifier: MIT */
/* RaneVstBridge.c - Universal VST 2.4 C Bridge Implementation */

#include "RaneVstBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
#define effGetEffectName        45
#define effGetVendorString      47
#define effGetProductString     48
#define effGetVendorVersion     49
#define effCanDo                51

// Host opcodes
#define audioMasterVersion              1
#define audioMasterGetSampleRate        15
#define audioMasterGetBlockSize         16
#define audioMasterGetCurrentProcessLevel 23
#define audioMasterGetVendorString      32
#define audioMasterGetProductString     33
#define audioMasterGetVendorVersion     34
#define audioMasterCanDo                37

static intptr_t rane_vst_host_callback(AEffect* effect, int32_t opcode, int32_t index, intptr_t value, void* ptr, float opt) {
    switch (opcode) {
        case audioMasterVersion:
            return 2400; // VST 2.4
        case audioMasterGetSampleRate:
            return 48000;
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
                    strcmp(canDo, "receiveVstEvents") == 0 ||
                    strcmp(canDo, "receiveVstMidiEvent") == 0 ||
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

    float* inBuffers[2] = { (float*)inL, (float*)inR };
    float* outBuffers[2] = { outL, outR };

    if (effect->processReplacing) {
        effect->processReplacing(effect, inBuffers, outBuffers, frames);
    } else if (effect->process) {
        effect->process(effect, inBuffers, outBuffers, frames);
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

void rane_vst_close(AEffect* effect, void* bundle) {
    if (!effect) return;
    effect->dispatcher(effect, effMainsChanged, 0, 0, NULL, 0.0f);
    effect->dispatcher(effect, effClose, 0, 0, NULL, 0.0f);
    if (bundle) {
        CFBundleRef cfBundle = (CFBundleRef)bundle;
        CFBundleUnloadExecutable(cfBundle);
        CFRelease(cfBundle);
    }
}
