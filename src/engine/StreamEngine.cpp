/* SPDX-License-Identifier: MIT */
/* StreamEngine.cpp - High-level audio stream engine implementation. */

#include "StreamEngine.h"
#include "../transport/IOUSBLibTransport.h"
#include <os/log.h>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneStreamEngine] " fmt, ##__VA_ARGS__)

StreamEngine& StreamEngine::shared() {
    static StreamEngine sInstance;
    return sInstance;
}

StreamEngine::StreamEngine() {
    mTransport = &IOUSBLibTransport::shared();
}

StreamEngine::~StreamEngine() {
    stop();
}

bool StreamEngine::init(IUSBTransport *transport) {
    if (transport) mTransport = transport;
    return true;
}

bool StreamEngine::start() {
    if (mRunning.load()) return true;
    if (!mTransport) return false;

    if (mTransport->startStreaming()) {
        mRunning.store(true);
        RLOG("StreamEngine started successfully.");
        return true;
    }
    return false;
}

void StreamEngine::stop() {
    if (!mRunning.load()) return;
    mRunning.store(false);
    if (mTransport) mTransport->stopStreaming();
    RLOG("StreamEngine stopped.");
}

void StreamEngine::readInput(uint64_t sampleTime, uint32_t frames, float *dstFloat16Ch) {
    if (mTransport && mRunning.load()) {
        mTransport->readInput(sampleTime, frames, dstFloat16Ch);
    }
}

void StreamEngine::writeOutput(uint64_t sampleTime, uint32_t frames, const float *srcFloat16Ch) {
    if (mTransport && mRunning.load()) {
        mTransport->writeOutput(sampleTime, frames, srcFloat16Ch);
    }
}

void StreamEngine::getZeroTimeStamp(double *outSampleTime, uint64_t *outHostTime, uint64_t *outSeed) {
    if (mTransport) {
        mTransport->getZeroTimeStamp(outSampleTime, outHostTime, outSeed);
    }
}

bool StreamEngine::setSampleRate(uint32_t rate) {
    mSampleRate = rate;
    if (mTransport) return mTransport->setSampleRate(rate);
    return true;
}

uint32_t StreamEngine::currentSampleRate() const {
    if (mTransport) return mTransport->currentSampleRate();
    return mSampleRate;
}
