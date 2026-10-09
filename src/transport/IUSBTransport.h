/* SPDX-License-Identifier: MIT */
/* IUSBTransport.h - Abstract USB transport interface for Rane mixers. */
#ifndef RANE_IUSB_TRANSPORT_H
#define RANE_IUSB_TRANSPORT_H

#include <stdint.h>
#include <stddef.h>
#include <functional>

class IUSBTransport {
public:
    using AudioCallback = std::function<void(const uint8_t *data, size_t len)>;
    using AvailabilityHandler = std::function<void(bool available)>;

    virtual ~IUSBTransport() = default;

    virtual void setAvailabilityHandler(AvailabilityHandler handler) = 0;

    virtual bool findDevice(uint16_t *outVid, uint16_t *outPid) = 0;
    virtual bool openDevice() = 0;
    virtual void closeDevice() = 0;
    virtual bool isOpen() const = 0;

    virtual bool controlRequest(uint8_t requestType, uint8_t request,
                                uint16_t value, uint16_t index,
                                void *data, uint16_t length) = 0;

    virtual bool startStreaming() = 0;
    virtual void stopStreaming() = 0;

    virtual void readInput(uint64_t sampleTime, uint32_t frames, float *dstFloat16Ch) = 0;
    virtual void writeOutput(uint64_t sampleTime, uint32_t frames, const float *srcFloat16Ch) = 0;

    virtual void getZeroTimeStamp(double *outSampleTime, uint64_t *outHostTime, uint64_t *outSeed) = 0;

    virtual bool setSampleRate(uint32_t rate) = 0;
    virtual uint32_t currentSampleRate() const = 0;
    virtual uint16_t currentPID() const = 0;
    virtual void onBufferFrameSizeChanged(uint32_t newSize) {}
};

#endif /* RANE_IUSB_TRANSPORT_H */
