/* SPDX-License-Identifier: MIT */
/* RaneMidiLearnService.swift - Interactive MIDI Learn Manager for FlexFX and Mixer controls */

import Foundation
import CoreMIDI

public enum FlexFxMidiTarget: String, CaseIterable, Codable {
    case fxFilter    = "FX_FILTER"
    case fxFlanger   = "FX_FLANGER"
    case fxPhaser    = "FX_PHASER"
    case fxEcho      = "FX_ECHO"
    case fxRobot     = "FX_ROBOT"
    case fxReverb    = "FX_REVERB"
    case fxToggle    = "FX_TOGGLE"      // FlexFX On/Off
    case prevBeat    = "PREV_BEAT"      // Beat division <
    case nextBeat    = "NEXT_BEAT"      // Beat division >
    case dryWet      = "DRY_WET"        // Dry/Wet knob or slider
    case depth       = "DEPTH"          // Depth knob or slider
    case prePost     = "PRE_POST"       // Pre/Post Fader toggle
    case modulePower = "MODULE_POWER"   // Module master power

    public var displayName: String {
        switch self {
        case .fxFilter:     return "Filter"
        case .fxFlanger:    return "Flanger"
        case .fxPhaser:     return "Phaser"
        case .fxEcho:       return "Echo"
        case .fxRobot:      return "Robot"
        case .fxReverb:     return "Reverb"
        case .fxToggle:     return "FlexFX On/Off"
        case .prevBeat:     return "Beat <"
        case .nextBeat:     return "Beat >"
        case .dryWet:       return "Dry / Wet"
        case .depth:        return "Depth (Feedback)"
        case .prePost:      return "Pre / Post"
        case .modulePower:  return "Modul Power"
        }
    }
}

public enum MidiMessageType: String, Codable {
    case note = "NOTE"
    case cc   = "CC"
}

public enum ControlInteractionType: String, Codable, CaseIterable {
    case button = "Button"
    case faderKnob = "Fader / Knob"
    case encoder = "Encoder (Relative)"
}

public enum ButtonMode: String, Codable, CaseIterable {
    case toggle = "Toggle"
    case hold = "Hold"
    case trigger = "Trigger"
}

public struct MidiMapping: Codable, Equatable {
    public var type: MidiMessageType
    public var number: UInt8   // Note number (0-127) or CC number (0-127)
    public var channel: UInt8  // 0-15 (or 255 for any channel)
    public var interactionType: ControlInteractionType
    public var buttonMode: ButtonMode

    public init(type: MidiMessageType, number: UInt8, channel: UInt8 = 255, interactionType: ControlInteractionType? = nil, buttonMode: ButtonMode = .toggle) {
        self.type = type
        self.number = number
        self.channel = channel
        self.buttonMode = buttonMode
        if let it = interactionType {
            self.interactionType = it
        } else {
            // Default interaction based on type
            self.interactionType = (type == .note) ? .button : .faderKnob
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MidiMessageType.self, forKey: .type)
        self.number = try container.decode(UInt8.self, forKey: .number)
        self.channel = try container.decode(UInt8.self, forKey: .channel)
        self.interactionType = try container.decodeIfPresent(ControlInteractionType.self, forKey: .interactionType) ?? ((self.type == .note) ? .button : .faderKnob)
        self.buttonMode = try container.decodeIfPresent(ButtonMode.self, forKey: .buttonMode) ?? .toggle
    }

    public var summary: String {
        let chStr = (channel == 255) ? "All Ch" : "Ch \(channel + 1)"
        if type == .note {
            return "\(chStr) • Note \(number)"
        } else {
            return "\(chStr) • CC #\(number)"
        }
    }
}

public struct MidiFilterRule: Codable, Equatable {
    public let id: String
    public let type: MidiMessageType // .note or .cc
    public let number: UInt8         // 0..127
    public let channel: UInt8        // 0..15 or 255 (All)
    public let label: String         // e.g. "Mixer Fader PGM 1"

    public init(id: String = UUID().uuidString, type: MidiMessageType, number: UInt8, channel: UInt8 = 255, label: String = "") {
        self.id = id
        self.type = type
        self.number = number
        self.channel = channel
        self.label = label
    }

    public var summary: String {
        let chStr = (channel == 255) ? "All Ch" : "Ch \(channel + 1)"
        let tStr = (type == .note) ? "Note" : "CC #"
        let desc = label.isEmpty ? "" : " (\(label))"
        return "\(chStr) • \(tStr)\(number)\(desc)"
    }
}

public class RaneMidiLearnService {
    public static let shared = RaneMidiLearnService()

    private let userDefaultsKey = "RaneSixtyEight_MidiLearnMappings_v2"
    private let filterDefaultsKey = "RaneSixtyEight_MidiFilterRules_v1"

    // Active MIDI Learn Mode state
    public var isLearnModeActive: Bool = false {
        didSet {
            if !isLearnModeActive {
                selectedTarget = nil
            }
            onLearnModeChanged?(isLearnModeActive)
        }
    }

    public var selectedTarget: FlexFxMidiTarget? = nil {
        didSet {
            onSelectedTargetChanged?(selectedTarget)
        }
    }

    // Mappings: Target -> MIDI Message
    private(set) var mappings: [FlexFxMidiTarget: MidiMapping] = [:]

    // Filtered / Blocked MIDI Rules
    private(set) var filterRules: [MidiFilterRule] = []

    // Callbacks
    public var onLearnModeChanged: ((Bool) -> Void)?
    public var onSelectedTargetChanged: ((FlexFxMidiTarget?) -> Void)?
    public var onMappingUpdated: (() -> Void)?
    public var onFilterRulesUpdated: (() -> Void)?
    public var onMidiActionTriggered: ((FlexFxMidiTarget, Float) -> Void)?

    private init() {
        loadMappings()
        loadFilterRules()
    }

    // MARK: - Persistence
    private func loadMappings() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: MidiMapping].self, from: data)
            var loaded: [FlexFxMidiTarget: MidiMapping] = [:]
            for (key, val) in decoded {
                if let target = FlexFxMidiTarget(rawValue: key) {
                    loaded[target] = val
                }
            }
            self.mappings = loaded
        } catch {
            print("Failed to load MIDI learn mappings: \(error)")
        }
    }

    private func saveMappings() {
        var dict: [String: MidiMapping] = [:]
        for (target, mapping) in mappings {
            dict[target.rawValue] = mapping
        }
        do {
            let data = try JSONEncoder().encode(dict)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to save MIDI learn mappings: \(error)")
        }
        onMappingUpdated?()
    }

    private func loadFilterRules() {
        guard let data = UserDefaults.standard.data(forKey: filterDefaultsKey) else {
            // Provide sensible defaults: Sixty-Eight faders often send CC 112..127 or CC 33..37
            return
        }
        do {
            let rules = try JSONDecoder().decode([MidiFilterRule].self, from: data)
            self.filterRules = rules
        } catch {
            print("Failed to load MIDI filter rules: \(error)")
        }
    }

    private func saveFilterRules() {
        do {
            let data = try JSONEncoder().encode(filterRules)
            UserDefaults.standard.set(data, forKey: filterDefaultsKey)
        } catch {
            print("Failed to save MIDI filter rules: \(error)")
        }
        onFilterRulesUpdated?()
    }

    public func addFilterRule(_ rule: MidiFilterRule) {
        // Prevent exact duplicates
        if !filterRules.contains(where: { $0.type == rule.type && $0.number == rule.number && $0.channel == rule.channel }) {
            filterRules.append(rule)
            saveFilterRules()
        }
    }

    public func removeFilterRule(id: String) {
        filterRules.removeAll { $0.id == id }
        saveFilterRules()
    }

    public func clearAllFilterRules() {
        filterRules.removeAll()
        saveFilterRules()
    }

    /// Checks if an incoming MIDI message is blacklisted by any filter rule
    public func isMessageFiltered(type: MidiMessageType, number: UInt8, channel: UInt8) -> Bool {
        for rule in filterRules {
            if rule.type == type && rule.number == number {
                if rule.channel == 255 || rule.channel == channel {
                    return true
                }
            }
        }
        return false
    }

    public func mappingFor(target: FlexFxMidiTarget) -> MidiMapping? {
        return mappings[target]
    }

    public func clearMapping(for target: FlexFxMidiTarget) {
        mappings.removeValue(forKey: target)
        saveMappings()
    }

    public func setMapping(for target: FlexFxMidiTarget, mapping: MidiMapping) {
        // Remove any target that had this same mapping to avoid conflict
        for (t, m) in mappings where m.type == mapping.type && m.number == mapping.number && m.channel == mapping.channel {
            mappings.removeValue(forKey: t)
        }
        mappings[target] = mapping
        saveMappings()
    }

    public func clearAllMappings() {
        mappings.removeAll()
        saveMappings()
    }

    // MARK: - Incoming MIDI Event Handling
    /// Processes incoming Note or CC. Returns true if consumed/handled.
    @discardableResult
    public func handleIncomingMidi(status: UInt8, d1: UInt8, d2: UInt8) -> Bool {
        let channel = status & 0x0F
        let typeNibble = status & 0xF0

        let msgType: MidiMessageType
        let isNoteMessage = (typeNibble == 0x90 || typeNibble == 0x80)
        if isNoteMessage {
            msgType = .note
        } else if typeNibble == 0xB0 {
            msgType = .cc
        } else {
            return false
        }

        // 0. Filter Check: If blacklisted by filter rules, ignore completely!
        if isMessageFiltered(type: msgType, number: d1, channel: channel) {
            return false
        }

        // In Learn Mode: ignore Note Off or velocity 0 so we only learn on initial button press (Note On)
        if isLearnModeActive && typeNibble == 0x90 && d2 == 0 {
            return false
        }
        if isLearnModeActive && typeNibble == 0x80 {
            return false
        }

        // 1. In Learn Mode: map currently selected target to this incoming message
        if isLearnModeActive {
            if let target = selectedTarget {
                let newMapping = MidiMapping(type: msgType, number: d1, channel: channel)
                // Remove any existing target that used this exact message to avoid conflicts
                for (t, m) in mappings where m == newMapping {
                    mappings.removeValue(forKey: t)
                }
                mappings[target] = newMapping
                saveMappings()
                // Auto-advance or keep selected
                DispatchQueue.main.async { [weak self] in
                    self?.selectedTarget = nil
                }
                return true
            }
            return false
        }

        // 2. Normal Mode: check if message matches any mapped target
        var handled = false
        for (target, mapping) in mappings {
            if mapping.type == msgType && mapping.number == d1 {
                // If channel is specified, verify match
                if mapping.channel != 255 && mapping.channel != channel {
                    continue
                }

                handled = true
                let normVal = Float(d2) / 127.0
                let iType = mapping.interactionType
                let bMode = mapping.buttonMode
                DispatchQueue.main.async { [weak self] in
                    self?.executeTargetAction(target: target, rawValue: d2, normValue: normVal, interactionType: iType, buttonMode: bMode)
                }
            }
        }
        return handled
    }

    private func executeTargetAction(target: FlexFxMidiTarget, rawValue: UInt8, normValue: Float, interactionType: ControlInteractionType, buttonMode: ButtonMode = .toggle) {
        let flex = RaneFlexFxService.shared
        flex.isSuppressingHardwareLeds = true
        defer { flex.isSuppressingHardwareLeds = false }

        // Encoder relative step calculation (65 / 1 = +1, 63 / 127 = -1)
        let isRelativeIncrement = (rawValue == 1 || rawValue == 65)
        let isRelativeDecrement = (rawValue == 127 || rawValue == 63)
        let isPressed = (rawValue > 0)

        switch target {
        case .fxFilter:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .filter }
            } else {
                flex.currentEffect = .filter
            }
        case .fxFlanger:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .flanger }
            } else {
                flex.currentEffect = .flanger
            }
        case .fxPhaser:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .phaser }
            } else {
                flex.currentEffect = .phaser
            }
        case .fxEcho:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .echo }
            } else {
                flex.currentEffect = .echo
            }
        case .fxRobot:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .robot }
            } else {
                flex.currentEffect = .robot
            }
        case .fxReverb:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .reverb }
            } else {
                flex.currentEffect = .reverb
            }
        case .fxToggle:
            if interactionType == .button {
                switch buttonMode {
                case .toggle:
                    if isPressed { flex.isEnabled.toggle() }
                case .hold:
                    flex.isEnabled = isPressed
                case .trigger:
                    if isPressed { flex.isEnabled = true }
                }
            } else {
                flex.isEnabled = (normValue > 0.5)
            }
        case .prevBeat:
            if isPressed { flex.cycleBeatDivision(forward: false) }
        case .nextBeat:
            if isPressed { flex.cycleBeatDivision(forward: true) }
        case .dryWet:
            if interactionType == .encoder {
                let step = isRelativeIncrement ? 0.02 : (isRelativeDecrement ? -0.02 : (normValue > 0.5 ? 0.02 : -0.02))
                flex.dryWet = max(0.0, min(1.0, flex.dryWet + Double(step)))
            } else {
                flex.dryWet = Double(normValue)
            }
        case .depth:
            if interactionType == .encoder {
                let step = isRelativeIncrement ? 0.02 : (isRelativeDecrement ? -0.02 : (normValue > 0.5 ? 0.02 : -0.02))
                flex.depth = max(0.0, min(1.0, flex.depth + Double(step)))
            } else {
                flex.depth = Double(normValue)
            }
        case .prePost:
            if interactionType == .button {
                switch buttonMode {
                case .toggle:
                    if isPressed { flex.isPreFader.toggle() }
                case .hold:
                    flex.isPreFader = isPressed
                case .trigger:
                    if isPressed { flex.isPreFader = true }
                }
            } else {
                flex.isPreFader = (normValue > 0.5)
            }
        case .modulePower:
            if interactionType == .button {
                switch buttonMode {
                case .toggle:
                    if isPressed { flex.isModuleEnabled.toggle() }
                case .hold:
                    flex.isModuleEnabled = isPressed
                case .trigger:
                    if isPressed { flex.isModuleEnabled = true }
                }
            } else {
                flex.isModuleEnabled = (normValue > 0.5)
            }
        }

        onMidiActionTriggered?(target, normValue)
    }
}
