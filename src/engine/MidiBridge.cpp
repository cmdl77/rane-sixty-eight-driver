/* SPDX-License-Identifier: MIT */
/* MidiBridge.cpp - Bidirectional Unix socket client inside Rane HAL plugin. */

#include "MidiBridge.h"
#include <errno.h>
#include <fcntl.h>
#include <os/log.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[RaneHAL/MIDI] " fmt, ##__VA_ARGS__)

static const char* kSocketPath = "/tmp/org.openrane.sixtyeight.midi";

MidiBridge::MidiBridge() {
    mMidiOutRing.init(kMidiRingCapacity);
}

MidiBridge::~MidiBridge() {
    stop();
}

bool MidiBridge::start() {
    mStopped.store(false);
    return true;
}

void MidiBridge::stop() {
    mStopped.store(true);
    closeSocket();
    if (mReadThread) {
        pthread_join(mReadThread, nullptr);
        mReadThread = 0;
    }
}

void MidiBridge::closeSocket() {
    int fd = mSock.exchange(-1);
    if (fd >= 0) close(fd);
}

void* MidiBridge::socketReadEntry(void* arg) {
    static_cast<MidiBridge*>(arg)->socketReadLoop();
    return nullptr;
}

void MidiBridge::socketReadLoop() {
    uint8_t buf[256];
    while (!mStopped.load()) {
        int fd = mSock.load();
        if (fd < 0) {
            usleep(50000);
            continue;
        }
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n > 0) {
            mMidiOutRing.push(buf, (size_t)n);
        } else if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                usleep(5000);
                continue;
            }
            RLOG("Socket read ended or failed: %s", (n < 0 ? strerror(errno) : "EOF"));
            closeSocket();
        }
    }
}

void MidiBridge::ensureConnected() {
    if (mSock.load() >= 0 || mStopped.load()) return;

    pthread_mutex_lock(&mConnectMutex);
    if (mSock.load() < 0 && !mStopped.load()) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd >= 0) {
            int set = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &set, sizeof(set));

            struct sockaddr_un addr = {};
            addr.sun_family = AF_UNIX;
            std::strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);

            int r = connect(fd, (struct sockaddr*)&addr, sizeof(addr));
            if (r == 0) {
                mSock.store(fd);
                RLOG("connected to Rane MIDI agent at %s", kSocketPath);

                if (!mReadThread) {
                    pthread_create(&mReadThread, nullptr, &MidiBridge::socketReadEntry, this);
                }
            } else {
                close(fd);
            }
        }
    }
    pthread_mutex_unlock(&mConnectMutex);
}

void MidiBridge::feedMidiIn(const uint8_t *data, size_t len) {
    if (mStopped.load() || len == 0) return;
    ensureConnected();
    int fd = mSock.load();
    if (fd < 0) return;

    ssize_t n = send(fd, data, len, 0);
    if (n < 0) {
        RLOG("send() failed: %s - closing socket", strerror(errno));
        closeSocket();
    }
}

bool MidiBridge::getMidiOutByte(uint8_t *outByte) {
    if (mMidiOutRing.availableRead() > 0) {
        return mMidiOutRing.pop(outByte, 1) == 1;
    }
    return false;
}
