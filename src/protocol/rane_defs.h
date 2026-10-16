/* SPDX-License-Identifier: MIT */
/* rane_defs.h - Rane USB protocol definitions and device IDs.
 * Supports Rane Sixty-Eight, Sixty-Four, Sixty-Two, SL4.
 */
#ifndef RANE_DEFS_H
#define RANE_DEFS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* USB Vendor IDs */
#define RANE_VENDOR_ID_1          0x1CC5  /* Rane Corporation (Decimal 7365) */
#define RANE_VENDOR_ID_2          0x13E5  /* Rane Legacy VID */
#define RANE_VENDOR_ID_3          0x29E2  /* inMusic Rane */

/* Product IDs */
#define RANE_PID_SIXTY_EIGHT_HW   0x0004  /* Rane Sixty-Eight Hardware PID 4 */
#define RANE_PID_SIXTY_EIGHT_A    0x0008  /* Rane Sixty-Eight USB 1 */
#define RANE_PID_SIXTY_EIGHT_B    0x0080  /* Rane Sixty-Eight USB 2 */
#define RANE_PID_SIXTY_EIGHT_ALT  0x000E  /* Rane Sixty-Eight Alt FW */
#define RANE_PID_SIXTY_FOUR       0x0014  /* Rane Sixty-Four */
#define RANE_PID_SIXTY_TWO        0x0012  /* Rane Sixty-Two */
#define RANE_PID_SL4              0x0006  /* Rane SL4 */

/* Endpoints */
#define RANE_EP_PCM_OUT           0x06    /* Endpoint 6 OUT (Isochronous Audio OUT) */
#define RANE_EP_PCM_IN            0x82    /* Endpoint 2 IN  (0x02 | 0x80 Isochronous Audio IN) */
#define RANE_EP_MIDI_IN           0x81    /* Endpoint 1 IN  (0x01 | 0x80 MIDI IN) */
#define RANE_EP_MIDI_OUT          0x01    /* Endpoint 1 OUT (0x01 MIDI OUT) */

/* Topology */
#define RANE_CHANNELS_IN          12      /* 12 Audio Input channels (6 Stereo Pairs) */
#define RANE_CHANNELS_OUT         10      /* 10 Audio Output channels (5 Stereo Pairs) */
#define RANE_CHANNELS_TOTAL       22      /* 12 In + 10 Out */
#define RANE_CHANNELS             12      /* Max single-direction channels */
#define RANE_BYTES_PER_SAMPLE     3       /* 24-bit PCM S24_3LE */
#define RANE_OUT_FRAME_SIZE       (RANE_CHANNELS_OUT * RANE_BYTES_PER_SAMPLE) /* 30 bytes per frame */
#define RANE_IN_FRAME_SIZE        (RANE_CHANNELS_IN  * RANE_BYTES_PER_SAMPLE) /* 36 bytes per frame */
#define RANE_FRAMES_PER_PACKET    48      /* 1ms buffer at 48kHz */

/* Packet sizes */
#define RANE_OUT_PKT_SIZE         (RANE_FRAMES_PER_PACKET * RANE_OUT_FRAME_SIZE) /* 1440 bytes */
#define RANE_IN_PKT_SIZE          (RANE_FRAMES_PER_PACKET * RANE_IN_FRAME_SIZE)  /* 1728 bytes */

#define RANE_NUM_INTERFACES       2
#define RANE_ALT_SETTING_AUDIO    1

/* Rane MIDI SysEx Protocol Definitions */
#define RANE_MIDI_STATUS_SYS_EX         0xF0
#define RANE_MIDI_STATUS_NOTE_ON        0x90
#define RANE_MIDI_STATUS_NOTE_OFF       0x80
#define RANE_MIDI_STATUS_CONTROL_CHANGE 0xB0
#define RANE_MIDI_SYSEX_RANE_ID         0x17
#define RANE_MIDI_SYSEX_EOX             0xF7

/* Rane SysEx Opcodes (Firmware verified) */
#define RANE_SYSEX_OP_DEVICE_ID         0x01  /* Device Capabilities & ID (18 bytes total) */
#define RANE_SYSEX_OP_PARAMS            0x02  /* Get/Set Hardware Parameters */
#define RANE_SYSEX_OP_GET_ALL           0x04  /* Request full hardware controls dump (4 bytes: F0 17 04 F7) */
#define RANE_SYSEX_OP_BULK_LED          0x09  /* Bulk LED Matrix Set (9 payload bytes, 12 bytes total) */
#define RANE_SYSEX_OP_DSP_FX            0x18  /* Hardware Security Unlock (11 bytes: F0 17 18 02 43 88 38 03 6A 01 F7) */
#define RANE_SYSEX_OP_SECURITY_UNLOCK   0x18  /* Alias for LPC2468 ROM Magic Key Unlock */
#define RANE_SYSEX_OP_UNMUTE            0x52  /* Set Control Point (5 bytes: F0 17 52 <port> F7) */
#define RANE_SYSEX_OP_MUTE              0x53  /* Legacy alias for 0x53 */
#define RANE_SYSEX_OP_BPM_SYNC          0x53  /* Serato BPM & Asterisk Sync (14 bytes nibble-encoded) */
#define RANE_SYSEX_OP_FX_STATE          0x54  /* Hardware FlexFX State Report (12 bytes) */
#define RANE_SYSEX_OP_HEARTBEAT         0x55  /* Hardware Heartbeat ping */
#define RANE_SYSEX_OP_BOOTLOADER_ENTER  0x7C  /* Enter Bootloader mode */
#define RANE_SYSEX_OP_BOOTLOADER_EXIT   0x7D  /* Exit Bootloader mode */

/* MIDI CC Heartbeat */
#define RANE_MIDI_CC_HEARTBEAT          0x56  /* CC #86 on Channel 1 (B0 56 <counter>) */

/* USB Port Selection for Opcode 0x52 */
#define RANE_USB_PORT_A                 0x00
#define RANE_USB_PORT_B                 0x01

/* Rate Encoding helper */
static inline void rane_encode_rate(uint32_t rate, uint8_t buf[3]) {
    buf[0] = (uint8_t)(rate & 0xFF);
    buf[1] = (uint8_t)((rate >> 8) & 0xFF);
    buf[2] = (uint8_t)((rate >> 16) & 0xFF);
}

static inline uint32_t rane_decode_rate(const uint8_t buf[3]) {
    return (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) | ((uint32_t)buf[2] << 16);
}

typedef struct {
    uint16_t vid;
    uint16_t pid;
    const char *displayName;
    const char *modelUID;
    uint32_t defaultSampleRate;
    uint32_t channelsIn;
    uint32_t channelsOut;
} RaneDeviceInfo;

static inline const RaneDeviceInfo* rane_lookup_device(uint16_t vid, uint16_t pid) {
    static const RaneDeviceInfo kDevices[] = {
        { RANE_VENDOR_ID_1, RANE_PID_SIXTY_EIGHT_HW,  "Rane Sixty-Eight",         "RaneSixtyEight_Model",  48000, 12, 10 },
        { RANE_VENDOR_ID_1, RANE_PID_SIXTY_EIGHT_A,   "Rane Sixty-Eight (USB 1)", "RaneSixtyEight_Model1", 48000, 12, 10 },
        { RANE_VENDOR_ID_1, RANE_PID_SIXTY_EIGHT_B,   "Rane Sixty-Eight (USB 2)", "RaneSixtyEight_Model2", 48000, 12, 10 },
        { RANE_VENDOR_ID_2, RANE_PID_SIXTY_EIGHT_HW,  "Rane Sixty-Eight",         "RaneSixtyEight_Model",  48000, 12, 10 },
        { RANE_VENDOR_ID_2, RANE_PID_SIXTY_EIGHT_A,   "Rane Sixty-Eight (USB 1)", "RaneSixtyEight_Model1", 48000, 12, 10 },
        { RANE_VENDOR_ID_3, RANE_PID_SIXTY_EIGHT_HW,  "Rane Sixty-Eight",         "RaneSixtyEight_Model",  48000, 12, 10 },
        { RANE_VENDOR_ID_1, RANE_PID_SIXTY_FOUR,      "Rane Sixty-Four",          "RaneSixtyFour_Model",   48000, 12, 12 },
        { RANE_VENDOR_ID_1, RANE_PID_SIXTY_TWO,       "Rane Sixty-Two",           "RaneSixtyTwo_Model",    48000, 6,  6  },
        { RANE_VENDOR_ID_1, RANE_PID_SL4,             "Rane SL4",                 "RaneSL4_Model",         48000, 10, 10 },
    };
    for (size_t i = 0; i < sizeof(kDevices)/sizeof(kDevices[0]); i++) {
        if ((kDevices[i].vid == vid || vid == 0 || kDevices[i].vid == 0x1CC5 || vid == 0x1CC5) &&
            (kDevices[i].pid == pid || pid == 4 || pid == 8)) {
            return &kDevices[i];
        }
    }
    return NULL;
}

#ifdef __cplusplus
}
#endif

#endif /* RANE_DEFS_H */
