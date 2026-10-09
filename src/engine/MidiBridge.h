/* SPDX-License-Identifier: MIT */
/* MidiBridge.h - Non-blocking Unix domain socket IPC for Rane MIDI. */
#ifndef RANE_MIDI_BRIDGE_H
#define RANE_MIDI_BRIDGE_H

#include "RaneRing.h"
#include <atomic>
#include <pthread.h>
#include <stdint.h>

class MidiBridge {
public:
    static constexpr size_t kMidiRingCapacity = 4096;

    MidiBridge();
    ~MidiBridge();

    bool start();
    void stop();

    void feedMidiIn(const uint8_t *data, size_t len);
    bool getMidiOutByte(uint8_t *outByte);

private:
    void ensureConnected();
    void closeSocket();

    static void* socketReadEntry(void* arg);
    void socketReadLoop();

    std::atomic<int>   mSock{-1};
    std::atomic<bool>  mStopped{true};
    pthread_t          mReadThread = 0;
    pthread_mutex_t    mConnectMutex = PTHREAD_MUTEX_INITIALIZER;
    RaneRing           mMidiOutRing;
};

#endif /* RANE_MIDI_BRIDGE_H */
