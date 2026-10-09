/* SPDX-License-Identifier: MIT */
/* RaneRing.h - Lock-free SPSC ring buffer for CoreAudio Float32 streams. */
#ifndef RANE_RING_H
#define RANE_RING_H

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <algorithm>

class RaneRing {
public:
    RaneRing() = default;
    ~RaneRing() {
        if (mBuffer) std::free(mBuffer);
    }

    RaneRing(const RaneRing&) = delete;
    RaneRing& operator=(const RaneRing&) = delete;

    bool init(size_t capacityBytes) {
        /* Round up to power of 2 */
        size_t cap = 1;
        while (cap < capacityBytes) cap <<= 1;

        mBuffer = (uint8_t*)std::malloc(cap);
        if (!mBuffer) return false;
        std::memset(mBuffer, 0, cap);

        mCapacity = cap;
        mMask = cap - 1;
        mHead.store(0, std::memory_order_relaxed);
        mTail.store(0, std::memory_order_relaxed);
        return true;
    }

    size_t availableWrite() const {
        size_t head = mHead.load(std::memory_order_acquire);
        size_t tail = mTail.load(std::memory_order_relaxed);
        return mCapacity - (tail - head);
    }

    size_t availableRead() const {
        size_t head = mHead.load(std::memory_order_relaxed);
        size_t tail = mTail.load(std::memory_order_acquire);
        return tail - head;
    }

    static constexpr size_t kFrameBytes = 16 * sizeof(float); /* 64 bytes: 1 audio frame of 16 float channels */

    size_t push(const uint8_t* src, size_t bytes) {
        size_t avail = availableWrite();
        size_t toWrite = std::min(bytes, avail);
        toWrite = (toWrite / kFrameBytes) * kFrameBytes;
        if (toWrite == 0) return 0;

        size_t tail = mTail.load(std::memory_order_relaxed);
        size_t offset = tail & mMask;
        size_t firstChunk = std::min(toWrite, mCapacity - offset);
        size_t secondChunk = toWrite - firstChunk;

        std::memcpy(mBuffer + offset, src, firstChunk);
        if (secondChunk > 0) {
            std::memcpy(mBuffer, src + firstChunk, secondChunk);
        }

        mTail.store(tail + toWrite, std::memory_order_release);
        return toWrite;
    }

    size_t pop(uint8_t* dst, size_t bytes) {
        size_t avail = availableRead();
        size_t toRead = std::min(bytes, avail);
        toRead = (toRead / kFrameBytes) * kFrameBytes;
        if (toRead == 0) return 0;

        size_t head = mHead.load(std::memory_order_relaxed);
        size_t offset = head & mMask;
        size_t firstChunk = std::min(toRead, mCapacity - offset);
        size_t secondChunk = toRead - firstChunk;

        if (dst) {
            std::memcpy(dst, mBuffer + offset, firstChunk);
            if (secondChunk > 0) {
                std::memcpy(dst + firstChunk, mBuffer, secondChunk);
            }
        }

        mHead.store(head + toRead, std::memory_order_release);
        return toRead;
    }

    void reset() {
        mHead.store(0, std::memory_order_relaxed);
        mTail.store(0, std::memory_order_relaxed);
    }

private:
    uint8_t*            mBuffer   = nullptr;
    size_t              mCapacity = 0;
    size_t              mMask     = 0;
    alignas(64) std::atomic<size_t> mHead{0};
    alignas(64) std::atomic<size_t> mTail{0};
};

#endif /* RANE_RING_H */
