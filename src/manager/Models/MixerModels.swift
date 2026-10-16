/* SPDX-License-Identifier: MIT */
/* MixerModels.swift - Data models and structures for Rane Sixty-Eight */

import Cocoa

struct PendingControlChange {
    let targetValue: UInt8
    let timestamp: TimeInterval
}

struct PgmChannelControls {
    let channelNumber: Int
    let container: NSView
    let inputTypeBadge: NSTextField   // Feld 1: LINE (CD) / PHONO / S/PDIF (CC 112..115)
    let sourceBadge: NSTextField      // Feld 2: PH/CD / USB / AUX (CC 116..119)
    let phonoPopup: NSPopUpButton
    let resonanceSegment: NSSegmentedControl
    let recordSegment: NSSegmentedControl
    let crossfaderBadge: NSTextField  // Feld 3: Crossfader A / POST / B (CC 120..123)
}

struct LedTestItem {
    let name: String
    let note: UInt8
    let color: String
    let channel: UInt8
    let isMixerControl: Bool
}

/// Official Rane Sixty-Eight SysEx & Protocol Constants (verified against ARM LPC2468 firmware)
enum RaneProtocol {
    static let manufacturerId: UInt8 = 0x17
    static let sysExStart: UInt8 = 0xF0
    static let sysExEnd: UInt8 = 0xF7

    enum Opcode {
        static let deviceIdQuery: UInt8 = 0x01
        static let getSetParams: UInt8 = 0x02
        static let getAllControls: UInt8 = 0x04
        static let bulkLedMatrix: UInt8 = 0x09
        static let dspFxParams: UInt8 = 0x18
        static let securityUnlock: UInt8 = 0x18
        static let audioUnmute: UInt8 = 0x52
        static let setControlPoint: UInt8 = 0x52
        static let audioMute: UInt8 = 0x53
        static let seratoBpmSync: UInt8 = 0x53
        static let fxStateReport: UInt8 = 0x54
        static let heartbeat: UInt8 = 0x55
        static let bootloaderEnter: UInt8 = 0x7C
        static let bootloaderExit: UInt8 = 0x7D
    }

    /// Verified 7-byte LPC2468 ROM Security Key (at Flash offset 0x000185B3)
    static let romUnlockKey: [UInt8] = [0x02, 0x43, 0x88, 0x38, 0x03, 0x6A, 0x01]

    enum Port {
        static let usbPortA: UInt8 = 0x00
        static let usbPortB: UInt8 = 0x01
    }

    enum CC {
        static let hardwareHeartbeat: UInt8 = 0x56 // CC #86
    }
}
