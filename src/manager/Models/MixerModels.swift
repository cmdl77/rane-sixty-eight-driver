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
    let inputBadge: NSTextField
    let phonoPopup: NSPopUpButton
    let resonanceSegment: NSSegmentedControl
    let recordSegment: NSSegmentedControl
}

struct LedTestItem {
    let name: String
    let note: UInt8
    let color: String
    let channel: UInt8
    let isMixerControl: Bool
}
