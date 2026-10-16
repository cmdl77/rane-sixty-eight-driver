/* SPDX-License-Identifier: MIT */
/* RaneLinkBridge.cpp - Native Ableton Link C Wrapper */

#include "RaneLinkBridge.h"
#include <abl_link.h>
#include <mutex>

namespace {
    struct abl_link gLink = { nullptr };
    abl_link_session_state gSessionState = { nullptr };
    bool gInitialized = false;
    std::mutex gMutex;

    RaneLinkPeersCallback gPeersCallback = nullptr;
    RaneLinkTempoCallback gTempoCallback = nullptr;

    void internal_peers_cb(uint64_t peers, void * /*ctx*/) {
        RaneLinkPeersCallback cb = nullptr;
        {
            std::lock_guard<std::mutex> lock(gMutex);
            cb = gPeersCallback;
        }
        if (cb) {
            cb(peers);
        }
    }

    void internal_tempo_cb(double bpm, void * /*ctx*/) {
        RaneLinkTempoCallback cb = nullptr;
        {
            std::lock_guard<std::mutex> lock(gMutex);
            cb = gTempoCallback;
        }
        if (cb) {
            cb(bpm);
        }
    }
}

extern "C" {

bool rane_link_init(double initial_bpm) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (gInitialized) {
        return true;
    }
    gLink = abl_link_create(initial_bpm);
    gSessionState = abl_link_create_session_state();
    abl_link_set_num_peers_callback(gLink, internal_peers_cb, nullptr);
    abl_link_set_tempo_callback(gLink, internal_tempo_cb, nullptr);
    gInitialized = true;
    return true;
}

void rane_link_enable(bool enable) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return;
    abl_link_enable(gLink, enable);
}

bool rane_link_is_enabled(void) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return false;
    return abl_link_is_enabled(gLink);
}

uint64_t rane_link_get_num_peers(void) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return 0;
    return abl_link_num_peers(gLink);
}

double rane_link_get_tempo(void) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return 120.0;
    abl_link_capture_app_session_state(gLink, gSessionState);
    return abl_link_tempo(gSessionState);
}

void rane_link_set_tempo(double bpm) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return;
    abl_link_capture_app_session_state(gLink, gSessionState);
    int64_t now_micros = abl_link_clock_micros(gLink);
    abl_link_set_tempo(gSessionState, bpm, now_micros);
    abl_link_commit_app_session_state(gLink, gSessionState);
}

void rane_link_set_callbacks(RaneLinkPeersCallback peers_cb, RaneLinkTempoCallback tempo_cb) {
    std::lock_guard<std::mutex> lock(gMutex);
    gPeersCallback = peers_cb;
    gTempoCallback = tempo_cb;
}

void rane_link_destroy(void) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gInitialized) return;
    abl_link_enable(gLink, false);
    abl_link_destroy_session_state(gSessionState);
    abl_link_destroy(gLink);
    gInitialized = false;
}

} // extern "C"
