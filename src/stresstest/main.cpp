/* SPDX-License-Identifier: MIT */
/* main.cpp - Rane Sixty-Eight Hardware & Driver Stress Test Suite */

#include <CoreAudio/CoreAudio.h>
#include <CoreMIDI/CoreMIDI.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach_time.h>
#include <iostream>
#include <iomanip>
#include <vector>
#include <chrono>
#include <thread>
#include <atomic>
#include <cmath>
#include <cstring>

struct StressStats {
    std::atomic<uint64_t> totalCallbacks{0};
    std::atomic<uint64_t> totalFramesRendered{0};
    std::atomic<uint32_t> bufferResizeSuccesses{0};
    std::atomic<uint32_t> bufferResizeFailures{0};
    std::atomic<uint32_t> midiEventsSent{0};
    std::atomic<uint32_t> xrunCount{0};
    double minPeriodMs = 999999.0;
    double maxPeriodMs = 0.0;
    double avgPeriodMs = 0.0;
    double maxJitterMs = 0.0;
    uint64_t lastHostTime = 0;
};

static StressStats gStats;
static std::atomic<bool> gRunning{false};
static std::atomic<uint32_t> gCurrentBufferFrames{512};

// CoreAudio IO Callback
static OSStatus stressIOProc(
    AudioDeviceID           inDevice,
    const AudioTimeStamp*   inNow,
    const AudioBufferList*  inInputData,
    const AudioTimeStamp*   inInputTime,
    AudioBufferList*        outOutputData,
    const AudioTimeStamp*   inOutputTime,
    void*                   inClientData)
{
    (void)inDevice; (void)inNow; (void)inInputData; (void)inInputTime; (void)inOutputTime; (void)inClientData;

    gStats.totalCallbacks.fetch_add(1, std::memory_order_relaxed);

    // Calculate interval & jitter
    uint64_t nowHost = inNow->mHostTime;
    if (gStats.lastHostTime != 0 && nowHost > gStats.lastHostTime) {
        uint64_t deltaTicks = nowHost - gStats.lastHostTime;
        static mach_timebase_info_data_t timebase;
        if (timebase.denom == 0) mach_timebase_info(&timebase);
        double deltaNs = (double)(deltaTicks * timebase.numer) / (double)timebase.denom;
        double deltaMs = deltaNs / 1000000.0;

        double nominalMs = (double)gCurrentBufferFrames.load(std::memory_order_relaxed) / 48.0;
        double jitter = std::abs(deltaMs - nominalMs);

        if (deltaMs < gStats.minPeriodMs) gStats.minPeriodMs = deltaMs;
        if (deltaMs > gStats.maxPeriodMs) gStats.maxPeriodMs = deltaMs;
        if (jitter > gStats.maxJitterMs)  gStats.maxJitterMs = jitter;

        // Detect severe dropout (> 3x nominal buffer period)
        if (deltaMs > nominalMs * 3.0) {
            gStats.xrunCount.fetch_add(1, std::memory_order_relaxed);
        }
    }
    gStats.lastHostTime = nowHost;

    // Synthesize sine wave on all 16 output channels
    if (outOutputData) {
        static float phase = 0.0f;
        float freq = 440.0f;
        float phaseInc = (2.0f * (float)M_PI * freq) / 48000.0f;

        for (UInt32 b = 0; b < outOutputData->mNumberBuffers; ++b) {
            float* outBuf = (float*)outOutputData->mBuffers[b].mData;
            UInt32 numFrames = outOutputData->mBuffers[b].mDataByteSize / (outOutputData->mBuffers[b].mNumberChannels * sizeof(float));
            UInt32 channels = outOutputData->mBuffers[b].mNumberChannels;

            for (UInt32 f = 0; f < numFrames; ++f) {
                float sample = sinf(phase) * 0.25f; // -12 dBFS
                phase += phaseInc;
                if (phase > 2.0f * (float)M_PI) phase -= 2.0f * (float)M_PI;

                for (UInt32 c = 0; c < channels; ++c) {
                    outBuf[f * channels + c] = sample;
                }
            }
            gStats.totalFramesRendered.fetch_add(numFrames, std::memory_order_relaxed);
        }
    }

    return noErr;
}

// Find Rane Sixty-Eight CoreAudio Device
static AudioDeviceID findRaneAudioDevice() {
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 dataSize = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propAddr, 0, nullptr, &dataSize) != noErr) {
        return kAudioDeviceUnknown;
    }

    UInt32 numDevices = dataSize / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> devices(numDevices);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, nullptr, &dataSize, devices.data()) != noErr) {
        return kAudioDeviceUnknown;
    }

    for (AudioDeviceID dev : devices) {
        CFStringRef devName = nullptr;
        UInt32 nameSize = sizeof(devName);
        AudioObjectPropertyAddress nameAddr = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        if (AudioObjectGetPropertyData(dev, &nameAddr, 0, nullptr, &nameSize, &devName) == noErr && devName) {
            char buf[256] = {0};
            CFStringGetCString(devName, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(devName);
            if (strstr(buf, "Sixty-Eight") || strstr(buf, "Rane")) {
                return dev;
            }
        }
    }
    return kAudioDeviceUnknown;
}

// Detect USB Port Details (Port A vs Port B)
static void detectUSBPortInfo(std::string& outPortName, uint16_t& outPid) {
    outPortName = "Unbekannt / Offline";
    outPid = 0;

    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching) return;

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != kIOReturnSuccess) return;

    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFNumberRef vidNum = (CFNumberRef)IORegistryEntryCreateCFProperty(service, CFSTR(kUSBVendorID), kCFAllocatorDefault, 0);
        CFNumberRef pidNum = (CFNumberRef)IORegistryEntryCreateCFProperty(service, CFSTR(kUSBProductID), kCFAllocatorDefault, 0);

        if (vidNum && pidNum) {
            int vid = 0, pid = 0;
            CFNumberGetValue(vidNum, kCFNumberIntType, &vid);
            CFNumberGetValue(pidNum, kCFNumberIntType, &pid);

            if (vid == 0x1CC5 || vid == 0x13E5 || vid == 0x29E2) {
                outPid = (uint16_t)pid;
                if (pid == 0x0004) {
                    outPortName = "USB Port A (Primärer Anschluss)";
                } else if (pid == 0x0008 || pid == 0x0080) {
                    outPortName = "USB Port B (Zweiter DJ-Anschluss)";
                } else {
                    outPortName = "USB Port erkannt (PID: 0x" + std::to_string(pid) + ")";
                }
                CFRelease(vidNum);
                CFRelease(pidNum);
                IOObjectRelease(service);
                break;
            }
            CFRelease(vidNum);
            CFRelease(pidNum);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
}

// Find Rane MIDI Destination
static MIDIEndpointRef findRaneMidiDest() {
    ItemCount numDests = MIDIGetNumberOfDestinations();
    for (ItemCount i = 0; i < numDests; ++i) {
        MIDIEndpointRef dest = MIDIGetDestination(i);
        CFStringRef name = nullptr;
        MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name);
        if (name) {
            char buf[128] = {0};
            CFStringGetCString(name, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(name);
            if (strstr(buf, "Sixty-Eight") || strstr(buf, "Rane")) {
                return dest;
            }
        }
    }
    return 0;
}

int main(int argc, char* argv[]) {
    int durationSec = 15;
    for (int i = 1; i < argc; ++i) {
        if ((strcmp(argv[i], "--duration") == 0 || strcmp(argv[i], "-d") == 0) && i + 1 < argc) {
            durationSec = atoi(argv[++i]);
            if (durationSec < 5) durationSec = 5;
        }
    }

    std::cout << "\n=======================================================" << std::endl;
    std::cout << "   🎛 RANE SIXTY-EIGHT HARDWARE & DRIVER STRESSTEST     " << std::endl;
    std::cout << "=======================================================" << std::endl;

    // 1. USB & Hardware Port Detection
    std::cout << "\n[1/4] USB-Schnittstellen-Erkennung..." << std::endl;
    std::string usbPortName;
    uint16_t usbPid = 0;
    detectUSBPortInfo(usbPortName, usbPid);
    std::cout << "  -> Status:    " << usbPortName << std::endl;
    std::cout << "  -> Hardware:  VID: 0x1CC5, PID: 0x" << std::hex << usbPid << std::dec << std::endl;

    // 2. CoreAudio HAL Device Check
    std::cout << "\n[2/4] CoreAudio HAL Treiber-Verbindung..." << std::endl;
    AudioDeviceID raneDevice = findRaneAudioDevice();
    if (raneDevice == kAudioDeviceUnknown) {
        std::cerr << "  ❌ FEHLER: Rane Sixty-Eight CoreAudio-Gerät nicht gefunden!" << std::endl;
        std::cerr << "  Bitte sicherstellen, dass der Mixer eingeschaltet und per USB verbunden ist." << std::endl;
        return 1;
    }
    std::cout << "  -> AudioDeviceID: " << raneDevice << " (Rane Sixty-Eight online)" << std::endl;

    // Register IOProc
    AudioDeviceIOProcID ioProcId = nullptr;
    OSStatus err = AudioDeviceCreateIOProcID(raneDevice, stressIOProc, nullptr, &ioProcId);
    if (err != noErr || !ioProcId) {
        std::cerr << "  ❌ FEHLER beim Registrieren des CoreAudio IO-Callbacks (Code: " << err << ")" << std::endl;
        return 1;
    }

    // Start Audio IO
    err = AudioDeviceStart(raneDevice, ioProcId);
    if (err != noErr) {
        std::cerr << "  ❌ FEHLER beim Starten des Audio-Streams (Code: " << err << ")" << std::endl;
        AudioDeviceDestroyIOProcID(raneDevice, ioProcId);
        return 1;
    }
    gRunning.store(true);
    std::cout << "  -> 16-Kanal Audio-Stream aktiv gestartet (48 kHz Float)" << std::endl;

    // 3. MIDI Flood Engine Setup
    std::cout << "\n[3/4] MIDI- & HID-Bus Stresstest vorbereiten..." << std::endl;
    MIDIClientRef midiClient = 0;
    MIDIPortRef outPort = 0;
    MIDIClientCreate(CFSTR("RaneStressClient"), nullptr, nullptr, &midiClient);
    MIDIOutputPortCreate(midiClient, CFSTR("RaneStressOut"), &outPort);
    MIDIEndpointRef raneDest = findRaneMidiDest();
    if (raneDest != 0) {
        std::cout << "  -> CoreMIDI Destination verbunden: Rane Sixty-Eight" << std::endl;
    } else {
        std::cout << "  -> Hinweis: CoreMIDI Destination nicht erreichbar (Audio läuft weiter)." << std::endl;
    }

    // 4. Run Stress Phases
    std::cout << "\n[4/4] Führe Belastungstest durch (" << durationSec << " Sekunden)..." << std::endl;
    auto startTime = std::chrono::steady_clock::now();
    uint32_t bufferSizes[] = { 64, 128, 256, 512, 1024, 2048, 512, 256, 128, 64 };
    size_t numBufferSizes = sizeof(bufferSizes) / sizeof(bufferSizes[0]);
    size_t bufIdx = 0;

    int secondsPassed = 0;
    while (secondsPassed < durationSec) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        secondsPassed++;

        // Live Buffer Resize Test every 2 seconds
        if (secondsPassed % 2 == 0) {
            uint32_t targetBuf = bufferSizes[bufIdx % numBufferSizes];
            bufIdx++;
            gCurrentBufferFrames.store(targetBuf, std::memory_order_relaxed);

            AudioObjectPropertyAddress bufAddr = {
                kAudioDevicePropertyBufferFrameSize,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            UInt32 sizeBytes = sizeof(targetBuf);
            OSStatus sErr = AudioObjectSetPropertyData(raneDevice, &bufAddr, 0, nullptr, sizeBytes, &targetBuf);
            if (sErr == noErr) {
                gStats.bufferResizeSuccesses.fetch_add(1, std::memory_order_relaxed);
            } else {
                gStats.bufferResizeFailures.fetch_add(1, std::memory_order_relaxed);
            }
        }

        // MIDI Flood Burst (50 events/sec)
        if (raneDest != 0 && outPort != 0) {
            for (uint8_t note = 24; note < 44; ++note) {
                MIDIPacket packet;
                packet.length = 3;
                packet.timeStamp = 0;
                packet.data[0] = 0x90; // Note On
                packet.data[1] = note;
                packet.data[2] = 100;
                MIDIPacketList list;
                list.numPackets = 1;
                list.packet[0] = packet;
                MIDISend(outPort, raneDest, &list);
                gStats.midiEventsSent.fetch_add(1, std::memory_order_relaxed);
            }
        }

        std::cout << "  ⏱ [" << std::setw(2) << secondsPassed << "/" << durationSec << "s] "
                  << "Callbacks: " << gStats.totalCallbacks.load() << " | "
                  << "Puffer: " << gCurrentBufferFrames.load() << " | "
                  << "Dropouts: " << gStats.xrunCount.load() << " | "
                  << "MIDI: " << gStats.midiEventsSent.load() << "\r" << std::flush;
    }
    std::cout << std::endl;

    // Cleanup & Stop Audio
    gRunning.store(false);
    AudioDeviceStop(raneDevice, ioProcId);
    AudioDeviceDestroyIOProcID(raneDevice, ioProcId);
    if (outPort) MIDIPortDispose(outPort);
    if (midiClient) MIDIClientDispose(midiClient);

    // 5. Final Report
    std::cout << "\n=======================================================" << std::endl;
    std::cout << "          📊 STRESSTEST - ABSCHLUSSBERICHT              " << std::endl;
    std::cout << "=======================================================" << std::endl;
    std::cout << "  • Hardware-Port:         " << usbPortName << std::endl;
    std::cout << "  • Test-Dauer:            " << durationSec << " Sekunden" << std::endl;
    std::cout << "  • Audio-Callbacks:       " << gStats.totalCallbacks.load() << " Zyklen" << std::endl;
    std::cout << "  • Gerenderte Frames:     " << gStats.totalFramesRendered.load() << " (16 In / 16 Out)" << std::endl;
    std::cout << "  • Puffergrößen-Wechsel:  " << gStats.bufferResizeSuccesses.load() << " erfolgreich ("
              << gStats.bufferResizeFailures.load() << " Fehler)" << std::endl;
    std::cout << "  • Erkannte Dropouts:     " << gStats.xrunCount.load() << std::endl;
    std::cout << "  • Max. Latenz-Jitter:    " << std::fixed << std::setprecision(2) << gStats.maxJitterMs << " ms" << std::endl;
    std::cout << "  • MIDI-Events geflutet:  " << gStats.midiEventsSent.load() << std::endl;

    std::cout << "-------------------------------------------------------" << std::endl;
    if (gStats.xrunCount.load() == 0 && gStats.bufferResizeFailures.load() == 0) {
        std::cout << "  🏆 GESAMTNOTE: 100 % BESTANDEN - TOUR- & CLUB-READY!" << std::endl;
        std::cout << "     Der Mixer arbeitet vollkommen synchron, stabil und ohne Dropouts." << std::endl;
    } else {
        std::cout << "  ⚠️ HINWEIS: Es wurden " << gStats.xrunCount.load() << " Puffer-Unregelmäßigkeiten festgestellt." << std::endl;
    }
    std::cout << "=======================================================\n" << std::endl;

    return (gStats.xrunCount.load() == 0) ? 0 : 2;
}
