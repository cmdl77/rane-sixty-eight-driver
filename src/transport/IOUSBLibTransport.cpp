/* SPDX-License-Identifier: MIT */
/* IOUSBLibTransport.cpp - User-space IOUSBLib USB transport implementation. */

#include "IOUSBLibTransport.h"
#include "../protocol/rane_packet.h"

#include <CoreAudio/AudioHardware.h>
#include <mach/mach_time.h>
#include <os/log.h>
#include <sys/time.h>
#include <unistd.h>
#include <cmath>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneTransport] " fmt, ##__VA_ARGS__)

IOUSBLibTransport& IOUSBLibTransport::shared() {
    static IOUSBLibTransport sShared;
    return sShared;
}

IOUSBLibTransport::IOUSBLibTransport() {
    mInRing.init(kInRingBytes, kInChannels * sizeof(float));
    mOutRing.init(kOutRingBytes, kOutChannels * sizeof(float));

    for (uint32_t i = 0; i < kDoubleBuffer; i++) {
        mOutSlotInFlight[i].store(false);
        mInSlotInFlight[i].store(false);
        mOutBuf[i] = (uint8_t*)calloc(1, kWireBufBytes);
        mInBuf[i]  = (uint8_t*)calloc(1, kWireBufBytes);

        mOutCtx[i] = { this, i };
        mInCtx[i]  = { this, i };
    }

    for (uint32_t i = 0; i < kMidiInSlots; i++) {
        mMidiSlotInFlight[i].store(false);
        mMidiInBuf[i] = (uint8_t*)malloc(kMidiInBufSize);
        mMidiInCtx[i] = { this, i };
    }

    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    double nsPerTick = (double)tb.numer / (double)tb.denom;
    mHostTicksPerFrame = 1e9 / (nsPerTick * (double)mSampleRate);

    setupHotplugNotification();
}

IOUSBLibTransport::~IOUSBLibTransport() {
    stopStreaming();
    teardownHotplugNotification();
    closeDevice();

    for (uint32_t i = 0; i < kDoubleBuffer; i++) {
        if (mOutBuf[i]) free(mOutBuf[i]);
        if (mInBuf[i])  free(mInBuf[i]);
    }
    for (uint32_t i = 0; i < kMidiInSlots; i++) {
        if (mMidiInBuf[i]) free(mMidiInBuf[i]);
    }
}

bool IOUSBLibTransport::ensureMonitor() {
    if (mMonitorThread == 0) {
        mMonitorShutdown.store(false);
        pthread_create(&mMonitorThread, nullptr, &IOUSBLibTransport::monitorEntry, this);
    }
    return true;
}

void* IOUSBLibTransport::monitorEntry(void* arg) {
    static_cast<IOUSBLibTransport*>(arg)->monitorLoop();
    return nullptr;
}

void IOUSBLibTransport::monitorLoop() {
    RLOG("[Watchdog] Hardware watchdog monitor loop started.");
    while (!mMonitorShutdown.load()) {
        usleep(500000);
        if (mMonitorShutdown.load()) break;

        if (!mDeviceOpen.load()) {
            uint16_t vid = 0, pid = 0;
            if (findDevice(&vid, &pid)) {
                RLOG("[Watchdog] Found Rane USB Device powered ON! Opening device...");
                openDevice();
            }
        }
    }
}

static const char* getUSBDeviceClassName() {
    return kIOUSBDeviceClassName;
}

bool IOUSBLibTransport::findDevice(uint16_t *outVid, uint16_t *outPid) {
    CFMutableDictionaryRef matchingDict = IOServiceMatching(getUSBDeviceClassName());
    if (!matchingDict) return false;

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iter) != kIOReturnSuccess) {
        return false;
    }

    bool found = false;
    io_service_t deviceService = IO_OBJECT_NULL;

    while ((deviceService = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface** plugIn = nullptr;
        SInt32 score = 0;
        IOReturn kr = IOCreatePlugInInterfaceForService(
            deviceService, kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugIn, &score);

        if (kr == kIOReturnSuccess && plugIn) {
            IOUSBDeviceInterface942** dev = nullptr;
            HRESULT res = (*plugIn)->QueryInterface(
                plugIn, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID*)&dev);
            (*plugIn)->Release(plugIn);

            if (res == S_OK && dev) {
                UInt16 vendor = 0, product = 0;
                (*dev)->GetDeviceVendor(dev, &vendor);
                (*dev)->GetDeviceProduct(dev, &product);

                const RaneDeviceInfo* info = rane_lookup_device(vendor, product);
                if (info) {
                    mCurrentVID = vendor;
                    mCurrentPID = product;
                    if (outVid) *outVid = vendor;
                    if (outPid) *outPid = product;
                    found = true;
                    RLOG("Found Rane Device: %s (VID: 0x%04X, PID: 0x%04X)", info->displayName, vendor, product);
                }
                (*dev)->Release(dev);
            }
        }
        IOObjectRelease(deviceService);
        if (found) break;
    }

    IOObjectRelease(iter);
    return found;
}

bool IOUSBLibTransport::openDevice() {
    if (mDeviceOpen.load()) return true;

    uint16_t vid = 0, pid = 0;
    if (!findDevice(&vid, &pid)) {
        printf("[openDevice] findDevice failed.\n");
        return false;
    }

    CFMutableDictionaryRef matchingDict = IOServiceMatching(getUSBDeviceClassName());
    SInt32 v32 = vid, p32 = pid;
    CFDictionarySetValue(matchingDict, CFSTR(kUSBVendorID), CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v32));
    CFDictionarySetValue(matchingDict, CFSTR(kUSBProductID), CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &p32));

    io_service_t deviceService = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict);
    if (!deviceService) {
        printf("[openDevice] IOServiceGetMatchingService returned NULL for VID 0x%04X, PID 0x%04X\n", vid, pid);
        return false;
    }

    IOCFPlugInInterface** plugIn = nullptr;
    SInt32 score = 0;
    IOReturn kr = IOCreatePlugInInterfaceForService(
        deviceService, kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugIn, &score);

    if (mHotplugPort) {
        IOServiceAddInterestNotification(
            mHotplugPort, deviceService, kIOGeneralInterest,
            &IOUSBLibTransport::interestCallbackTrampoline, this, &mInterestNotifier);
    }

    IOObjectRelease(deviceService);
    if (kr != kIOReturnSuccess || !plugIn) {
        printf("[openDevice] IOCreatePlugInInterfaceForService failed: 0x%08x\n", kr);
        return false;
    }

    kr = (*plugIn)->QueryInterface(
        plugIn, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID*)&mDevice);
    (*plugIn)->Release(plugIn);

    if (kr != kIOReturnSuccess || !mDevice) {
        printf("[openDevice] QueryInterface ID942 failed: 0x%08x\n", kr);
        return false;
    }

    kr = (*mDevice)->USBDeviceOpenSeize(mDevice);
    if (kr != kIOReturnSuccess) {
        printf("[openDevice] USBDeviceOpenSeize failed: 0x%08x. Trying USBDeviceOpen...\n", kr);
        kr = (*mDevice)->USBDeviceOpen(mDevice);
        if (kr != kIOReturnSuccess) {
            printf("[openDevice] USBDeviceOpen failed: 0x%08x\n", kr);
            (*mDevice)->Release(mDevice);
            mDevice = nullptr;
            return false;
        }
    }

    kr = (*mDevice)->SetConfiguration(mDevice, 1);
    if (kr != kIOReturnSuccess) {
        printf("[openDevice] SetConfiguration failed: 0x%08x\n", kr);
    }

    if (!openInterfaces()) {
        printf("[openDevice] openInterfaces failed.\n");
        closeDevice();
        return false;
    }

    claimPipes();

    mDeviceOpen.store(true);
    mMidiBridge.start();
    if (mAvailHandler) mAvailHandler(true);
    RLOG("[openDevice] Successfully opened Rane USB Device!");
    return true;
}

bool IOUSBLibTransport::openInterfaces() {
    IOUSBFindInterfaceRequest request = {
        .bInterfaceClass    = kIOUSBFindInterfaceDontCare,
        .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting  = kIOUSBFindInterfaceDontCare
    };

    io_iterator_t iter = IO_OBJECT_NULL;
    IOReturn kr = (*mDevice)->CreateInterfaceIterator(mDevice, &request, &iter);
    if (kr != kIOReturnSuccess) {
        RLOG("[openInterfaces] CreateInterfaceIterator failed: 0x%08x", kr);
        return false;
    }

    io_service_t intfService = IO_OBJECT_NULL;
    mNumIntf = 0;

    while ((intfService = IOIteratorNext(iter)) != IO_OBJECT_NULL && mNumIntf < kMaxInterfaces) {
        IOCFPlugInInterface** plugIn = nullptr;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(
            intfService, kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugIn, &score);
        IOObjectRelease(intfService);

        if (kr == kIOReturnSuccess && plugIn) {
            IOUSBInterfaceInterface942** intf = nullptr;
            kr = (*plugIn)->QueryInterface(
                plugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID942), (LPVOID*)&intf);
            (*plugIn)->Release(plugIn);

            if (kr == kIOReturnSuccess && intf) {
                kr = (*intf)->USBInterfaceOpen(intf);
                RLOG("[openInterfaces] Interface %d open kr: 0x%08x", mNumIntf, kr);

                // Set Alternate Setting 1 for audio streaming interfaces (Interface 1 and 2)
                UInt8 intfNum = 0;
                (*intf)->GetInterfaceNumber(intf, &intfNum);
                if (intfNum == 1 || intfNum == 2) {
                    IOReturn altKr = (*intf)->SetAlternateInterface(intf, 1);
                    RLOG("[openInterfaces] Interface %d SetAlternateInterface(1) kr: 0x%08x", intfNum, altKr);
                }

                UInt8 numPipes = 0;
                (*intf)->GetNumEndpoints(intf, &numPipes);
                RLOG("[openInterfaces] Interface %d has %d pipes:", mNumIntf, numPipes);
                for (UInt8 ref = 1; ref <= numPipes; ref++) {
                    UInt8 direction = 0, number = 0, transferType = 0, interval = 0;
                    UInt16 maxPacketSize = 0;
                    (*intf)->GetPipeProperties(intf, ref, &direction, &number, &transferType, &maxPacketSize, &interval);
                    uint8_t addr = (direction << 7) | number;
                    RLOG("   Pipe %d: EP 0x%02X (Dir: %d, Num: %d, Type: %d, MaxPkt: %d)",
                         ref, addr, direction, number, transferType, maxPacketSize);
                }

                mIntf[mNumIntf] = intf;
                mNumIntf++;
            }
        }
    }
    IOObjectRelease(iter);
    return (mNumIntf > 0);
}

bool IOUSBLibTransport::setupHIDBridge() {
    if (mHIDManager) teardownHIDBridge();

    mHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
    if (!mHIDManager) {
        RLOG("[setupHIDBridge] Failed to create IOHIDManager.");
        return false;
    }

    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int vid = (mCurrentVID != 0) ? mCurrentVID : RANE_VENDOR_ID_1;
    int pid = (mCurrentPID != 0) ? mCurrentPID : RANE_PID_SIXTY_EIGHT_HW;
    CFNumberRef vidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef pidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vidNum);
    CFDictionarySetValue(dict, CFSTR(kIOHIDProductIDKey), pidNum);
    CFRelease(vidNum);
    CFRelease(pidNum);

    IOHIDManagerSetDeviceMatching(mHIDManager, dict);
    CFRelease(dict);

    IOReturn kr = IOHIDManagerOpen(mHIDManager, kIOHIDOptionsTypeNone);
    RLOG("[setupHIDBridge] IOHIDManagerOpen kr: 0x%08x", kr);

    CFSetRef deviceSet = IOHIDManagerCopyDevices(mHIDManager);
    if (!deviceSet || CFSetGetCount(deviceSet) == 0) {
        RLOG("[setupHIDBridge] No matching IOHIDDevice found.");
        if (deviceSet) CFRelease(deviceSet);
        return false;
    }

    CFIndex count = CFSetGetCount(deviceSet);
    IOHIDDeviceRef devices[8];
    CFSetGetValues(deviceSet, (const void**)devices);

    for (CFIndex i = 0; i < count; i++) {
        IOReturn dkr = IOHIDDeviceOpen(devices[i], kIOHIDOptionsTypeNone);
        if (dkr == kIOReturnSuccess) {
            mHIDDevice = devices[i];
            IOHIDDeviceRegisterInputReportCallback(
                mHIDDevice, mHIDReportBuf, sizeof(mHIDReportBuf),
                &IOUSBLibTransport::hidInputReportCallbackTrampoline, this);
            IOHIDManagerScheduleWithRunLoop(mHIDManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
            RLOG("[setupHIDBridge] Successfully attached IOHIDDevice for Rane MIDI/HID interface!");
            break;
        }
    }

    CFRelease(deviceSet);
    return (mHIDDevice != nullptr);
}

void IOUSBLibTransport::teardownHIDBridge() {
    if (mHIDDevice) {
        IOHIDDeviceClose(mHIDDevice, kIOHIDOptionsTypeNone);
        mHIDDevice = nullptr;
    }
    if (mHIDManager) {
        IOHIDManagerUnscheduleFromRunLoop(mHIDManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        IOHIDManagerClose(mHIDManager, kIOHIDOptionsTypeNone);
        CFRelease(mHIDManager);
        mHIDManager = nullptr;
    }
}

void IOUSBLibTransport::hidInputReportCallbackTrampoline(void* context, IOReturn result, void* sender, IOHIDReportType type, uint32_t reportID, uint8_t* report, CFIndex reportLength) {
    (void)result; (void)sender; (void)type; (void)reportID;
    auto* self = static_cast<IOUSBLibTransport*>(context);
    if (self) self->onHIDInputReport(report, reportLength);
}

void IOUSBLibTransport::onHIDInputReport(uint8_t* report, CFIndex length) {
    if (report && length > 0) {
        mMidiBridge.feedMidiIn(report, (size_t)length);
    }
}

bool IOUSBLibTransport::sendMidiSysEx(const uint8_t *sysexData, size_t length) {
    if (mHIDDevice) {
        uint8_t pkt[64] = {0};
        pkt[0] = 0x04;
        size_t copyLen = (length < 63) ? length : 63;
        memcpy(&pkt[1], sysexData, copyLen);
        IOReturn kr = IOHIDDeviceSetReport(mHIDDevice, kIOHIDReportTypeOutput, 0, pkt, (CFIndex)(copyLen + 1));
        RLOG("[sendMidiSysEx] IOHIDDeviceSetReport %zu bytes kr: 0x%08x", copyLen, kr);
        return (kr == kIOReturnSuccess);
    }
    return false;
}

bool IOUSBLibTransport::sendHardwareHandshake() {
    RLOG("Sending Rane Sixty-Eight hardware handshake sequence via IOHIDDeviceSetReport...");

    if (!mHIDDevice) {
        setupHIDBridge();
    }

    if (mHIDDevice) {
        // 1. Set Control Point to USB Port 1: F0 17 52 01 F7
        uint8_t pkt1[8] = { 0x04, 0xF0, 0x17, 0x52, 0x07, 0x01, 0xF7, 0x00 };
        IOReturn kr1 = IOHIDDeviceSetReport(mHIDDevice, kIOHIDReportTypeOutput, 0, pkt1, sizeof(pkt1));
        RLOG("[Handshake] Set Control Point (USB 1) kr: 0x%08x", kr1);

        usleep(20000);

        // 2. Get All Controls / Unmute Hardware: F0 17 04 F7
        uint8_t pkt2[8] = { 0x04, 0xF0, 0x17, 0x04, 0x05, 0xF7, 0x00, 0x00 };
        IOReturn kr2 = IOHIDDeviceSetReport(mHIDDevice, kIOHIDReportTypeOutput, 0, pkt2, sizeof(pkt2));
        RLOG("[Handshake] Get All Controls / Hardware Unmute kr: 0x%08x", kr2);

        usleep(20000);

        // 3. Repeat Set Control Point for USB 1
        IOHIDDeviceSetReport(mHIDDevice, kIOHIDReportTypeOutput, 0, pkt1, sizeof(pkt1));
        RLOG("Rane Sixty-Eight hardware handshake completed successfully!");
        return true;
    }

    RLOG("[Handshake] WARNING: mHIDDevice not active, handshake deferred.");
    return false;
}

bool IOUSBLibTransport::claimPipes() {
    mOutPipeIntf = nullptr;
    mInPipeIntf = nullptr;
    mMidiInPipeIntf = nullptr;
    mMidiOutPipeIntf = nullptr;

    for (uint32_t i = 0; i < mNumIntf; i++) {
        if (!mIntf[i]) continue;
        if (!mOutPipeIntf && findPipeRef(mIntf[i], RANE_EP_PCM_OUT, &mOutPipeRef)) {
            mOutPipeIntf = mIntf[i];
        }
        if (!mInPipeIntf && findPipeRef(mIntf[i], RANE_EP_PCM_IN, &mInPipeRef)) {
            mInPipeIntf = mIntf[i];
        }
        if (!mMidiInPipeIntf && findPipeRef(mIntf[i], RANE_EP_MIDI_IN, &mMidiInPipeRef)) {
            mMidiInPipeIntf = mIntf[i];
        }
        if (!mMidiOutPipeIntf && findPipeRef(mIntf[i], RANE_EP_MIDI_OUT, &mMidiOutPipeRef)) {
            mMidiOutPipeIntf = mIntf[i];
        }
    }

    if (mOutPipeIntf) {
        UInt8 direction = 0, number = 0, transferType = 0, interval = 0;
        UInt16 maxPkt = 0;
        (*mOutPipeIntf)->GetPipeProperties(mOutPipeIntf, mOutPipeRef, &direction, &number, &transferType, &maxPkt, &interval);
        if (maxPkt > 0) mOutMaxPkt = maxPkt;
    }
    if (mInPipeIntf) {
        UInt8 direction = 0, number = 0, transferType = 0, interval = 0;
        UInt16 maxPkt = 0;
        (*mInPipeIntf)->GetPipeProperties(mInPipeIntf, mInPipeRef, &direction, &number, &transferType, &maxPkt, &interval);
        if (maxPkt > 0) mInMaxPkt = maxPkt;
    }

    RLOG("[claimPipes] mOutPipeIntf: %p (Ref %d, EP 0x%02X, MaxPkt %d), mInPipeIntf: %p (Ref %d, EP 0x%02X, MaxPkt %d)",
         mOutPipeIntf, mOutPipeRef, RANE_EP_PCM_OUT, mOutMaxPkt, mInPipeIntf, mInPipeRef, RANE_EP_PCM_IN, mInMaxPkt);

    return (mOutPipeIntf != nullptr);
}

bool IOUSBLibTransport::findPipeRef(IOUSBInterfaceInterface942** intf, uint8_t epAddr, uint8_t* outRef) {
    UInt8 numPipes = 0;
    (*intf)->GetNumEndpoints(intf, &numPipes);

    for (UInt8 ref = 1; ref <= numPipes; ref++) {
        UInt8 direction = 0, number = 0, transferType = 0, interval = 0;
        UInt16 maxPacketSize = 0;
        (*intf)->GetPipeProperties(intf, ref, &direction, &number, &transferType, &maxPacketSize, &interval);

        uint8_t addr = (direction << 7) | number;
        if (addr == epAddr) {
            if (outRef) *outRef = ref;
            return true;
        }
    }
    return false;
}

void IOUSBLibTransport::closeDevice() {
    stopStreaming();
    teardownHIDBridge();
    mMidiBridge.stop();
    teardownInterfaces();

    if (mInterestNotifier) {
        IOObjectRelease(mInterestNotifier);
        mInterestNotifier = 0;
    }

    if (mDevice) {
        (*mDevice)->USBDeviceClose(mDevice);
        (*mDevice)->Release(mDevice);
        mDevice = nullptr;
    }
    mDeviceOpen.store(false);
    if (mAvailHandler) mAvailHandler(false);
}

void IOUSBLibTransport::teardownInterfaces() {
    for (uint32_t i = 0; i < mNumIntf; i++) {
        if (mIntf[i]) {
            (*mIntf[i])->USBInterfaceClose(mIntf[i]);
            (*mIntf[i])->Release(mIntf[i]);
            mIntf[i] = nullptr;
        }
        mIntfSrc[i] = nullptr;
    }
    mNumIntf = 0;
}

bool IOUSBLibTransport::controlRequest(uint8_t requestType, uint8_t request,
                                       uint16_t value, uint16_t index,
                                       void *data, uint16_t length) {
    if (!mDevice) return false;
    IOUSBDevRequest req = {
        .bmRequestType = requestType,
        .bRequest      = request,
        .wValue        = value,
        .wIndex        = index,
        .wLength       = length,
        .pData         = data,
        .wLenDone      = 0
    };
    IOReturn kr = (*mDevice)->DeviceRequest(mDevice, &req);
    RLOG("[controlRequest] type:0x%02X req:0x%02X val:0x%04X idx:0x%04X len:%d -> kr:0x%08x",
         requestType, request, value, index, length, kr);
    return (kr == kIOReturnSuccess);
}

bool IOUSBLibTransport::setSampleRate(uint32_t rate) {
    mSampleRate = rate;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    double nsPerTick = (double)tb.numer / (double)tb.denom;
    mHostTicksPerFrame = 1e9 / (nsPerTick * (double)mSampleRate);
    return true;
}

bool IOUSBLibTransport::startStreaming() {
    if (mRunning.load()) return true;
    if (!mDeviceOpen.load() && !openDevice()) return false;

    mAnchorHostTime.store(mach_absolute_time(), std::memory_order_release);
    mClockSeed.fetch_add(1, std::memory_order_relaxed);
    
    mInRing.reset();
    mOutRing.reset();
    mOutPrerolled.store(false);

    mFeedbackHead.store(0, std::memory_order_relaxed);
    mFeedbackTail.store(0, std::memory_order_relaxed);

    mFbBalance.store(0);
    mXferErrLogCount.store(0);

    for (uint32_t i = 0; i < kDoubleBuffer; i++) {
        mOutSlotInFlight[i].store(false, std::memory_order_release);
        mInSlotInFlight[i].store(false, std::memory_order_release);
    }
    for (uint32_t i = 0; i < kMidiInSlots; i++) {
        mMidiSlotInFlight[i].store(false, std::memory_order_release);
    }

    mShutdown.store(false);
    mRunning.store(true);

    pthread_create(&mWorker, nullptr, &IOUSBLibTransport::workerEntry, this);
    while (!mWorkerReady.load()) usleep(1000);

    UInt64 busFrame = 0;
    AbsoluteTime atTime;
    if (mOutPipeIntf) {
        (*mOutPipeIntf)->GetBusFrameNumber(mOutPipeIntf, &busFrame, &atTime);
    }
    mNextOutFrame.store(busFrame + 10);
    mNextInFrame.store(busFrame + 10);
    RLOG("startStreaming: Initial bus frame = %llu, starting at %llu", busFrame, busFrame + 10);

    for (uint32_t i = 0; i < kDoubleBuffer; i++) {
        submitIn(i);
        submitOut(i);
    }
    for (uint32_t i = 0; i < kMidiInSlots; i++) {
        submitMidiIn(i);
    }
    return true;
}

void IOUSBLibTransport::stopStreaming() {
    if (!mRunning.load()) return;
    mRunning.store(false);

    /* Abort all pipes BEFORE stopping the worker runloop so cancelled transfers drain cleanly */
    if (mOutPipeIntf && mOutPipeRef) {
        (*mOutPipeIntf)->AbortPipe(mOutPipeIntf, mOutPipeRef);
    }
    if (mInPipeIntf && mInPipeRef) {
        (*mInPipeIntf)->AbortPipe(mInPipeIntf, mInPipeRef);
    }
    if (mMidiInPipeIntf && mMidiInPipeRef) {
        (*mMidiInPipeIntf)->AbortPipe(mMidiInPipeIntf, mMidiInPipeRef);
    }

    shutdownWorker();

    for (uint32_t i = 0; i < kDoubleBuffer; i++) {
        mOutSlotInFlight[i].store(false, std::memory_order_release);
        mInSlotInFlight[i].store(false, std::memory_order_release);
    }
    for (uint32_t i = 0; i < kMidiInSlots; i++) {
        mMidiSlotInFlight[i].store(false, std::memory_order_release);
    }

    mOutPrerolled.store(false, std::memory_order_release);
    mOutRing.reset();
    mInRing.reset();
    mFeedbackHead.store(0, std::memory_order_relaxed);
    mFeedbackTail.store(0, std::memory_order_relaxed);
}

void* IOUSBLibTransport::workerEntry(void* arg) {
    static_cast<IOUSBLibTransport*>(arg)->workerLoop();
    return nullptr;
}

void IOUSBLibTransport::workerLoop() {
    mWorkerLoop = CFRunLoopGetCurrent();
    for (uint32_t i = 0; i < mNumIntf; i++) {
        if (mIntf[i]) {
            CFRunLoopSourceRef src = nullptr;
            IOReturn kr = (*mIntf[i])->CreateInterfaceAsyncEventSource(mIntf[i], &src);
            if (kr == kIOReturnSuccess && src) {
                CFRunLoopAddSource(mWorkerLoop, src, kCFRunLoopDefaultMode);
                mIntfSrc[i] = src;
            }
        }
    }

    mWorkerReady.store(true);
    while (!mShutdown.load()) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    }

    for (uint32_t i = 0; i < mNumIntf; i++) {
        if (mIntfSrc[i]) {
            CFRunLoopRemoveSource(mWorkerLoop, mIntfSrc[i], kCFRunLoopDefaultMode);
            CFRelease(mIntfSrc[i]);
            mIntfSrc[i] = nullptr;
        }
    }
}

void IOUSBLibTransport::shutdownWorker() {
    mShutdown.store(true);
    if (mWorkerLoop) CFRunLoopStop(mWorkerLoop);
    if (mWorker) {
        pthread_join(mWorker, nullptr);
        mWorker = 0;
    }
    mWorkerReady.store(false);
}

static inline float rane_clamp_float(float v) {
    if (v > 1.0f) return 1.0f;
    if (v < -1.0f) return -1.0f;
    return v;
}



static UInt64 rane_schedule_frame(std::atomic<UInt64>& next, IOUSBInterfaceInterface942** intf, bool force) {
    UInt64 bus = 0;
    AbsoluteTime t;
    (*intf)->GetBusFrameNumber(intf, &bus, &t);
    UInt64 f = next.load();
    if (force || f <= bus || f > bus + 32) {
        f = bus + 4;
    }
    next.store(f + 1);
    return f;
}

bool IOUSBLibTransport::submitOut(uint32_t slot) {
    if (!mRunning.load() || !mOutPipeIntf || slot >= kDoubleBuffer) return false;

    if (mOutSlotInFlight[slot].exchange(true, std::memory_order_acq_rel)) {
        return false;
    }

    uint32_t hostFrames = mHostPeriodFrames.load(std::memory_order_relaxed);
    if (hostFrames == 0) hostFrames = 512;

    /* USB Isochronous Audio OUT: Driven by Implicit Feedback from EP 0x82 IN.
     * The Rane Sixty-Eight DAC consumes frames at the mixer hardware's crystal clock rate.
     * Each microframe OUT transmits the exact frame count clocked by the mixer on IN. */
    size_t fTail = mFeedbackTail.load(std::memory_order_acquire);
    size_t fHead = mFeedbackHead.load(std::memory_order_relaxed);
    if (fTail > fHead + 32) {
        fHead = fTail - 16;
    }

    uint32_t counts[kUFramesPerXfer];
    uint32_t totalFrames = 0;
    for (uint32_t i = 0; i < kUFramesPerXfer; i++) {
        uint32_t c = kNominalFramesPerUF;
        if (fHead < fTail) {
            c = mFeedbackFifo[fHead % kFeedbackFifoCap];
            fHead++;
        }
        if (c < 5 || c > 7) c = kNominalFramesPerUF;
        counts[i] = c;
        totalFrames += c;
    }
    mFeedbackHead.store(fHead, std::memory_order_release);

    float floatFrames[kUFramesPerXfer * kMaxFramesPerUF * kOutChannels];
    size_t wantBytes = (size_t)totalFrames * kOutChannels * sizeof(float);

    /* Dynamic pre-roll watermark: cushion based on host period (at least 2 host cycles) */
    uint32_t watermarkFrames = std::max((uint32_t)256, hostFrames * 2);
    if (watermarkFrames > 2048) watermarkFrames = 2048;
    size_t watermarkBytes = (size_t)watermarkFrames * kOutChannels * sizeof(float);

    if (!mOutPrerolled.load(std::memory_order_relaxed)) {
        size_t avail = mOutRing.availableRead();
        if (avail < watermarkBytes) {
            memset(floatFrames, 0, wantBytes);
        } else {
            mOutPrerolled.store(true, std::memory_order_release);
            RLOG("OUT buffer watermark reached (%zu bytes / %u frames). Playback started.",
                 avail, (uint32_t)(avail / (kOutChannels * sizeof(float))));
            size_t poppedBytes = mOutRing.pop((uint8_t*)floatFrames, wantBytes);
            if (poppedBytes < wantBytes) {
                memset((uint8_t*)floatFrames + poppedBytes, 0, wantBytes - poppedBytes);
            }
        }
    } else {
        /* Bounded Latency & Drift Correction:
         * Keep buffer occupancy tightly locked to the target cushion (at most 2x watermark).
         * If host clock is slightly faster than mixer crystal or if USB transfers were delayed,
         * prune the excess oldest frames so latency never builds up! */
        size_t maxAllowedBytes = watermarkBytes * 2;
        size_t curAvail = mOutRing.availableRead();
        if (curAvail > maxAllowedBytes + wantBytes) {
            size_t excessBytes = curAvail - maxAllowedBytes;
            size_t frameBytes = kOutChannels * sizeof(float);
            excessBytes = (excessBytes / frameBytes) * frameBytes;
            if (excessBytes > 0) {
                mOutRing.pop(nullptr, excessBytes);
            }
        }

        size_t poppedBytes = mOutRing.pop((uint8_t*)floatFrames, wantBytes);
        if (poppedBytes < wantBytes) {
            if (mXferErrLogCount.fetch_add(1, std::memory_order_relaxed) < 100) {
                RLOG("OUT underrun! want: %zu, got: %zu. Re-buffering...", wantBytes, poppedBytes);
            }
            memset((uint8_t*)floatFrames + poppedBytes, 0, wantBytes - poppedBytes);
            mOutPrerolled.store(false, std::memory_order_release);
        }
    }

    if (mXferErrLogCount.fetch_add(1) % 1000 == 0) {
        RLOG("OUT submit: totalFrames=%u avail=%zu prerolled=%d",
             totalFrames, mOutRing.availableRead(), (int)mOutPrerolled.load());
    }

    float* dstFloat = (float*)mOutBuf[slot];
    for (uint32_t f = 0; f < totalFrames; f++) {
        const float* src = &floatFrames[f * kOutChannels];
        for (uint32_t w = 0; w < kWireOutCh; w++) {
            *dstFloat++ = rane_clamp_float(src[w]);
        }
    }

    for (uint32_t i = 0; i < kUFramesPerXfer; i++) {
        mOutIsochFrames[slot][i].frReqCount = (UInt16)(counts[i] * kWireOutFrameBytes);
        mOutIsochFrames[slot][i].frActCount = 0;
        mOutIsochFrames[slot][i].frStatus   = 0;
    }

    IOReturn kr = kIOReturnError;
    UInt64 frameStart = 0;
    for (int attempt = 0; attempt < 2; attempt++) {
        frameStart = rane_schedule_frame(mNextOutFrame, mOutPipeIntf, attempt > 0);
        kr = (*mOutPipeIntf)->WriteIsochPipeAsync(
            mOutPipeIntf, mOutPipeRef, mOutBuf[slot], frameStart, kUFramesPerXfer,
            mOutIsochFrames[slot],
            &IOUSBLibTransport::outCompletionTrampoline, &mOutCtx[slot]);
        if (kr != kIOReturnIsoTooNew && kr != kIOReturnIsoTooOld) break;
    }

    if (kr != kIOReturnSuccess) {
        mOutSlotInFlight[slot].store(false, std::memory_order_release);
        if (mXferErrLogCount.fetch_add(1) < 50) {
            RLOG("WriteIsochPipeAsync slot %d frame %llu failed: 0x%08x", slot, frameStart, kr);
        }
        return false;
    }

    return true;
}

bool IOUSBLibTransport::submitIn(uint32_t slot) {
    if (!mRunning.load() || !mInPipeIntf || slot >= kDoubleBuffer) return false;

    if (mInSlotInFlight[slot].exchange(true, std::memory_order_acq_rel)) {
        return false;
    }

    UInt16 req = (UInt16)((mInMaxPkt > 0 && mInMaxPkt <= kMaxUFrameBytes) ? mInMaxPkt
                                                                           : kMaxFramesPerUF * kWireInFrameBytes);
    for (uint32_t i = 0; i < kUFramesPerXfer; i++) {
        mInIsochFrames[slot][i].frReqCount = req;
        mInIsochFrames[slot][i].frActCount = 0;
        mInIsochFrames[slot][i].frStatus   = 0;
    }

    IOReturn kr = kIOReturnError;
    UInt64 frameStart = 0;
    for (int attempt = 0; attempt < 2; attempt++) {
        frameStart = rane_schedule_frame(mNextInFrame, mInPipeIntf, attempt > 0);
        kr = (*mInPipeIntf)->ReadIsochPipeAsync(
            mInPipeIntf, mInPipeRef, mInBuf[slot], frameStart, kUFramesPerXfer,
            mInIsochFrames[slot],
            &IOUSBLibTransport::inCompletionTrampoline, &mInCtx[slot]);
        if (kr != kIOReturnIsoTooNew && kr != kIOReturnIsoTooOld) break;
    }

    if (kr != kIOReturnSuccess) {
        mInSlotInFlight[slot].store(false, std::memory_order_release);
        if (mXferErrLogCount.fetch_add(1) < 50) {
            RLOG("ReadIsochPipeAsync slot %d frame %llu failed: 0x%08x", slot, frameStart, kr);
        }
        return false;
    }

    return true;
}

bool IOUSBLibTransport::submitMidiIn(uint32_t slot) {
    if (!mRunning.load() || !mMidiInPipeIntf || slot >= kMidiInSlots) return false;

    if (mMidiSlotInFlight[slot].exchange(true, std::memory_order_acq_rel)) {
        return false;
    }

    IOReturn kr = (*mMidiInPipeIntf)->ReadPipeAsync(
        mMidiInPipeIntf, mMidiInPipeRef, mMidiInBuf[slot], kMidiInBufSize,
        &IOUSBLibTransport::midiInCompletionTrampoline, &mMidiInCtx[slot]);

    if (kr != kIOReturnSuccess) {
        mMidiSlotInFlight[slot].store(false, std::memory_order_release);
        return false;
    }

    return true;
}

void IOUSBLibTransport::outCompletionTrampoline(void* refcon, IOReturn result, void* arg0) {
    auto* ctx = static_cast<CompletionCtx*>(refcon);
    ctx->self->onOutComplete(ctx->slot, result, (uint32_t)(uintptr_t)arg0);
}

void IOUSBLibTransport::inCompletionTrampoline(void* refcon, IOReturn result, void* arg0) {
    auto* ctx = static_cast<CompletionCtx*>(refcon);
    ctx->self->onInComplete(ctx->slot, result, (uint32_t)(uintptr_t)arg0);
}

void IOUSBLibTransport::midiInCompletionTrampoline(void* refcon, IOReturn result, void* arg0) {
    auto* ctx = static_cast<CompletionCtx*>(refcon);
    ctx->self->onMidiInComplete(ctx->slot, result, (uint32_t)(uintptr_t)arg0);
}

void IOUSBLibTransport::onOutComplete(uint32_t slot, IOReturn result, uint32_t bytes) {
    (void)bytes;
    if (slot < kDoubleBuffer) {
        mOutSlotInFlight[slot].store(false, std::memory_order_release);
    }
    if (result == kIOReturnAborted) {
        return;
    }

    static uint32_t sLogCount = 0;
    if (sLogCount++ % 200 == 0) {
        char statusStr[256] = {0};
        int pos = 0;
        for (uint32_t i = 0; i < kUFramesPerXfer; i++) {
            pos += snprintf(statusStr + pos, sizeof(statusStr) - pos,
                            "[%u:act=%u,st=0x%x] ", i,
                            mOutIsochFrames[slot][i].frActCount,
                            mOutIsochFrames[slot][i].frStatus);
        }
        RLOG("OUT status: res=0x%08x %{public}s", result, statusStr);
    }
    if (result != kIOReturnSuccess && result != kIOReturnUnderrun) {
        if (mXferErrLogCount.fetch_add(1) < 50) {
            RLOG("onOutComplete slot %d error: 0x%08x", slot, result);
        }
        if (result == kIOReturnIsoTooOld || result == kIOReturnIsoTooNew) {
            UInt64 busFrame = 0;
            AbsoluteTime atTime;
            if (mOutPipeIntf) (*mOutPipeIntf)->GetBusFrameNumber(mOutPipeIntf, &busFrame, &atTime);
            mNextOutFrame.store(busFrame + 4);
        }
    }
    if (mRunning.load()) {
        submitOut(slot);
    }
}

void IOUSBLibTransport::onInComplete(uint32_t slot, IOReturn result, uint32_t bytes) {
    (void)bytes;
    if (slot < kDoubleBuffer) {
        mInSlotInFlight[slot].store(false, std::memory_order_release);
    }
    if (result == kIOReturnAborted) {
        return;
    }
    if (result != kIOReturnSuccess && result != kIOReturnUnderrun) {
        if (mXferErrLogCount.fetch_add(1) < 50) {
            RLOG("onInComplete slot %d error: 0x%08x", slot, result);
        }
        if (result == kIOReturnIsoTooOld || result == kIOReturnIsoTooNew) {
            UInt64 busFrame = 0;
            AbsoluteTime atTime;
            if (mInPipeIntf) (*mInPipeIntf)->GetBusFrameNumber(mInPipeIntf, &busFrame, &atTime);
            mNextInFrame.store(busFrame + 4);
        }
        if (mRunning.load()) {
            submitIn(slot);
        }
        return;
    }
    if (!mRunning.load()) return;

    UInt16 stride = (UInt16)((mInMaxPkt > 0 && mInMaxPkt <= kMaxUFrameBytes) ? mInMaxPkt
                                                                              : kMaxFramesPerUF * kWireInFrameBytes);
    float floatFrames[kUFramesPerXfer * kMaxFramesPerUF * kInChannels];
    uint32_t nFrames = 0;
    for (uint32_t i = 0; i < kUFramesPerXfer; i++) {
        const IOUSBIsocFrame& fr = mInIsochFrames[slot][i];
        if (fr.frStatus != kIOReturnSuccess && fr.frStatus != kIOReturnUnderrun) continue;
        uint32_t act = fr.frActCount;
        if (act > stride) act = stride;
        uint32_t cnt = act / kWireInFrameBytes;
        if (cnt == 0) continue;
        if (cnt > kMaxFramesPerUF) cnt = kMaxFramesPerUF;

        // Push frame count into implicit feedback FIFO for EP 0x06 OUT
        size_t t = mFeedbackTail.load(std::memory_order_relaxed);
        size_t h = mFeedbackHead.load(std::memory_order_relaxed);
        if (t - h < kFeedbackFifoCap) {
            mFeedbackFifo[t % kFeedbackFifoCap] = (uint8_t)cnt;
            mFeedbackTail.store(t + 1, std::memory_order_release);
        }

        const float* srcFloat = (const float*)(mInBuf[slot] + (size_t)i * stride);
        for (uint32_t k = 0; k < cnt; k++) {
            float* dst = &floatFrames[nFrames * kInChannels];
            for (uint32_t w = 0; w < kInChannels; w++) {
                dst[w] = srcFloat[w];
            }
            srcFloat += kWireInCh;
            nFrames++;
        }
    }

    if (nFrames > 0) {
        mInRing.push((const uint8_t*)floatFrames, (size_t)nFrames * kInChannels * sizeof(float));
    }
    submitIn(slot);
}

void IOUSBLibTransport::onMidiInComplete(uint32_t slot, IOReturn result, uint32_t bytes) {
    if (slot < kMidiInSlots) {
        mMidiSlotInFlight[slot].store(false, std::memory_order_release);
    }
    if (result == kIOReturnAborted) {
        return;
    }
    if (mRunning.load() && result == kIOReturnSuccess && bytes > 0) {
        mMidiBridge.feedMidiIn(mMidiInBuf[slot], bytes);
        submitMidiIn(slot);
    }
}

void IOUSBLibTransport::readInput(uint64_t sampleTime, uint32_t frames, float *dstFloatIn) {
    (void)sampleTime;
    size_t reqBytes = frames * sizeof(float) * kInChannels;
    size_t readBytes = mInRing.pop((uint8_t*)dstFloatIn, reqBytes);
    if (readBytes < reqBytes) {
        memset((uint8_t*)dstFloatIn + readBytes, 0, reqBytes - readBytes);
    }
}

void IOUSBLibTransport::writeOutput(uint64_t sampleTime, uint32_t frames, const float *srcFloatOut) {
    (void)sampleTime;
    if (frames > 0 && srcFloatOut) {
        mHostPeriodFrames.store(frames, std::memory_order_relaxed);
        size_t writeBytes = frames * sizeof(float) * kOutChannels;
        size_t availWrite = mOutRing.availableWrite();
        if (availWrite < writeBytes) {
            /* Emergency safety: drop oldest unplayed frames rather than truncating incoming buffer */
            size_t needDrop = writeBytes - availWrite;
            size_t frameBytes = kOutChannels * sizeof(float);
            needDrop = ((needDrop + frameBytes - 1) / frameBytes) * frameBytes;
            mOutRing.pop(nullptr, needDrop);
        }
        mOutRing.push((const uint8_t*)srcFloatOut, writeBytes);
    }
}

void IOUSBLibTransport::onBufferFrameSizeChanged(uint32_t newSize) {
    mHostPeriodFrames.store(newSize, std::memory_order_relaxed);
}

void IOUSBLibTransport::getZeroTimeStamp(double *outSampleTime, uint64_t *outHostTime, uint64_t *outSeed) {
    uint64_t now = mach_absolute_time();
    uint64_t anchorHT = mAnchorHostTime.load(std::memory_order_relaxed);
    if (anchorHT == 0) {
        anchorHT = now;
        mAnchorHostTime.store(anchorHT, std::memory_order_relaxed);
    }

    if (mHostTicksPerFrame <= 0.0) {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        double nsPerTick = (double)tb.numer / (double)tb.denom;
        mHostTicksPerFrame = 1e9 / (nsPerTick * (double)mSampleRate);
    }

    uint64_t elapsedHostTicks = (now > anchorHT) ? (now - anchorHT) : 0;

    /* Must match kAudioDevicePropertyZeroTimeStampPeriod in RaneHALPlugin.cpp */
    static constexpr double kZeroTSPeriodFrames = 16384.0;
    const double elapsedFrames = (double)elapsedHostTicks / mHostTicksPerFrame;
    const double zeroFrame = std::floor(elapsedFrames / kZeroTSPeriodFrames) * kZeroTSPeriodFrames;
    const uint64_t zeroHostTime = anchorHT + (uint64_t)(zeroFrame * mHostTicksPerFrame);

    if (outSampleTime) *outSampleTime = zeroFrame;
    if (outHostTime)   *outHostTime   = zeroHostTime;
    if (outSeed)       *outSeed       = mClockSeed.load(std::memory_order_relaxed);
}

void IOUSBLibTransport::matchedCallbackTrampoline(void* refCon, io_iterator_t iter) {
    auto* self = static_cast<IOUSBLibTransport*>(refCon);
    io_service_t service = IO_OBJECT_NULL;
    bool found = false;
    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        found = true;
        IOObjectRelease(service);
    }
    if (found) {
        RLOG("[Hotplug] Rane USB Device connected / powered ON!");
        if (!self->isOpen()) {
            self->openDevice();
        }
    }
}

void IOUSBLibTransport::interestCallbackTrampoline(void* refCon, io_service_t service, uint32_t messageType, void* messageArgument) {
    (void)service; (void)messageArgument;
    auto* self = static_cast<IOUSBLibTransport*>(refCon);
    if (messageType == kIOMessageServiceIsTerminated) {
        RLOG("[Hotplug] Rane USB Device powered OFF / disconnected!");
        if (self && self->isOpen()) {
            self->closeDevice();
        }
    }
}

void IOUSBLibTransport::terminatedCallbackTrampoline(void* refCon, io_iterator_t iter) {
    auto* self = static_cast<IOUSBLibTransport*>(refCon);
    io_service_t service = IO_OBJECT_NULL;
    bool terminated = false;
    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        terminated = true;
        IOObjectRelease(service);
    }
    if (terminated) {
        RLOG("[Hotplug] Rane USB Device disconnected / powered OFF!");
        if (self && self->isOpen()) {
            self->closeDevice();
        }
    }
}

void IOUSBLibTransport::setupHotplugNotification() {
    mHotplugPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!mHotplugPort) return;

    IONotificationPortSetDispatchQueue(mHotplugPort, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    SInt32 v32 = (mCurrentVID != 0) ? mCurrentVID : RANE_VENDOR_ID_1;

    // 1. Match Notification (USB Device Connected / Turned ON)
    CFMutableDictionaryRef matchDict = IOServiceMatching(getUSBDeviceClassName());
    CFDictionarySetValue(matchDict, CFSTR(kUSBVendorID), CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v32));

    IOReturn kr1 = IOServiceAddMatchingNotification(
        mHotplugPort, kIOFirstMatchNotification, matchDict,
        &IOUSBLibTransport::matchedCallbackTrampoline, this, &mMatchedIter);

    if (kr1 == kIOReturnSuccess && mMatchedIter) {
        matchedCallbackTrampoline(this, mMatchedIter);
    }

    // 2. Terminate Notification (USB Device Disconnected / Turned OFF)
    CFMutableDictionaryRef termDict = IOServiceMatching(getUSBDeviceClassName());
    CFDictionarySetValue(termDict, CFSTR(kUSBVendorID), CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v32));

    IOReturn kr2 = IOServiceAddMatchingNotification(
        mHotplugPort, kIOTerminatedNotification, termDict,
        &IOUSBLibTransport::terminatedCallbackTrampoline, this, &mTerminatedIter);

    if (kr2 == kIOReturnSuccess && mTerminatedIter) {
        terminatedCallbackTrampoline(this, mTerminatedIter);
    }
}

void IOUSBLibTransport::teardownHotplugNotification() {
    if (mMatchedIter) {
        IOObjectRelease(mMatchedIter);
        mMatchedIter = IO_OBJECT_NULL;
    }
    if (mTerminatedIter) {
        IOObjectRelease(mTerminatedIter);
        mTerminatedIter = IO_OBJECT_NULL;
    }
    if (mHotplugPort) {
        IONotificationPortDestroy(mHotplugPort);
        mHotplugPort = nullptr;
    }
}

