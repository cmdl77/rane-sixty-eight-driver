/* SPDX-License-Identifier: MIT */
/* IOUSBLibTransport.h - User-space IOUSBLib USB transport implementation for Rane mixers. */
#ifndef RANE_IOUSB_LIB_TRANSPORT_H
#define RANE_IOUSB_LIB_TRANSPORT_H

#include "IUSBTransport.h"
#include "../protocol/rane_defs.h"
#include "../engine/RaneRing.h"
#include "../engine/MidiBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <atomic>
#include <dispatch/dispatch.h>
#include <pthread.h>

class IOUSBLibTransport : public IUSBTransport {
public:
    static constexpr uint32_t kInChannels         = 12; /* 12 Record / Input channels (6 stereo pairs) */
    static constexpr uint32_t kOutChannels        = 10; /* 10 Playback / Output channels (5 stereo pairs) */
    static constexpr uint32_t kBytesPerFloat      = sizeof(float);
    static constexpr uint32_t kRingFrames         = 32768;
    static constexpr uint32_t kInRingBytes        = kRingFrames * kInChannels * kBytesPerFloat;
    static constexpr uint32_t kOutRingBytes       = kRingFrames * kOutChannels * kBytesPerFloat;
    static constexpr uint32_t kFramesPerXfer      = RANE_FRAMES_PER_PACKET; /* 48 */
    static constexpr uint32_t kDoubleBuffer       = 4;

    /* Real wire format (from UAC2 descriptors of the Sixty-Eight):
     *   EP 0x06 OUT: 10 ch, 4-byte subslot, 32-bit, async, wMaxPacketSize 280 (7 frames)
     *   EP 0x82 IN : 12 ch, 4-byte subslot, 32-bit, implicit feedback, wMaxPacketSize 336
     * High-speed, bInterval 1 => 8 microframes per 1 ms transfer, 6 frames nominal each. */
    static constexpr uint32_t kWireOutCh          = 10;
    static constexpr uint32_t kWireInCh           = 12;
    static constexpr uint32_t kWireSubslot        = 4;
    static constexpr uint32_t kWireOutFrameBytes  = kWireOutCh * kWireSubslot; /* 40 */
    static constexpr uint32_t kWireInFrameBytes   = kWireInCh  * kWireSubslot; /* 48 */
    static constexpr uint32_t kUFramesPerXfer     = 8;
    static constexpr uint32_t kNominalFramesPerUF = 6;
    static constexpr uint32_t kMaxFramesPerUF     = 7;
    static constexpr uint32_t kMaxUFrameBytes     = 400;  /* >= 336, stride for IN buffer */
    static constexpr uint32_t kWireBufBytes       = kUFramesPerXfer * kMaxUFrameBytes; /* 3200 */

    static IOUSBLibTransport& shared();

    IOUSBLibTransport();
    virtual ~IOUSBLibTransport();

    virtual void setAvailabilityHandler(AvailabilityHandler handler) override { mAvailHandler = handler; }

    virtual bool findDevice(uint16_t *outVid, uint16_t *outPid) override;
    virtual bool openDevice() override;
    virtual void closeDevice() override;
    virtual bool isOpen() const override { return mDeviceOpen.load(); }

    virtual bool controlRequest(uint8_t requestType, uint8_t request,
                                uint16_t value, uint16_t index,
                                void *data, uint16_t length) override;

    virtual bool startStreaming() override;
    virtual void stopStreaming() override;

    virtual void readInput(uint64_t sampleTime, uint32_t frames, float *dstFloatIn) override;
    virtual void writeOutput(uint64_t sampleTime, uint32_t frames, const float *srcFloatOut) override;

    virtual void getZeroTimeStamp(double *outSampleTime, uint64_t *outHostTime, uint64_t *outSeed) override;

    virtual bool setSampleRate(uint32_t rate) override;
    virtual uint32_t currentSampleRate() const override { return mSampleRate; }
    virtual uint16_t currentPID() const override { return mCurrentPID; }
    virtual void onBufferFrameSizeChanged(uint32_t newSize) override;
    uint16_t currentVID() const { return mCurrentVID; }

    bool ensureMonitor();

private:
    bool openInterfaces();
    bool claimPipes();
    bool findPipeRef(IOUSBInterfaceInterface942** intf, uint8_t epAddr, uint8_t* outRef);
    void teardownInterfaces();

    bool submitOut(uint32_t slot);
    bool submitIn(uint32_t slot);
    bool submitMidiIn(uint32_t slot);

    static void inCompletionTrampoline(void* refcon, IOReturn result, void* arg0);
    static void outCompletionTrampoline(void* refcon, IOReturn result, void* arg0);
    static void midiInCompletionTrampoline(void* refcon, IOReturn result, void* arg0);

    void onInComplete(uint32_t slot, IOReturn result, uint32_t bytes);
    void onOutComplete(uint32_t slot, IOReturn result, uint32_t bytes);
    void onMidiInComplete(uint32_t slot, IOReturn result, uint32_t bytes);

    static void* workerEntry(void* arg);
    void workerLoop();
    void shutdownWorker();

    static void powerCallbackTrampoline(void* refCon, io_service_t service,
                                         uint32_t messageType, void* messageArgument);
    void onPowerEvent(uint32_t messageType, void* messageArgument);
    void reopenDeviceAfterWake(bool immediate = false);

    void setupHotplugNotification();
    void teardownHotplugNotification();
    static void hotplugCallbackTrampoline(void* refCon, io_iterator_t iter);
    void onHotplug(io_iterator_t iter);
    void handleDeviceLost();

    IOUSBDeviceInterface942**     mDevice = nullptr;
    static constexpr uint32_t     kMaxInterfaces = 8;
    IOUSBInterfaceInterface942**  mIntf[kMaxInterfaces] = {};
    CFRunLoopSourceRef            mIntfSrc[kMaxInterfaces] = {};
    uint32_t                      mNumIntf = 0;

    io_connect_t                  mPowerConnect = 0;
    IONotificationPortRef         mPowerPort = nullptr;
    io_object_t                   mPowerNotifier = 0;
    std::atomic<bool>             mSuspended{false};

    IONotificationPortRef         mHotplugPort = nullptr;
    io_iterator_t                 mMatchedIter = IO_OBJECT_NULL;
    io_iterator_t                 mTerminatedIter = IO_OBJECT_NULL;
    io_object_t                   mInterestNotifier = 0;
    std::atomic<bool>             mDeviceLost{false};

    static void matchedCallbackTrampoline(void* refCon, io_iterator_t iter);
    static void terminatedCallbackTrampoline(void* refCon, io_iterator_t iter);
    static void interestCallbackTrampoline(void* refCon, io_service_t service, uint32_t messageType, void* messageArgument);

    uint8_t  mOutPipeRef = 0;
    uint8_t  mInPipeRef  = 0;
    uint8_t  mMidiInPipeRef = 0;
    uint8_t  mMidiOutPipeRef = 0;
    uint16_t mOutMaxPkt = 280;
    uint16_t mInMaxPkt  = 336;
    IOUSBInterfaceInterface942** mOutPipeIntf    = nullptr;
    IOUSBInterfaceInterface942** mInPipeIntf     = nullptr;
    IOUSBInterfaceInterface942** mMidiInPipeIntf = nullptr;
    IOUSBInterfaceInterface942** mMidiOutPipeIntf = nullptr;

    IOHIDManagerRef mHIDManager = nullptr;
    IOHIDDeviceRef  mHIDDevice  = nullptr;
    uint8_t         mHIDReportBuf[64] = {};

    bool setupHIDBridge();
    void teardownHIDBridge();
    static void hidInputReportCallbackTrampoline(void* context, IOReturn result, void* sender, IOHIDReportType type, uint32_t reportID, uint8_t* report, CFIndex reportLength);
    void onHIDInputReport(uint8_t* report, CFIndex length);

    bool sendHardwareHandshake();
    bool sendMidiSysEx(const uint8_t *sysexData, size_t length);

    uint16_t mCurrentVID = RANE_VENDOR_ID_1;
    uint16_t mCurrentPID = RANE_PID_SIXTY_EIGHT_A;

    static constexpr uint32_t kMidiInBufSize = 512;
    static constexpr uint32_t kMidiInSlots   = 4;
    MidiBridge mMidiBridge;

    uint32_t mSampleRate = 48000;

    pthread_t         mMonitorThread = 0;
    std::atomic<bool> mMonitorShutdown{false};
    static void* monitorEntry(void* arg);
    void monitorLoop();

    pthread_t         mWorker = 0;
    CFRunLoopRef      mWorkerLoop = nullptr;
    std::atomic<bool> mWorkerReady{false};
    std::atomic<bool> mShutdown{false};
    std::atomic<bool> mRunning{false};
    std::atomic<bool> mDeviceOpen{false};

    std::atomic<bool> mOutSlotInFlight[kDoubleBuffer];
    std::atomic<bool> mInSlotInFlight[kDoubleBuffer];
    std::atomic<bool> mMidiSlotInFlight[kMidiInSlots];

    uint8_t* mOutBuf[kDoubleBuffer] = {};
    uint8_t* mInBuf [kDoubleBuffer] = {};

    static constexpr uint32_t kMicroframesPerPacket = 8;
    IOUSBIsocFrame mOutIsochFrames[kDoubleBuffer][kMicroframesPerPacket] = {};
    IOUSBIsocFrame mInIsochFrames [kDoubleBuffer][kMicroframesPerPacket] = {};

    struct CompletionCtx {
        IOUSBLibTransport* self;
        uint32_t           slot;
    };
    CompletionCtx mOutCtx[kDoubleBuffer];
    CompletionCtx mInCtx [kDoubleBuffer];
    uint8_t* mMidiInBuf[kMidiInSlots] = {};
    CompletionCtx mMidiInCtx[kMidiInSlots];

    std::atomic<uint64_t> mInSampleTime{0};
    std::atomic<uint64_t> mOutSampleTime{0};
    std::atomic<UInt64>   mNextOutFrame{0};
    std::atomic<UInt64>   mNextInFrame{0};
    /* Implicit feedback FIFO (frames received on EP 0x82 IN driving EP 0x06 OUT) */
    static constexpr size_t kFeedbackFifoCap = 256;
    uint8_t               mFeedbackFifo[kFeedbackFifoCap] = {};
    std::atomic<size_t>   mFeedbackHead{0};
    std::atomic<size_t>   mFeedbackTail{0};

    std::atomic<int32_t>  mFbBalance{0};
    std::atomic<uint32_t> mXferErrLogCount{0};
    std::atomic<uint64_t> mAnchorHostTime{0};
    double                mHostTicksPerFrame = 0.0;
    std::atomic<uint64_t> mClockSeed{1};

    RaneRing mInRing;
    RaneRing mOutRing;
    std::atomic<bool>     mOutPrerolled{false};
    std::atomic<uint32_t> mHostPeriodFrames{512};

    AvailabilityHandler mAvailHandler = nullptr;
};

#endif /* RANE_IOUSB_LIB_TRANSPORT_H */
