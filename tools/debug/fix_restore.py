import re

text = """/* main.cpp - CoreMIDI LaunchAgent Daemon for Rane Mixers */
#include <CoreMIDI/CoreMIDI.h>
#include <IOKit/hid/IOHIDManager.h>
#include <CoreFoundation/CoreFoundation.h>
#include <atomic>
#include <csignal>
#include <os/log.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneMIDI-Agent] " fmt, ##__VA_ARGS__)

static const char* kSocketPath = "/tmp/com.dieckmann.rane.midi";

static IOHIDManagerRef gHIDManager = nullptr;
static IOHIDDeviceRef gHIDDevice = nullptr;
static MIDIClientRef gMidiClient = 0;
static MIDIEndpointRef gVirtualSource = 0;
static MIDIEndpointRef gVirtualDest = 0;

static std::atomic<bool> gRunning{true};
static std::atomic<int> gClientFd{-1};

static uint8_t gHIDReportBuf[1024];
static std::atomic<uint32_t> gHIDReportCount{0};

static void send_midi(const uint8_t* data, size_t len);
static void parse_and_forward_midi(const uint8_t *raw, size_t len);
static void cleanupMidi();

static void midiReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon) {
    (void)readProcRefCon;
    (void)srcConnRefCon;

    if (pktlist && gHIDDevice) {
        const MIDIPacket *packet = &pktlist->packet[0];
        for (UInt32 i = 0; i < pktlist->numPackets; ++i) {
            if (packet->length > 0) {
                uint8_t pkt[64] = {0};
                pkt[0] = 0x04;
                size_t copyLen = (packet->length < 63) ? packet->length : 63;
                memcpy(&pkt[1], packet->data, copyLen);
                IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pkt, (CFIndex)(copyLen + 1));
            }
            packet = MIDIPacketNext(packet);
        }
    }

    int fd = gClientFd.load();
    if (fd < 0 || !pktlist) return;

    const MIDIPacket *packet = &pktlist->packet[0];
    for (UInt32 i = 0; i < pktlist->numPackets; ++i) {
        if (packet->length > 0) {
            send(fd, packet->data, packet->length, 0);
        }
        packet = MIDIPacketNext(packet);
    }
}

static void onHIDInputReport(uint8_t* report, CFIndex length) {
    if (report && length > 0) {
        uint32_t n = gHIDReportCount.fetch_add(1);
        if (n < 2000) {
            char hex[64 * 3 + 1] = {0};
            CFIndex shown = length < 64 ? length : 64;
            for (CFIndex i = 0; i < shown; i++) snprintf(hex + i * 3, 4, "%02X ", report[i]);
            RLOG("HID IN #%u len=%ld: %{public}s", n, (long)length, hex);
        }
        parse_and_forward_midi(report, (size_t)length);
    }
}

static void hidCallbackTrampoline(void* context, IOReturn result, void* sender, IOHIDReportType type, uint32_t reportID, uint8_t* report, CFIndex reportLength) {
    (void)context; (void)result; (void)sender; (void)type; (void)reportID;
    onHIDInputReport(report, reportLength);
}

static bool setupHIDBridge() {
    if (gHIDManager) return true;

    gHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
    if (!gHIDManager) return false;

    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int vid = 0x1CC5;
    int pid = 0x0004;
    CFNumberRef vidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef pidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vidNum);
    CFDictionarySetValue(dict, CFSTR(kIOHIDProductIDKey), pidNum);
    CFRelease(vidNum);
    CFRelease(pidNum);

    IOHIDManagerSetDeviceMatching(gHIDManager, dict);
    CFRelease(dict);

    IOReturn kr = IOHIDManagerOpen(gHIDManager, kIOHIDOptionsTypeNone);
    RLOG("User-Space IOHIDManagerOpen kr: 0x%08x", kr);

    CFSetRef deviceSet = IOHIDManagerCopyDevices(gHIDManager);
    if (!deviceSet || CFSetGetCount(deviceSet) == 0) {
        if (deviceSet) CFRelease(deviceSet);
        return false;
    }

    CFIndex count = CFSetGetCount(deviceSet);
    IOHIDDeviceRef devices[8];
    CFSetGetValues(deviceSet, (const void**)devices);

    for (CFIndex i = 0; i < count; i++) {
        IOReturn dkr = IOHIDDeviceOpen(devices[i], kIOHIDOptionsTypeNone);
        if (dkr == kIOReturnSuccess) {
            gHIDDevice = devices[i];
            IOHIDDeviceRegisterInputReportCallback(
                gHIDDevice, gHIDReportBuf, sizeof(gHIDReportBuf),
                hidCallbackTrampoline, nullptr);
            IOHIDManagerScheduleWithRunLoop(gHIDManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            RLOG("Successfully opened IOHIDDevice in User-Space!");

            // Send Hardware Unmute Handshake!
            uint8_t pkt1[8] = { 0x04, 0xF0, 0x17, 0x52, 0x07, 0x01, 0xF7, 0x00 };
            IOReturn kr1 = IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pkt1, sizeof(pkt1));
            RLOG("Handshake Set Control Point kr: 0x%08x", kr1);

            usleep(20000);

            uint8_t pkt2[8] = { 0x04, 0xF0, 0x17, 0x04, 0x05, 0xF7, 0x00, 0x00 };
            IOReturn kr2 = IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pkt2, sizeof(pkt2));
            RLOG("Handshake Hardware Unmute kr: 0x%08x", kr2);

            usleep(20000);

            IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pkt1, sizeof(pkt1));
            RLOG("Rane Sixty-Eight hardware handshake sent & hardware UNMUTED!");
            break;
        }
    }

    CFRelease(deviceSet);
    return (gHIDDevice != nullptr);
}

static void setupMidi() {
    OSStatus status;

    status = MIDIClientCreate(CFSTR("Rane MIDI Agent"), nullptr, nullptr, &gMidiClient);
    if (status != noErr) {
        RLOG("Failed to create CoreMIDI client: %d", (int)status);
        return;
    }

    status = MIDISourceCreate(gMidiClient, CFSTR("Rane Sixty-Eight"), &gVirtualSource);
    if (status != noErr) {
        RLOG("Failed to create Virtual Source: %d", (int)status);
    } else {
        MIDIObjectSetIntegerProperty(gVirtualSource, kMIDIPropertyOffline, 0);
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyName, CFSTR("Rane Sixty-Eight"));
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyManufacturer, CFSTR("Rane Corporation"));
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyModel, CFSTR("Sixty-Eight"));
    }

    status = MIDIDestinationCreate(gMidiClient, CFSTR("Rane Sixty-Eight"), midiReadProc, nullptr, &gVirtualDest);
    if (status != noErr) {
        RLOG("Failed to create Virtual Destination: %d", (int)status);
    } else {
        MIDIObjectSetIntegerProperty(gVirtualDest, kMIDIPropertyOffline, 0);
        MIDIObjectSetStringProperty(gVirtualDest, kMIDIPropertyName, CFSTR("Rane Sixty-Eight"));
        MIDIObjectSetStringProperty(gVirtualDest, kMIDIPropertyManufacturer, CFSTR("Rane Corporation"));
        MIDIObjectSetStringProperty(gVirtualDest, kMIDIPropertyModel, CFSTR("Sixty-Eight"));
    }

    RLOG("CoreMIDI Virtual Source & Destination 'Rane Sixty-Eight' created successfully!");
}

static void cleanupMidi() {
    if (gHIDDevice) {
        IOHIDDeviceClose(gHIDDevice, kIOHIDOptionsTypeNone);
        gHIDDevice = nullptr;
    }
    if (gHIDManager) {
        IOHIDManagerUnscheduleFromRunLoop(gHIDManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDManagerClose(gHIDManager, kIOHIDOptionsTypeNone);
        CFRelease(gHIDManager);
        gHIDManager = nullptr;
    }
    if (gVirtualSource) MIDIEndpointDispose(gVirtualSource);
    if (gVirtualDest) MIDIEndpointDispose(gVirtualDest);
    if (gMidiClient) MIDIClientDispose(gMidiClient);
}

static int midi_msg_len(uint8_t status) {
    if (status >= 0xF8) return 1;             /* realtime */
    switch (status & 0xF0) {
        case 0x80: case 0x90: case 0xA0: case 0xB0: case 0xE0: return 3;
        case 0xC0: case 0xD0: return 2;
    }
    switch (status) {
        case 0xF1: case 0xF3: return 2;
        case 0xF2: return 3;
        case 0xF6: return 1;
    }
    return 0;                                  /* F0 handled separately, others invalid */
}

static void send_midi(const uint8_t* data, size_t len) {
    if (!gVirtualSource || len == 0) return;
    Byte packetBuf[1024];
    MIDIPacketList *pktList = (MIDIPacketList*)packetBuf;
    MIDIPacket *pkt = MIDIPacketListInit(pktList);
    pkt = MIDIPacketListAdd(pktList, sizeof(packetBuf), pkt, 0, (ByteCount)len, data);
    if (pkt) MIDIReceived(gVirtualSource, pktList);
}

static void parse_and_forward_midi(const uint8_t *raw, size_t len) {
    if (!gVirtualSource || len == 0) return;
    size_t i = 1;
    while (i < len) {
        uint8_t b = raw[i];
        if (b < 0x80) { i++; continue; }
        if (b == 0xF0) {
            size_t j = i + 1;
            while (j < len && raw[j] != 0xF7 && raw[j] < 0x80) j++;
            if (j < len && raw[j] == 0xF7) {
                send_midi(&raw[i], j - i + 1);
                i = j + 1;
            } else { i++; }
            continue;
        }
        int n = midi_msg_len(b);
        if (n > 0 && i + n <= len) {
            bool ok = true;
            for (int k = 1; k < n; k++) if (raw[i + k] >= 0x80) { ok = false; break; }
            if (ok) {
                send_midi(&raw[i], (size_t)n);
                i += n;
                continue;
            }
        }
        i++;
    }
}

static void signalHandler(int sig) {
    (void)sig;
    gRunning.store(false);
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    signal(SIGPIPE, SIG_IGN);

    RLOG("Rane MIDI Agent starting...");
    setupMidi();
    setupHIDBridge();

    int listenFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listenFd < 0) {
        RLOG("Failed to create socket: %s", strerror(errno));
        cleanupMidi();
        return 1;
    }

    unlink(kSocketPath);

    struct sockaddr_un addr = {};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);

    if (bind(listenFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        RLOG("Failed to bind socket at %s: %s", kSocketPath, strerror(errno));
        close(listenFd);
        cleanupMidi();
        return 1;
    }

    chmod(kSocketPath, 0777);

    if (listen(listenFd, 5) < 0) {
        RLOG("Failed to listen on socket: %s", strerror(errno));
        close(listenFd);
        cleanupMidi();
        return 1;
    }

    while (gRunning.load()) {
        int clientFd = accept(listenFd, nullptr, nullptr);
        if (clientFd >= 0) {
            RLOG("HAL Plugin connected (fd=%d)", clientFd);
            int oldFd = gClientFd.exchange(clientFd);
            if (oldFd >= 0) close(oldFd);

            int set = 1;
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &set, sizeof(set));
            
            while (gRunning.load()) {
                uint8_t rxBuffer[256];
                ssize_t n = recv(clientFd, rxBuffer, sizeof(rxBuffer), 0);
                if (n > 0) {
                    // Do not parse socket IN, since we are handling MIDI entirely in this agent!
                    // Wait, if HAL plugin sends MIDI to agent, we must send it to CoreMIDI?
                    // Actually, Traktor sends MIDI to VirtualDest, which sends it to device via HID.
                    // The socket is purely if we want to forward something from HAL to Traktor.
                } else if (n <= 0) {
                    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) continue;
                    RLOG("HAL Plugin disconnected (fd=%d)", clientFd);
                    gClientFd.store(-1);
                    close(clientFd);
                    break;
                }
            }
        } else {
            if (errno == EINTR) continue;
            usleep(100000);
        }
    }

    int finalFd = gClientFd.exchange(-1);
    if (finalFd >= 0) close(finalFd);
    close(listenFd);
    unlink(kSocketPath);
    cleanupMidi();

    RLOG("Rane MIDI Agent exited cleanly.");
    return 0;
}
"""

with open("src/midi-agent/main.cpp", "w") as f:
    f.write(text)
