/* SPDX-License-Identifier: MIT */
/* RaneHALPlugin.cpp - CoreAudio AudioServerPlugIn for Rane Sixty-Eight (16x16 Channels). */

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreAudio/AudioHardware.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <os/log.h>
#include <pthread.h>
#include <atomic>
#include <cstring>

#include "../engine/StreamEngine.h"
#include "../transport/IOUSBLibTransport.h"

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneHALPlugin] " fmt, ##__VA_ARGS__)

static constexpr AudioObjectID kObjectID_PlugIn        = kAudioObjectPlugInObject; /* = 1 */
static constexpr AudioObjectID kObjectID_Device        = 2;
static constexpr AudioObjectID kObjectID_Stream_Input  = 3;
static constexpr AudioObjectID kObjectID_Stream_Output = 4;

static constexpr UInt32 kChannels       = RANE_CHANNELS; /* 16 */
static constexpr UInt32 kBytesPerFloat  = sizeof(float); /* 4 */
static constexpr UInt32 kBytesPerFrame  = kChannels * kBytesPerFloat; /* 64 */
static constexpr UInt32 kZeroTSPeriod   = 16384;
static constexpr UInt32 kSafetyOffset   = 256;
static constexpr UInt32 kDeviceLatency  = 512;
static constexpr UInt32 kStreamLatency  = 0;

static const Float64 kSupportedRates[] = { 48000.0 };
static constexpr UInt32 kNumRates = sizeof(kSupportedRates) / sizeof(kSupportedRates[0]);

static AudioServerPlugInHostRef gHost = nullptr;
static pthread_mutex_t          gStateLock = PTHREAD_MUTEX_INITIALIZER;
static std::atomic<UInt32>      gRefCount{1};
static std::atomic<Float64>     gNominalRate{48000.0};
static std::atomic<UInt32>      gBufferFrameSize{512};
static std::atomic<bool>        gStreamInputActive{true};
static std::atomic<bool>        gStreamOutputActive{true};
static std::atomic<bool>        gDeviceRunning{false};
static std::atomic<bool>        gDeviceAlive{false};

static void LoadPersistedBufferFrameSize() {
    FILE* f = fopen("/tmp/rane_sixty_eight_buffer_size.txt", "r");
    if (!f) f = fopen("/var/tmp/rane_sixty_eight_buffer_size.txt", "r");
    if (f) {
        uint32_t s = 0;
        if (fscanf(f, "%u", &s) == 1 && s >= 64 && s <= 4096) {
            gBufferFrameSize.store(s);
            RLOG("Loaded persisted BufferFrameSize from file: %u", s);
            fclose(f);
            return;
        }
        fclose(f);
    }
    Boolean valid = false;
    CFIndex val = CFPreferencesGetAppIntegerValue(CFSTR("BufferFrameSize"), CFSTR("org.openrane.sixtyeight"), &valid);
    if (valid && val >= 64 && val <= 4096) {
        gBufferFrameSize.store((UInt32)val);
        RLOG("Loaded persisted BufferFrameSize from CFPreferences: %u", (UInt32)val);
    }
}

static void SavePersistedBufferFrameSize(UInt32 size) {
    FILE* f = fopen("/tmp/rane_sixty_eight_buffer_size.txt", "w");
    if (f) {
        fprintf(f, "%u\n", size);
        fclose(f);
    }
    FILE* f2 = fopen("/var/tmp/rane_sixty_eight_buffer_size.txt", "w");
    if (f2) {
        fprintf(f2, "%u\n", size);
        fclose(f2);
    }
    CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &size);
    if (num) {
        CFPreferencesSetAppValue(CFSTR("BufferFrameSize"), num, CFSTR("org.openrane.sixtyeight"));
        CFPreferencesAppSynchronize(CFSTR("org.openrane.sixtyeight"));
        CFRelease(num);
    }
    RLOG("Persisted BufferFrameSize: %u", size);
}

static void NotifyDeviceAvailability(bool alive) {
    if (alive) {
        LoadPersistedBufferFrameSize();
    }
    gDeviceAlive.store(alive);
    RLOG("Availability notification: %s", alive ? "Rane Device Connected" : "Rane Device Disconnected");
    if (!gHost) return;

    AudioObjectPropertyAddress addr{
        kAudioPlugInPropertyDeviceList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    gHost->PropertiesChanged(gHost, kObjectID_PlugIn, 1, &addr);

    addr.mSelector = kAudioDevicePropertyDeviceIsAlive;
    gHost->PropertiesChanged(gHost, kObjectID_Device, 1, &addr);
}

static AudioStreamBasicDescription MakeASBD(Float64 sampleRate) {
    AudioStreamBasicDescription asbd = {};
    asbd.mSampleRate       = sampleRate;
    asbd.mFormatID         = kAudioFormatLinearPCM;
    asbd.mFormatFlags      = (AudioFormatFlags)kAudioFormatFlagIsFloat
                           | (AudioFormatFlags)kAudioFormatFlagsNativeEndian
                           | (AudioFormatFlags)kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket   = kBytesPerFrame;
    asbd.mFramesPerPacket  = 1;
    asbd.mBytesPerFrame    = kBytesPerFrame;
    asbd.mChannelsPerFrame = kChannels;
    asbd.mBitsPerChannel   = 32;
    return asbd;
}

static OSStatus WriteCFString(CFStringRef s, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    if (outDataSize) *outDataSize = sizeof(CFStringRef);
    if (outData) {
        if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
        *(CFStringRef*)outData = s;
        CFRetain(s);
    }
    return noErr;
}

extern "C" __attribute__((visibility("default")))
void* RaneHALPlugInFactory(CFAllocatorRef allocator, CFUUIDRef typeUUID);

static HRESULT STDMETHODCALLTYPE RaneHAL_QueryInterface(void* driver, REFIID iid, LPVOID* outInterface) {
    (void)driver;
    if (!outInterface) return E_POINTER;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, iid);
    if (!requested) return E_INVALIDARG;
    CFUUIDRef iUnknown = IUnknownUUID;
    CFUUIDRef iPlugIn  = kAudioServerPlugInDriverInterfaceUUID;
    HRESULT result = E_NOINTERFACE;
    if (CFEqual(requested, iUnknown) || CFEqual(requested, iPlugIn)) {
        gRefCount.fetch_add(1);
        *outInterface = driver;
        result = S_OK;
    }
    CFRelease(requested);
    return result;
}

static ULONG STDMETHODCALLTYPE RaneHAL_AddRef(void*)  { return gRefCount.fetch_add(1) + 1; }
static ULONG STDMETHODCALLTYPE RaneHAL_Release(void*) { return gRefCount.fetch_sub(1) - 1; }

static OSStatus RaneHAL_Initialize(AudioServerPlugInDriverRef, AudioServerPlugInHostRef inHost) {
    gHost = inHost;
    RLOG("Initializing Rane HAL PlugIn");
    LoadPersistedBufferFrameSize();
    StreamEngine::shared().init();

    IOUSBLibTransport::shared().setAvailabilityHandler([](bool avail) {
        NotifyDeviceAvailability(avail);
    });
    bool opened = IOUSBLibTransport::shared().openDevice();
    if (opened || IOUSBLibTransport::shared().isOpen()) {
        NotifyDeviceAvailability(true);
    }
    IOUSBLibTransport::shared().ensureMonitor();
    return noErr;
}

static OSStatus RaneHAL_CreateDevice(AudioServerPlugInDriverRef, CFDictionaryRef, const AudioServerPlugInClientInfo*, AudioObjectID*) {
    return kAudioHardwareUnsupportedOperationError;
}
static OSStatus RaneHAL_DestroyDevice(AudioServerPlugInDriverRef, AudioObjectID) {
    return kAudioHardwareUnsupportedOperationError;
}
static OSStatus RaneHAL_AddDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*)   { return noErr; }
static OSStatus RaneHAL_RemoveDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*) { return noErr; }

static OSStatus RaneHAL_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64 inChangeAction, void*) {
    uint32_t newRate = (uint32_t)inChangeAction;
    if (newRate != 44100 && newRate != 48000 && newRate != 88200 && newRate != 96000)
        return kAudioHardwareIllegalOperationError;
    pthread_mutex_lock(&gStateLock);
    gNominalRate.store((Float64)newRate);
    StreamEngine::shared().setSampleRate(newRate);
    pthread_mutex_unlock(&gStateLock);
    return noErr;
}
static OSStatus RaneHAL_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*) { return noErr; }

static Boolean RaneHAL_HasProperty(AudioServerPlugInDriverRef, AudioObjectID inObjectID, pid_t,
                            const AudioObjectPropertyAddress* inAddress) {
    if (!inAddress) return false;

    switch (inObjectID) {
    case kObjectID_PlugIn:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
            return true;
        }
        return false;

    case kObjectID_Device:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange:
        case kAudioDevicePropertyPreferredChannelsForStereo:
            return true;
        }
        return false;

    case kObjectID_Stream_Input:
    case kObjectID_Stream_Output:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        }
        return false;
    }
    return false;
}

static OSStatus RaneHAL_IsPropertySettable(AudioServerPlugInDriverRef, AudioObjectID inObjectID, pid_t,
                                    const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable) {
    *outIsSettable = false;
    if (!inAddress) return kAudioHardwareUnknownPropertyError;
    if (inObjectID == kObjectID_Device) {
        switch (inAddress->mSelector) {
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
            *outIsSettable = true;
            return noErr;
        }
    }
    if (inObjectID == kObjectID_Stream_Input || inObjectID == kObjectID_Stream_Output) {
        switch (inAddress->mSelector) {
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outIsSettable = true;
            return noErr;
        }
    }
    return noErr;
}

static OSStatus RaneHAL_GetPropertyDataSize(AudioServerPlugInDriverRef, AudioObjectID inObjectID, pid_t,
                                     const AudioObjectPropertyAddress* inAddress,
                                     UInt32, const void*, UInt32* outDataSize) {
    if (!inAddress || !outDataSize) return kAudioHardwareUnknownPropertyError;

    switch (inObjectID) {
    case kObjectID_PlugIn:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:                   *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyResourceBundle:          *outDataSize = sizeof(CFStringRef); return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:              *outDataSize = gDeviceAlive.load() ? sizeof(AudioObjectID) : 0; return noErr;
        case kAudioPlugInPropertyTranslateUIDToDevice:    *outDataSize = sizeof(AudioObjectID); return noErr;
        }
        return kAudioHardwareUnknownPropertyError;

    case kObjectID_Device:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:                            *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:                         *outDataSize = sizeof(CFStringRef); return noErr;
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyZeroTimeStampPeriod:              *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyBufferFrameSizeRange:             *outDataSize = sizeof(AudioValueRange); return noErr;
        case kAudioDevicePropertyNominalSampleRate:                *outDataSize = sizeof(Float64); return noErr;
        case kAudioObjectPropertyOwnedObjects:                    *outDataSize = 2 * sizeof(AudioObjectID); return noErr;
        case kAudioDevicePropertyRelatedDevices:                   *outDataSize = sizeof(AudioObjectID); return noErr;
        case kAudioObjectPropertyControlList:                       *outDataSize = 0; return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates:      *outDataSize = kNumRates * sizeof(AudioValueRange); return noErr;
        case kAudioDevicePropertyStreams: {
            if (inAddress->mScope == kAudioObjectPropertyScopeInput)        *outDataSize = sizeof(AudioObjectID);
            else if (inAddress->mScope == kAudioObjectPropertyScopeOutput)  *outDataSize = sizeof(AudioObjectID);
            else                                                            *outDataSize = 2 * sizeof(AudioObjectID);
            return noErr;
        }
        case kAudioDevicePropertyPreferredChannelsForStereo:       *outDataSize = 2 * sizeof(UInt32); return noErr;
        }
        return kAudioHardwareUnknownPropertyError;

    case kObjectID_Stream_Input:
    case kObjectID_Stream_Output:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:               *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyName:                *outDataSize = sizeof(CFStringRef); return noErr;
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:             *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:      *outDataSize = sizeof(AudioStreamBasicDescription); return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *outDataSize = kNumRates * sizeof(AudioStreamRangedDescription);
            return noErr;
        }
        return kAudioHardwareUnknownPropertyError;
    }
    return kAudioHardwareBadObjectError;
}

static OSStatus RaneHAL_GetPropertyData(AudioServerPlugInDriverRef, AudioObjectID inObjectID, pid_t,
                                const AudioObjectPropertyAddress* inAddress,
                                UInt32 inQualifierDataSize, const void* inQualifierData,
                                UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    if (!inAddress || !outDataSize || !outData) return kAudioHardwareUnknownPropertyError;
    (void)inQualifierDataSize; (void)inDataSize;

    switch (inObjectID) {
    case kObjectID_PlugIn:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:   *(AudioClassID*)outData = kAudioObjectClassID;  *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyClass:       *(AudioClassID*)outData = kAudioPlugInClassID;  *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyOwner:       *(AudioObjectID*)outData = kAudioObjectUnknown; *outDataSize = sizeof(AudioObjectID); return noErr;
        case kAudioObjectPropertyManufacturer:return WriteCFString(CFSTR("Rane / Open Source Community"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            if (gDeviceAlive.load()) {
                ((AudioObjectID*)outData)[0] = kObjectID_Device;
                *outDataSize = sizeof(AudioObjectID);
            } else {
                *outDataSize = 0;
            }
            return noErr;
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            CFStringRef requestedUID = (inQualifierData ? *(CFStringRef*)inQualifierData : nullptr);
            if (requestedUID && CFEqual(requestedUID, CFSTR("org.openrane.sixtyeight"))) {
                *(AudioObjectID*)outData = kObjectID_Device;
            } else {
                *(AudioObjectID*)outData = kAudioObjectUnknown;
            }
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        }
        case kAudioPlugInPropertyResourceBundle:
            return WriteCFString(CFSTR(""), inDataSize, outDataSize, outData);
        }
        return kAudioHardwareUnknownPropertyError;

    case kObjectID_Device: {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:   *(AudioClassID*)outData = kAudioObjectClassID;  *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyClass:       *(AudioClassID*)outData = kAudioDeviceClassID;  *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyOwner:       *(AudioObjectID*)outData = kObjectID_PlugIn;    *outDataSize = sizeof(AudioObjectID); return noErr;
        case kAudioObjectPropertyName:        return WriteCFString(CFSTR("Rane Sixty-Eight"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyManufacturer:return WriteCFString(CFSTR("Rane Corporation"), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyDeviceUID:   return WriteCFString(CFSTR("org.openrane.sixtyeight"), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyModelUID:    return WriteCFString(CFSTR("RaneSixtyEight_Model"), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyTransportType:*(UInt32*)outData = kAudioDeviceTransportTypeUSB;   *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyClockDomain:  *(UInt32*)outData = 0;                                *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyDeviceIsAlive:*(UInt32*)outData = gDeviceAlive.load() ? 1 : 0;       *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyDeviceIsRunning:*(UInt32*)outData = gDeviceRunning.load() ? 1 : 0; *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyIsHidden:     *(UInt32*)outData = 0;                                *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyLatency:      *(UInt32*)outData = gBufferFrameSize.load();          *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertySafetyOffset: *(UInt32*)outData = std::max((UInt32)16, gBufferFrameSize.load() / 4); *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyBufferFrameSize:*(UInt32*)outData = gBufferFrameSize.load();         *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyBufferFrameSizeRange: {
            AudioValueRange* range = (AudioValueRange*)outData;
            range->mMinimum = 64.0;
            range->mMaximum = 4096.0;
            *outDataSize = sizeof(AudioValueRange);
            return noErr;
        }
        case kAudioDevicePropertyZeroTimeStampPeriod:*(UInt32*)outData = kZeroTSPeriod;              *outDataSize = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyNominalSampleRate:  *(Float64*)outData = gNominalRate.load();       *outDataSize = sizeof(Float64); return noErr;
        case kAudioObjectPropertyOwnedObjects: {
            ((AudioObjectID*)outData)[0] = kObjectID_Stream_Input;
            ((AudioObjectID*)outData)[1] = kObjectID_Stream_Output;
            *outDataSize = 2 * sizeof(AudioObjectID);
            return noErr;
        }
        case kAudioDevicePropertyRelatedDevices:
            ((AudioObjectID*)outData)[0] = kObjectID_Device;
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        case kAudioObjectPropertyControlList:
            *outDataSize = 0;
            return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            AudioValueRange* ranges = (AudioValueRange*)outData;
            for (UInt32 i = 0; i < kNumRates; i++) {
                ranges[i].mMinimum = kSupportedRates[i];
                ranges[i].mMaximum = kSupportedRates[i];
            }
            *outDataSize = kNumRates * sizeof(AudioValueRange);
            return noErr;
        }
        case kAudioDevicePropertyStreams: {
            if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
                ((AudioObjectID*)outData)[0] = kObjectID_Stream_Input;
                *outDataSize = sizeof(AudioObjectID);
            } else if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
                ((AudioObjectID*)outData)[0] = kObjectID_Stream_Output;
                *outDataSize = sizeof(AudioObjectID);
            } else {
                ((AudioObjectID*)outData)[0] = kObjectID_Stream_Input;
                ((AudioObjectID*)outData)[1] = kObjectID_Stream_Output;
                *outDataSize = 2 * sizeof(AudioObjectID);
            }
            return noErr;
        }
        case kAudioDevicePropertyPreferredChannelsForStereo:
            ((UInt32*)outData)[0] = 1;
            ((UInt32*)outData)[1] = 2;
            *outDataSize = 2 * sizeof(UInt32);
            return noErr;
        }
        return kAudioHardwareUnknownPropertyError;
    }

    case kObjectID_Stream_Input:
    case kObjectID_Stream_Output: {
        const bool isInput = (inObjectID == kObjectID_Stream_Input);
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:  *(AudioClassID*)outData = kAudioObjectClassID; *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyClass:      *(AudioClassID*)outData = kAudioStreamClassID; *outDataSize = sizeof(AudioClassID); return noErr;
        case kAudioObjectPropertyOwner:      *(AudioObjectID*)outData = kObjectID_Device;   *outDataSize = sizeof(AudioObjectID); return noErr;
        case kAudioObjectPropertyName:       return WriteCFString(isInput ? CFSTR("Rane Input (16 Ch)") : CFSTR("Rane Output (16 Ch)"),
                                                                 inDataSize, outDataSize, outData);
        case kAudioStreamPropertyIsActive:
            *(UInt32*)outData = (isInput ? gStreamInputActive.load() : gStreamOutputActive.load()) ? 1 : 0;
            *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyDirection:  *(UInt32*)outData = isInput ? 1 : 0;             *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyTerminalType:*(UInt32*)outData = kAudioStreamTerminalTypeLine;
                                              *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyStartingChannel:*(UInt32*)outData = 1;                       *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyLatency:    *(UInt32*)outData = gBufferFrameSize.load();      *outDataSize = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *(AudioStreamBasicDescription*)outData = MakeASBD(gNominalRate.load());
            *outDataSize = sizeof(AudioStreamBasicDescription); return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription* fmts = (AudioStreamRangedDescription*)outData;
            for (UInt32 i = 0; i < kNumRates; i++) {
                fmts[i].mFormat = MakeASBD(kSupportedRates[i]);
                fmts[i].mSampleRateRange.mMinimum = kSupportedRates[i];
                fmts[i].mSampleRateRange.mMaximum = kSupportedRates[i];
            }
            *outDataSize = kNumRates * sizeof(AudioStreamRangedDescription);
            return noErr;
        }
        }
        return kAudioHardwareUnknownPropertyError;
    }
    }
    return kAudioHardwareBadObjectError;
}

static OSStatus RaneHAL_SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID inObjectID, pid_t,
                                const AudioObjectPropertyAddress* inAddress,
                                UInt32, const void*, UInt32 inDataSize, const void* inData) {
    if (!inAddress) return kAudioHardwareUnknownPropertyError;

    if (inObjectID == kObjectID_Device &&
        inAddress->mSelector == kAudioDevicePropertyNominalSampleRate) {
        if (inDataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        Float64 newRate = *(const Float64*)inData;
        uint32_t rounded = (uint32_t)(newRate + 0.5);
        bool supported = false;
        for (UInt32 i = 0; i < kNumRates; i++)
            if (rounded == (uint32_t)kSupportedRates[i]) { supported = true; break; }
        if (!supported) return kAudioHardwareIllegalOperationError;

        if (gHost) {
            gHost->RequestDeviceConfigurationChange(gHost, kObjectID_Device, (UInt64)rounded, nullptr);
        }
        return noErr;
    }

    if (inObjectID == kObjectID_Device &&
        inAddress->mSelector == kAudioDevicePropertyBufferFrameSize) {
        if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        UInt32 newSize = *(const UInt32*)inData;
        if (newSize < 64 || newSize > 4096) return kAudioHardwareIllegalOperationError;
        gBufferFrameSize.store(newSize);
        SavePersistedBufferFrameSize(newSize);
        StreamEngine::shared().onBufferFrameSizeChanged(newSize);
        if (gHost) {
            AudioObjectPropertyAddress addrs[] = {
                { kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
                { kAudioDevicePropertyLatency,         kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
                { kAudioDevicePropertySafetyOffset,    kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain }
            };
            gHost->PropertiesChanged(gHost, kObjectID_Device, 3, addrs);
        }
        return noErr;
    }

    if ((inObjectID == kObjectID_Stream_Input || inObjectID == kObjectID_Stream_Output) &&
        (inAddress->mSelector == kAudioStreamPropertyVirtualFormat || inAddress->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        if (inDataSize < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        const AudioStreamBasicDescription* asbd = (const AudioStreamBasicDescription*)inData;
        uint32_t rounded = (uint32_t)(asbd->mSampleRate + 0.5);
        bool supported = false;
        for (UInt32 i = 0; i < kNumRates; i++)
            if (rounded == (uint32_t)kSupportedRates[i]) { supported = true; break; }
        if (!supported) return kAudioHardwareIllegalOperationError;
        gNominalRate.store((Float64)rounded);
        if (gHost) {
            AudioObjectPropertyAddress addrs[] = {
                { kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
                { kAudioStreamPropertyPhysicalFormat, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain }
            };
            gHost->PropertiesChanged(gHost, inObjectID, 2, addrs);
        }
        return noErr;
    }

    if ((inObjectID == kObjectID_Stream_Input || inObjectID == kObjectID_Stream_Output) &&
        inAddress->mSelector == kAudioStreamPropertyIsActive) {
        if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        UInt32 isActive = *(const UInt32*)inData;
        if (inObjectID == kObjectID_Stream_Input)  gStreamInputActive.store(isActive != 0);
        else                                       gStreamOutputActive.store(isActive != 0);
        if (gHost) {
            AudioObjectPropertyAddress addrs[] = {{ kAudioStreamPropertyIsActive,
                                                    kAudioObjectPropertyScopeGlobal,
                                                    kAudioObjectPropertyElementMain }};
            gHost->PropertiesChanged(gHost, inObjectID, 1, addrs);
        }
        return noErr;
    }

    (void)driver;
    return noErr;
}

static OSStatus RaneHAL_StartIO(AudioServerPlugInDriverRef, AudioObjectID deviceID, UInt32) {
    if (deviceID != kObjectID_Device) return kAudioHardwareBadObjectError;
    RLOG("StartIO requested");
    pthread_mutex_lock(&gStateLock);
    bool ok = StreamEngine::shared().start();
    if (ok) gDeviceRunning.store(true);
    pthread_mutex_unlock(&gStateLock);
    return ok ? noErr : (OSStatus)kAudioHardwareUnspecifiedError;
}

static OSStatus RaneHAL_StopIO(AudioServerPlugInDriverRef, AudioObjectID deviceID, UInt32) {
    if (deviceID != kObjectID_Device) return kAudioHardwareBadObjectError;
    RLOG("StopIO requested");
    pthread_mutex_lock(&gStateLock);
    StreamEngine::shared().stop();
    gDeviceRunning.store(false);
    pthread_mutex_unlock(&gStateLock);
    return noErr;
}

static OSStatus RaneHAL_GetZeroTimeStamp(AudioServerPlugInDriverRef, AudioObjectID deviceID, UInt32,
                                 Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    if (deviceID != kObjectID_Device) return kAudioHardwareBadObjectError;
    StreamEngine::shared().getZeroTimeStamp(outSampleTime, outHostTime, outSeed);
    if (*outHostTime == 0) {
        *outHostTime   = mach_absolute_time();
        *outSampleTime = 0;
        *outSeed       = 1;
    }
    return noErr;
}

static OSStatus RaneHAL_WillDoIOOperation(AudioServerPlugInDriverRef, AudioObjectID deviceID, UInt32,
                                  UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    if (deviceID != kObjectID_Device) return kAudioHardwareBadObjectError;
    *outWillDoInPlace = true;
    switch (inOperationID) {
    case kAudioServerPlugInIOOperationReadInput:
    case kAudioServerPlugInIOOperationWriteMix:
        *outWillDo = true; break;
    default:
        *outWillDo = false; break;
    }
    return noErr;
}

static OSStatus RaneHAL_BeginIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32,
                                 UInt32, const AudioServerPlugInIOCycleInfo*) { return noErr; }
static OSStatus RaneHAL_EndIOOperation  (AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32,
                                 UInt32, const AudioServerPlugInIOCycleInfo*) { return noErr; }

static OSStatus RaneHAL_DoIOOperation(AudioServerPlugInDriverRef, AudioObjectID deviceID,
                              AudioObjectID streamID, UInt32, UInt32 inOperationID,
                              UInt32 inIOBufferFrameSize,
                              const AudioServerPlugInIOCycleInfo* inIOCycleInfo,
                              void* ioMainBuffer, void*) {
    if (deviceID != kObjectID_Device) return kAudioHardwareBadObjectError;

    if (inIOBufferFrameSize >= 64 && inIOBufferFrameSize <= 4096) {
        if (gBufferFrameSize.load(std::memory_order_relaxed) != inIOBufferFrameSize) {
            gBufferFrameSize.store(inIOBufferFrameSize, std::memory_order_relaxed);
            StreamEngine::shared().onBufferFrameSizeChanged(inIOBufferFrameSize);
        }
    }

    if (inOperationID == kAudioServerPlugInIOOperationReadInput && streamID == kObjectID_Stream_Input) {
        const uint64_t sampleTime = (uint64_t)inIOCycleInfo->mInputTime.mSampleTime;
        StreamEngine::shared().readInput(sampleTime, inIOBufferFrameSize, (float*)ioMainBuffer);
        return noErr;
    }
    if (inOperationID == kAudioServerPlugInIOOperationWriteMix && streamID == kObjectID_Stream_Output) {
        static uint64_t sWriteCount = 0;
        if (sWriteCount++ % 50 == 0) {
            const float* fbuf = (const float*)ioMainBuffer;
            float p01 = 0, p23 = 0, p45 = 0, p67 = 0;
            if (fbuf) {
                for (UInt32 f = 0; f < inIOBufferFrameSize; f++) {
                    float v0 = fabsf(fbuf[f * kChannels + 0]); if (v0 > p01) p01 = v0;
                    float v1 = fabsf(fbuf[f * kChannels + 1]); if (v1 > p01) p01 = v1;
                    float v2 = fabsf(fbuf[f * kChannels + 2]); if (v2 > p23) p23 = v2;
                    float v3 = fabsf(fbuf[f * kChannels + 3]); if (v3 > p23) p23 = v3;
                    float v4 = fabsf(fbuf[f * kChannels + 4]); if (v4 > p45) p45 = v4;
                    float v5 = fabsf(fbuf[f * kChannels + 5]); if (v5 > p45) p45 = v5;
                    float v6 = fabsf(fbuf[f * kChannels + 6]); if (v6 > p67) p67 = v6;
                    float v7 = fabsf(fbuf[f * kChannels + 7]); if (v7 > p67) p67 = v7;
                }
            }
            RLOG("DoIO writeMix #%llu: frames=%u USB1(PGM1)=%.2f USB2(PGM2)=%.2f USB3(PGM3)=%.2f USB4(PGM4)=%.2f",
                 sWriteCount, inIOBufferFrameSize, p01, p23, p45, p67);
        }
        const uint64_t sampleTime = (uint64_t)inIOCycleInfo->mOutputTime.mSampleTime;
        StreamEngine::shared().writeOutput(sampleTime, inIOBufferFrameSize, (const float*)ioMainBuffer);
        return noErr;
    }
    return noErr;
}

static AudioServerPlugInDriverInterface gDriverInterface = {
    nullptr,
    RaneHAL_QueryInterface,
    RaneHAL_AddRef,
    RaneHAL_Release,
    RaneHAL_Initialize,
    RaneHAL_CreateDevice,
    RaneHAL_DestroyDevice,
    RaneHAL_AddDeviceClient,
    RaneHAL_RemoveDeviceClient,
    RaneHAL_PerformDeviceConfigurationChange,
    RaneHAL_AbortDeviceConfigurationChange,
    RaneHAL_HasProperty,
    RaneHAL_IsPropertySettable,
    RaneHAL_GetPropertyDataSize,
    RaneHAL_GetPropertyData,
    RaneHAL_SetPropertyData,
    RaneHAL_StartIO,
    RaneHAL_StopIO,
    RaneHAL_GetZeroTimeStamp,
    RaneHAL_WillDoIOOperation,
    RaneHAL_BeginIOOperation,
    RaneHAL_DoIOOperation,
    RaneHAL_EndIOOperation
};

static AudioServerPlugInDriverInterface* gDriverInterfacePtr = &gDriverInterface;

extern "C" __attribute__((visibility("default")))
void* RaneHALPlugInFactory(CFAllocatorRef allocator, CFUUIDRef typeUUID) {
    (void)allocator;
    if (CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return &gDriverInterfacePtr;
    }
    return nullptr;
}
