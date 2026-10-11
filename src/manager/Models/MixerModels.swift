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
