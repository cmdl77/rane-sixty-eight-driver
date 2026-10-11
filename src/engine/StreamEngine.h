/* SPDX-License-Identifier: MIT */
/* StreamEngine.h - High-level audio stream engine for Rane driver. */
#ifndef RANE_STREAM_ENGINE_H
#define RANE_STREAM_ENGINE_H

#include "../transport/IUSBTransport.h"
#include <atomic>
#include <memory>

class StreamEngine {
public:
    static StreamEngine& shared();

    StreamEngine();
    ~StreamEngine();

    bool init(IUSBTransport *transport = nullptr);
    bool start();
    void stop();
    bool isRunning() const { return mRunning.load(); }

    void readInput(uint64_t sampleTime, uint32_t frames, float *dstFloatIn);
    void writeOutput(uint64_t sampleTime, uint32_t frames, const float *srcFloatOut);

    void getZeroTimeStamp(double *outSampleTime, uint64_t *outHostTime, uint64_t *outSeed);

    bool setSampleRate(uint32_t rate);
    uint32_t currentSampleRate() const;
    void onBufferFrameSizeChanged(uint32_t newSize) {
        if (mTransport) mTransport->onBufferFrameSizeChanged(newSize);
    }

private:
    IUSBTransport*    mTransport = nullptr;
    std::atomic<bool> mRunning{false};
    uint32_t          mSampleRate = 48000;
};

#endif /* RANE_STREAM_ENGINE_H */
