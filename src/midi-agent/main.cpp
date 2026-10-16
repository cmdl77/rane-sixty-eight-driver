/* main.cpp - CoreMIDI LaunchAgent Daemon for Rane Mixers */
#include <CoreMIDI/CoreMIDI.h>
#include <IOKit/hid/IOHIDManager.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <atomic>
#include <csignal>
#include <os/log.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneMIDI-Agent] " fmt, ##__VA_ARGS__)

static const char* kSocketPath = "/tmp/org.openrane.sixtyeight.midi";

static IOHIDManagerRef gHIDManager = nullptr;
static IOHIDDeviceRef gHIDDevice = nullptr;
static MIDIClientRef gMidiClient = 0;
static MIDIEndpointRef gVirtualSource = 0;
static MIDIEndpointRef gVirtualDest = 0;

static std::atomic<bool> gRunning{true};
static std::atomic<int> gClientFd{-1};

static uint8_t gHIDReportBuf[1024];
static std::atomic<uint32_t> gHIDReportCount{0};

static int midi_msg_len(uint8_t status);
static void send_midi(const uint8_t* data, size_t len);
static void parse_and_forward_midi(const uint8_t *raw, size_t len);
static void cleanupMidi();

/* Echo suppression: hardware echoes outgoing LED SetReport commands back on HID IN.
 * We must detect and drop these echoes to prevent infinite MIDI feedback loops in Traktor. */
struct PendingEcho {
    uint8_t data[4];
    size_t  len;
    uint64_t timestamp;
};

static constexpr size_t kMaxPendingEchoes = 128;
static PendingEcho gPendingEchoes[kMaxPendingEchoes];
static size_t gPendingEchoCount = 0;
static pthread_mutex_t gEchoMutex = PTHREAD_MUTEX_INITIALIZER;
static uint64_t gEchoTimeoutTicks = 0;

static void initEchoTimeout() {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    /* 1.5 seconds in mach ticks */
    gEchoTimeoutTicks = (1500000000ULL * tb.denom) / tb.numer;
}

static void register_outgoing_midi(const uint8_t* data, size_t len) {
    if (!data || len == 0) return;
    pthread_mutex_lock(&gEchoMutex);
    uint64_t now = mach_absolute_time();

    size_t offset = 0;
    while (offset < len) {
        uint8_t st = data[offset];
        if (st >= 0xF8) {
            /* Realtime messages (Clock, Start, Stop) must never pollute echo table */
            offset++;
            continue;
        }
        int mLen = midi_msg_len(st);
        if (mLen <= 0 || offset + mLen > len) {
            mLen = (len - offset > 4) ? 4 : (int)(len - offset);
        }
        if (gPendingEchoCount < kMaxPendingEchoes) {
            auto& e = gPendingEchoes[gPendingEchoCount++];
            e.len = (size_t)mLen;
            memcpy(e.data, data + offset, mLen);
            e.timestamp = now;
        }
        offset += mLen;
    }
    pthread_mutex_unlock(&gEchoMutex);
}

static bool midi_msgs_match(const uint8_t* a, const uint8_t* b, size_t len) {
    if (len == 0) return false;
    if (memcmp(a, b, len) == 0) return true;
    if (len == 3) {
        bool a_note_off = ((a[0] & 0xF0) == 0x80) || (((a[0] & 0xF0) == 0x90) && a[2] == 0);
        bool b_note_off = ((b[0] & 0xF0) == 0x80) || (((b[0] & 0xF0) == 0x90) && b[2] == 0);
        if (a_note_off && b_note_off && (a[0] & 0x0F) == (b[0] & 0x0F) && a[1] == b[1]) {
            return true;
        }
    }
    return false;
}

static bool check_and_suppress_echo(const uint8_t* data, size_t len) {
    if (!data || len == 0) return false;
    bool found = false;
    pthread_mutex_lock(&gEchoMutex);
    uint64_t now = mach_absolute_time();

    for (size_t i = 0; i < gPendingEchoCount; i++) {
        if (gPendingEchoes[i].len == len && midi_msgs_match(gPendingEchoes[i].data, data, len)) {
            found = true;
            for (size_t j = i; j + 1 < gPendingEchoCount; j++) {
                gPendingEchoes[j] = gPendingEchoes[j + 1];
            }
            gPendingEchoCount--;
            break;
        }
    }

    size_t writeIdx = 0;
    for (size_t i = 0; i < gPendingEchoCount; i++) {
        uint64_t diff = (now > gPendingEchoes[i].timestamp) ? (now - gPendingEchoes[i].timestamp) : 0;
        if (diff < gEchoTimeoutTicks) {
            if (writeIdx != i) gPendingEchoes[writeIdx] = gPendingEchoes[i];
            writeIdx++;
        }
    }
    gPendingEchoCount = writeIdx;

    pthread_mutex_unlock(&gEchoMutex);
    return found;
}

static pthread_mutex_t gDeviceMutex = PTHREAD_MUTEX_INITIALIZER;
static std::atomic<uint32_t> gTxSeq{100};

static void midiReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon) {
    (void)readProcRefCon;
    (void)srcConnRefCon;

    pthread_mutex_lock(&gDeviceMutex);
    IOHIDDeviceRef dev = gHIDDevice;
    if (pktlist && dev) {
        const MIDIPacket *packet = &pktlist->packet[0];
        for (UInt32 i = 0; i < pktlist->numPackets; ++i) {
            if (packet->length > 0) {
                register_outgoing_midi(packet->data, packet->length);

                uint8_t pkt[64] = {0};
                pkt[0] = 0x41; // Opcode 0x41 for HIDI / MIDI transmission
                uint32_t seq = gTxSeq.fetch_add(1);
                pkt[1] = (uint8_t)((seq >> 24) & 0xFF);
                pkt[2] = (uint8_t)((seq >> 16) & 0xFF);
                pkt[3] = (uint8_t)((seq >> 8) & 0xFF);
                pkt[4] = (uint8_t)(seq & 0xFF);
                size_t copyLen = (packet->length < 58) ? packet->length : 58;
                pkt[5] = (uint8_t)copyLen;
                memcpy(&pkt[6], packet->data, copyLen);
                IOReturn kr = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, pkt, 64);
                static std::atomic<uint32_t> sClockLogCount{0};
                if (packet->data[0] < 0xF8) {
                    RLOG("CoreMIDI Out -> HID (kr=0x%08x): %zu bytes: %02X %02X %02X",
                         kr, copyLen, packet->data[0], (copyLen > 1 ? packet->data[1] : 0), (copyLen > 2 ? packet->data[2] : 0));
                } else if (packet->data[0] == 0xF8) {
                    if ((sClockLogCount.fetch_add(1) % 96) == 0) { // Log once every 4 beats at 24 ppqn
                        RLOG("CoreMIDI Out -> HID: Clock 0xF8 active (kr=0x%08x, seq=%u)", kr, seq);
                    }
                } else {
                    RLOG("CoreMIDI Out -> HID Realtime (kr=0x%08x): %02X", kr, packet->data[0]);
                }
            }
            packet = MIDIPacketNext(packet);
        }
    }
    pthread_mutex_unlock(&gDeviceMutex);

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
    if (!report || length < 6) return;

    uint32_t n = gHIDReportCount.fetch_add(1);
    if (n < 2000) {
        char hex[32 * 3 + 1] = {0};
        CFIndex shown = length < 32 ? length : 32;
        for (CFIndex i = 0; i < shown; i++) snprintf(hex + i * 3, 4, "%02X ", report[i]);
        RLOG("HID IN #%u len=%ld: %{public}s", n, (long)length, hex);
    }

    if (report[0] == 0x40 || report[0] == 0x41) {
        uint8_t payloadLen = report[5];
        if (payloadLen > 0 && payloadLen <= (length - 6)) {
            parse_and_forward_midi(report + 6, payloadLen);
        }
    } else if (report[0] == 0xFF) {
        parse_and_forward_midi(report + 1, (size_t)(length - 1));
    }
}

static void hidCallbackTrampoline(void* context, IOReturn result, void* sender, IOHIDReportType type, uint32_t reportID, uint8_t* report, CFIndex reportLength) {
    (void)context; (void)result; (void)sender; (void)type; (void)reportID;
    onHIDInputReport(report, reportLength);
}

static void onDeviceMatched(void* context, IOReturn result, void* sender, IOHIDDeviceRef device) {
    (void)context; (void)result; (void)sender;
    if (!device) return;

    pthread_mutex_lock(&gDeviceMutex);
    if (gHIDDevice) {
        pthread_mutex_unlock(&gDeviceMutex);
        return;
    }

    IOReturn kr = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    RLOG("onDeviceMatched IOHIDDeviceOpen kr: 0x%08x", kr);
    if (kr != kIOReturnSuccess) {
        pthread_mutex_unlock(&gDeviceMutex);
        return;
    }

    gHIDDevice = device;
    IOHIDDeviceRegisterInputReportCallback(
        gHIDDevice, gHIDReportBuf, sizeof(gHIDReportBuf),
        hidCallbackTrampoline, nullptr);
    IOHIDDeviceScheduleWithRunLoop(gHIDDevice, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    RLOG("Successfully opened Sixty-Eight IOHIDDevice in User-Space!");
    if (gVirtualSource) MIDIObjectSetIntegerProperty(gVirtualSource, kMIDIPropertyOffline, 0);
    if (gVirtualDest) MIDIObjectSetIntegerProperty(gVirtualDest, kMIDIPropertyOffline, 0);

    // 1. Send Opcode 0x36: InitHid command (64 bytes) to activate HID reporting engine
    uint8_t pktInit[64] = {0};
    pktInit[0] = 0x36;
    pktInit[1] = 0x00; pktInit[2] = 0x00; pktInit[3] = 0x00; pktInit[4] = 0x01;
    pktInit[5] = 0x01;
    IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pktInit, sizeof(pktInit));
    usleep(20000);

    // 2. Send Opcode 0x41 with SysEx 0x52 (Set Control Point Port A, 5 bytes: F0 17 52 00 F7)
    uint8_t pktUnmute[64] = {0};
    pktUnmute[0] = 0x41;
    pktUnmute[1] = 0x00; pktUnmute[2] = 0x00; pktUnmute[3] = 0x00; pktUnmute[4] = 0x02;
    pktUnmute[5] = 0x05;
    pktUnmute[6] = 0xF0;
    pktUnmute[7] = 0x17;
    pktUnmute[8] = 0x52;
    pktUnmute[9] = 0x00;
    pktUnmute[10] = 0xF7;
    IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pktUnmute, sizeof(pktUnmute));
    usleep(20000);

    // 3. Send Opcode 0x41 with SysEx 0x18 (LPC2468 ROM Security Unlock, 11 bytes)
    uint8_t pktUnlock[64] = {0};
    pktUnlock[0] = 0x41;
    pktUnlock[1] = 0x00; pktUnlock[2] = 0x00; pktUnlock[3] = 0x00; pktUnlock[4] = 0x03;
    pktUnlock[5] = 0x0B;
    const uint8_t unlockSysEx[11] = {0xF0, 0x17, 0x18, 0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01, 0xF7};
    memcpy(&pktUnlock[6], unlockSysEx, sizeof(unlockSysEx));
    IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pktUnlock, sizeof(pktUnlock));
    usleep(20000);

    // 4. Send Opcode 0x41 with SysEx 0x04 (Get All Controls / Initial Dump, 4 bytes: F0 17 04 F7)
    uint8_t pktSysEx[64] = {0};
    pktSysEx[0] = 0x41;
    pktSysEx[1] = 0x00; pktSysEx[2] = 0x00; pktSysEx[3] = 0x00; pktSysEx[4] = 0x04;
    pktSysEx[5] = 0x04;
    pktSysEx[6] = 0xF0;
    pktSysEx[7] = 0x17;
    pktSysEx[8] = 0x04;
    pktSysEx[9] = 0xF7;
    IOHIDDeviceSetReport(gHIDDevice, kIOHIDReportTypeOutput, 0, pktSysEx, sizeof(pktSysEx));

    RLOG("Sixty-Eight HID activated, ROM unlocked & Control Point set!");
    pthread_mutex_unlock(&gDeviceMutex);
}

static void onDeviceRemoved(void* context, IOReturn result, void* sender, IOHIDDeviceRef device) {
    (void)context; (void)result; (void)sender;
    pthread_mutex_lock(&gDeviceMutex);
    if (gHIDDevice == device) {
        RLOG("Sixty-Eight IOHIDDevice disconnected.");
        IOHIDDeviceUnscheduleFromRunLoop(gHIDDevice, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDDeviceClose(gHIDDevice, kIOHIDOptionsTypeNone);
        gHIDDevice = nullptr;
        if (gVirtualSource) MIDIObjectSetIntegerProperty(gVirtualSource, kMIDIPropertyOffline, 1);
        if (gVirtualDest) MIDIObjectSetIntegerProperty(gVirtualDest, kMIDIPropertyOffline, 1);
    }
    pthread_mutex_unlock(&gDeviceMutex);
}

static bool setupHIDBridge() {
    if (gHIDManager) return true;

    gHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
    if (!gHIDManager) return false;

    // Match both USB A (PID 0x0004) and USB B (PID 0x0008)
    CFMutableArrayRef matchArray = CFArrayCreateMutable(kCFAllocatorDefault, 2, &kCFTypeArrayCallBacks);
    int pids[2] = { 0x0004, 0x0008 };
    for (int p : pids) {
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        int vid = 0x1CC5;
        CFNumberRef vidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
        CFNumberRef pidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &p);
        CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vidNum);
        CFDictionarySetValue(dict, CFSTR(kIOHIDProductIDKey), pidNum);
        CFRelease(vidNum);
        CFRelease(pidNum);
        CFArrayAppendValue(matchArray, dict);
        CFRelease(dict);
    }
    IOHIDManagerSetDeviceMatchingMultiple(gHIDManager, matchArray);
    CFRelease(matchArray);

    IOHIDManagerRegisterDeviceMatchingCallback(gHIDManager, onDeviceMatched, nullptr);
    IOHIDManagerRegisterDeviceRemovalCallback(gHIDManager, onDeviceRemoved, nullptr);
    IOHIDManagerScheduleWithRunLoop(gHIDManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    IOReturn kr = IOHIDManagerOpen(gHIDManager, kIOHIDOptionsTypeNone);
    RLOG("User-Space IOHIDManagerOpen kr: 0x%08x", kr);
    return (kr == kIOReturnSuccess);
}

static void setupMidi() {
    OSStatus status;

    status = MIDIClientCreate(CFSTR("Rane MIDI Agent"), nullptr, nullptr, &gMidiClient);
    if (status != noErr) {
        RLOG("Failed to create CoreMIDI client: %d", (int)status);
        return;
    }

    int initOffline = (gHIDDevice != nullptr) ? 0 : 1;
    status = MIDISourceCreate(gMidiClient, CFSTR("Rane Sixty-Eight"), &gVirtualSource);
    if (status != noErr) {
        RLOG("Failed to create Virtual Source: %d", (int)status);
    } else {
        MIDIObjectSetIntegerProperty(gVirtualSource, kMIDIPropertyOffline, initOffline);
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyName, CFSTR("Rane Sixty-Eight"));
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyManufacturer, CFSTR("Rane Corporation"));
        MIDIObjectSetStringProperty(gVirtualSource, kMIDIPropertyModel, CFSTR("Sixty-Eight"));
    }

    status = MIDIDestinationCreate(gMidiClient, CFSTR("Rane Sixty-Eight"), midiReadProc, nullptr, &gVirtualDest);
    if (status != noErr) {
        RLOG("Failed to create Virtual Destination: %d", (int)status);
    } else {
        MIDIObjectSetIntegerProperty(gVirtualDest, kMIDIPropertyOffline, initOffline);
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

    size_t idx = 0;
    while (idx < len) {
        uint8_t st = raw[idx];
        if (st < 0x80) {
            idx++;
            continue;
        }

        if (st == 0xF0) {
            /* SysEx: scan for 0xF7 */
            size_t end = idx + 1;
            while (end < len && raw[end] != 0xF7) end++;
            if (end < len && raw[end] == 0xF7) {
                end++; /* Include 0xF7 */
                size_t sysexLen = end - idx;
                send_midi(raw + idx, sysexLen);
                RLOG("Forwarded SysEx (%zu bytes)", sysexLen);
                idx = end;
                continue;
            } else {
                break;
            }
        }

        int msgLen = midi_msg_len(st);
        if (msgLen <= 0 || idx + msgLen > len) {
            idx++;
            continue;
        }

        /* Validate that all payload data bytes have MSB = 0 */
        bool valid = true;
        for (int k = 1; k < msgLen; k++) {
            if (raw[idx + k] & 0x80) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            idx++;
            continue;
        }

        /* Suppress hardware echo of outgoing LED commands */
        if (!check_and_suppress_echo(raw + idx, (size_t)msgLen)) {
            send_midi(raw + idx, (size_t)msgLen);
            if (msgLen == 3) {
                RLOG("Forwarded MIDI: %02X %02X %02X", raw[idx], raw[idx+1], raw[idx+2]);
            } else if (msgLen == 2) {
                RLOG("Forwarded MIDI: %02X %02X", raw[idx], raw[idx+1]);
            } else {
                RLOG("Forwarded MIDI: %02X", raw[idx]);
            }
        } else {
            RLOG("Suppressed hardware echo: %02X %02X %02X",
                 raw[idx], (msgLen > 1 ? raw[idx+1] : 0), (msgLen > 2 ? raw[idx+2] : 0));
        }

        idx += msgLen;
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
    initEchoTimeout();
    setupMidi();

    // Start HID Bridge on a dedicated thread with its own CFRunLoop!
    pthread_t hidThread;
    pthread_create(&hidThread, nullptr, [](void*) -> void* {
        RLOG("HID RunLoop thread starting...");
        setupHIDBridge();
        CFRunLoopRun();
        return nullptr;
    }, nullptr);

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
