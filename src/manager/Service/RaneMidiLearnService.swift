/* SPDX-License-Identifier: MIT */
/* RaneMidiLearnService.swift - Interactive MIDI Learn Manager for FlexFX and Mixer controls */

import Foundation
import CoreMIDI

public enum FlexFxMidiTarget: String, CaseIterable, Codable {
    case fxFilter    = "FX_FILTER"
    case fxFlanger   = "FX_FLANGER"
    case fxPhaser    = "FX_PHASER"
    case fxEcho      = "FX_ECHO"
    case fxDubDelay  = "FX_DUB_DELAY"
    case fxReverb    = "FX_REVERB"
    case fxToggle    = "FX_TOGGLE"      // FlexFX On/Off
    case prevBeat    = "PREV_BEAT"      // Beat division <
    case nextBeat    = "NEXT_BEAT"      // Beat division >
    case dryWet      = "DRY_WET"        // Dry/Wet knob or slider
    case depth       = "DEPTH"          // Depth knob or slider
    case tempo       = "TEMPO"          // Tempo (BPM) Poti
    case prePost     = "PRE_POST"       // Pre/Post Fader toggle
    case modulePower = "MODULE_POWER"   // Module master power
    case abletonLink = "ABLETON_LINK"   // Ableton Link On/Off
    case inputSelect = "INPUT_SELECT"   // Cycle Audio Input Source
    case inputFlexFx = "INPUT_FLEXFX"   // Direct Select FlexFX Send (Ch 9–10)
    case inputPgm1   = "INPUT_PGM1"     // Direct Select Deck 1 / PGM 1 (Ch 1–2)
    case inputPgm2   = "INPUT_PGM2"     // Direct Select Deck 2 / PGM 2 (Ch 3–4)
    case inputPgm3   = "INPUT_PGM3"     // Direct Select Deck 3 / PGM 3 (Ch 5–6)
    case inputPgm4   = "INPUT_PGM4"     // Direct Select Deck 4 / PGM 4 (Ch 7–8)
    case inputMainMix = "INPUT_MAIN_MIX" // Direct Select Main Mix / Mic (Ch 11–12)

    public var displayName: String {
        switch self {
        case .fxFilter:     return "Filter"
        case .fxFlanger:    return "Flanger"
        case .fxPhaser:     return "Phaser"
        case .fxEcho:       return "Echo"
        case .fxDubDelay:   return "Dub Delay"
        case .fxReverb:     return "Reverb"
        case .fxToggle:     return "FlexFX On/Off"
        case .prevBeat:     return "Beat <"
        case .nextBeat:     return "Beat >"
        case .dryWet:       return "Dry / Wet"
        case .depth:        return "Depth (Feedback)"
        case .tempo:        return "Tempo (BPM)"
        case .prePost:      return "Pre / Post"
        case .modulePower:  return "Modul Power"
        case .abletonLink:  return "Ableton Link On/Off"
        case .inputSelect:  return "Audio Eingang (Umschalten)"
        case .inputFlexFx:  return "Eingang: FlexFX Send (Ch 9–10)"
        case .inputPgm1:    return "Eingang: Deck 1 / PGM 1 (Ch 1–2)"
        case .inputPgm2:    return "Eingang: Deck 2 / PGM 2 (Ch 3–4)"
        case .inputPgm3:    return "Eingang: Deck 3 / PGM 3 (Ch 5–6)"
        case .inputPgm4:    return "Eingang: Deck 4 / PGM 4 (Ch 7–8)"
        case .inputMainMix: return "Eingang: Main Mix / Mic (Ch 11–12)"
        }
    }

    public var defaultInteractionType: ControlInteractionType {
        switch self {
        case .dryWet, .depth, .tempo:
            return .faderKnob
        default:
            return .button
        }
    }

    public init?(rawValue: String) {
        if rawValue == "FX_ROBOT" {
            self = .fxDubDelay
            return
        }
        switch rawValue {
        case "FX_FILTER": self = .fxFilter
        case "FX_FLANGER": self = .fxFlanger
        case "FX_PHASER": self = .fxPhaser
        case "FX_ECHO": self = .fxEcho
        case "FX_DUB_DELAY": self = .fxDubDelay
        case "FX_REVERB": self = .fxReverb
        case "FX_TOGGLE": self = .fxToggle
        case "PREV_BEAT": self = .prevBeat
        case "NEXT_BEAT": self = .nextBeat
        case "DRY_WET": self = .dryWet
        case "DEPTH": self = .depth
        case "TEMPO": self = .tempo
        case "PRE_POST": self = .prePost
        case "MODULE_POWER": self = .modulePower
        case "ABLETON_LINK": self = .abletonLink
        case "INPUT_SELECT": self = .inputSelect
        case "INPUT_FLEXFX": self = .inputFlexFx
        case "INPUT_PGM1": self = .inputPgm1
        case "INPUT_PGM2": self = .inputPgm2
        case "INPUT_PGM3": self = .inputPgm3
        case "INPUT_PGM4": self = .inputPgm4
        case "INPUT_MAIN_MIX": self = .inputMainMix
        default: return nil
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
    case direct = "Direct / Switch"
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

public enum LedColor: String, Codable, CaseIterable {
    case off    = "Off / Aus"
    case on     = "Standard (127)"
    case red    = "Red (Rot)"
    case green  = "Green (Grün)"
    case blue   = "Blue (Blau)"
    case amber  = "Amber (Gelb/Orange)"
    case cyan   = "Cyan (Türkis)"
    case purple = "Purple (Lila)"
    case white  = "White (Weiß)"

    public var onVelocity: UInt8 {
        switch self {
        case .off:    return 0
        case .on:     return 127
        case .red:    return 1      // Standard MIDI controller RGB palette (Traktor/Pioneer/Akai)
        case .amber:  return 5
        case .green:  return 9
        case .cyan:   return 13
        case .blue:   return 17
        case .purple: return 21
        case .white:  return 25
        }
    }

    public var offVelocity: UInt8 {
        return 0
    }
}

public struct MidiOutMapping: Codable, Equatable {
    public var type: MidiMessageType
    public var number: UInt8   // Note number (0-127) or CC number (0-127)
    public var channel: UInt8  // 0-15 (or 255 for default ch 0)
    public var onValue: UInt8  // 0..127 Velocity / CC Value
    public var offValue: UInt8 // 0..127 Velocity / CC Value

    public init(type: MidiMessageType = .note, number: UInt8 = 0, channel: UInt8 = 0, onValue: UInt8 = 127, offValue: UInt8 = 0) {
        self.type = type
        self.number = number
        self.channel = channel
        self.onValue = onValue
        self.offValue = offValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MidiMessageType.self, forKey: .type)
        self.number = try container.decode(UInt8.self, forKey: .number)
        self.channel = try container.decode(UInt8.self, forKey: .channel)

        if let onV = try container.decodeIfPresent(UInt8.self, forKey: .onValue) {
            self.onValue = onV
        } else if let onColor = try container.decodeIfPresent(LedColor.self, forKey: .onColor) {
            self.onValue = onColor.onVelocity
        } else {
            self.onValue = 127
        }

        if let offV = try container.decodeIfPresent(UInt8.self, forKey: .offValue) {
            self.offValue = offV
        } else if let offColor = try container.decodeIfPresent(LedColor.self, forKey: .offColor) {
            self.offValue = offColor.offVelocity
        } else {
            self.offValue = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, number, channel, onValue, offValue, onColor, offColor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(number, forKey: .number)
        try container.encode(channel, forKey: .channel)
        try container.encode(onValue, forKey: .onValue)
        try container.encode(offValue, forKey: .offValue)
    }

    public var summary: String {
        let chStr = (channel == 255) ? "Ch 1" : "Ch \(channel + 1)"
        let tStr = (type == .note) ? "Note" : "CC #"
        return "\(chStr) • \(tStr)\(number) [ON: \(onValue) / OFF: \(offValue)]"
    }
}

public class RaneMidiLearnService {
    public static let shared = RaneMidiLearnService()

    private let userDefaultsKey = "RaneSixtyEight_MidiLearnMappings_v2"
    private let outDefaultsKey = "RaneSixtyEight_MidiOutMappings_v1"
    private let filterDefaultsKey = "RaneSixtyEight_MidiFilterRules_v1"

    // Active MIDI Learn Mode state
    public var isLearnModeActive: Bool = false {
        didSet {
            if !isLearnModeActive {
                selectedTarget = nil
            }
            onLearnModeChanged?(isLearnModeActive)
            for obs in learnModeObservers.values {
                obs(isLearnModeActive)
            }
        }
    }

    public var selectedTarget: FlexFxMidiTarget? = nil {
        didSet {
            onSelectedTargetChanged?(selectedTarget)
            for obs in selectedTargetObservers.values {
                obs(selectedTarget)
            }
        }
    }

    // Mappings: Target -> MIDI Message (In)
    private(set) var mappings: [FlexFxMidiTarget: MidiMapping] = [:]

    // Out Mappings: Target -> MIDI Message & LED Colors (Out)
    private(set) var outMappings: [FlexFxMidiTarget: MidiOutMapping] = [:]

    // Filtered / Blocked MIDI Rules
    private(set) var filterRules: [MidiFilterRule] = []

    // Callbacks & Multicast Observers
    public var onLearnModeChanged: ((Bool) -> Void)?
    public var onSelectedTargetChanged: ((FlexFxMidiTarget?) -> Void)?
    public var onMappingUpdated: (() -> Void)?
    public var onOutMappingUpdated: (() -> Void)?
    public var onFilterRulesUpdated: (() -> Void)?
    public var onMidiActionTriggered: ((FlexFxMidiTarget, Float) -> Void)?

    private var mappingObservers: [UUID: () -> Void] = [:]
    private var outMappingObservers: [UUID: () -> Void] = [:]
    private var learnModeObservers: [UUID: (Bool) -> Void] = [:]
    private var selectedTargetObservers: [UUID: (FlexFxMidiTarget?) -> Void] = [:]
    private var filterRulesObservers: [UUID: () -> Void] = [:]
    private var midiActionObservers: [UUID: (FlexFxMidiTarget, Float) -> Void] = [:]

    @discardableResult
    public func addMappingObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        mappingObservers[id] = observer
        return id
    }
    public func removeMappingObserver(_ id: UUID) {
        mappingObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addLearnModeObserver(_ observer: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        learnModeObservers[id] = observer
        return id
    }
    public func removeLearnModeObserver(_ id: UUID) {
        learnModeObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addSelectedTargetObserver(_ observer: @escaping (FlexFxMidiTarget?) -> Void) -> UUID {
        let id = UUID()
        selectedTargetObservers[id] = observer
        return id
    }
    public func removeSelectedTargetObserver(_ id: UUID) {
        selectedTargetObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addFilterRulesObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        filterRulesObservers[id] = observer
        return id
    }
    public func removeFilterRulesObserver(_ id: UUID) {
        filterRulesObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addMidiActionObserver(_ observer: @escaping (FlexFxMidiTarget, Float) -> Void) -> UUID {
        let id = UUID()
        midiActionObservers[id] = observer
        return id
    }
    public func removeMidiActionObserver(_ id: UUID) {
        midiActionObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addOutMappingObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        outMappingObservers[id] = observer
        return id
    }
    public func removeOutMappingObserver(_ id: UUID) {
        outMappingObservers.removeValue(forKey: id)
    }

    private init() {
        loadMappings()
        loadOutMappings()
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
                    var mapping = val
                    // Sanitize: button targets should default to .button interactionType
                    if target.defaultInteractionType == .button && mapping.interactionType == .faderKnob {
                        mapping.interactionType = .button
                    }
                    loaded[target] = mapping
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
        for obs in mappingObservers.values {
            obs()
        }
    }

    private func loadOutMappings() {
        guard let data = UserDefaults.standard.data(forKey: outDefaultsKey) else {
            // Setup default Sixty-Eight hardware LEDs out-mapping for quick out-of-the-box experience
            self.outMappings = [
                .modulePower: MidiOutMapping(type: .note, number: 19, channel: 0, onValue: 127, offValue: 0),
                .fxToggle:    MidiOutMapping(type: .note, number: 0,  channel: 0, onValue: 127, offValue: 0),
                .fxFilter:    MidiOutMapping(type: .note, number: 12, channel: 0, onValue: 127, offValue: 0),
                .fxFlanger:   MidiOutMapping(type: .note, number: 11, channel: 0, onValue: 127, offValue: 0),
                .fxPhaser:    MidiOutMapping(type: .note, number: 10, channel: 0, onValue: 127, offValue: 0),
                .fxEcho:      MidiOutMapping(type: .note, number: 13, channel: 0, onValue: 127, offValue: 0),
                .fxDubDelay:  MidiOutMapping(type: .note, number: 9,  channel: 0, onValue: 127, offValue: 0),
                .fxReverb:    MidiOutMapping(type: .note, number: 8,  channel: 0, onValue: 127, offValue: 0)
            ]
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: MidiOutMapping].self, from: data)
            var loaded: [FlexFxMidiTarget: MidiOutMapping] = [:]
            for (key, val) in decoded {
                if let target = FlexFxMidiTarget(rawValue: key) {
                    loaded[target] = val
                }
            }
            self.outMappings = loaded
        } catch {
            print("Failed to load MIDI out mappings: \(error)")
        }
    }

    private func saveOutMappings() {
        var dict: [String: MidiOutMapping] = [:]
        for (target, mapping) in outMappings {
            dict[target.rawValue] = mapping
        }
        do {
            let data = try JSONEncoder().encode(dict)
            UserDefaults.standard.set(data, forKey: outDefaultsKey)
        } catch {
            print("Failed to save MIDI out mappings: \(error)")
        }
        onOutMappingUpdated?()
        for obs in outMappingObservers.values {
            obs()
        }
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
        for obs in filterRulesObservers.values {
            obs()
        }
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

    public func outMappingFor(target: FlexFxMidiTarget) -> MidiOutMapping? {
        return outMappings[target]
    }

    public func clearOutMapping(for target: FlexFxMidiTarget) {
        outMappings.removeValue(forKey: target)
        saveOutMappings()
    }

    public func setOutMapping(for target: FlexFxMidiTarget, mapping: MidiOutMapping) {
        // Remove any other target that had this same out mapping to avoid hardware LED conflict
        for (t, m) in outMappings where t != target && m.type == mapping.type && m.number == mapping.number && m.channel == mapping.channel {
            outMappings.removeValue(forKey: t)
        }
        outMappings[target] = mapping
        saveOutMappings()
    }

    public var allMappings: [FlexFxMidiTarget: MidiMapping] {
        return mappings
    }

    public var allOutMappings: [FlexFxMidiTarget: MidiOutMapping] {
        return outMappings
    }

    public func applyMappings(_ newMappings: [FlexFxMidiTarget: MidiMapping]) {
        self.mappings = newMappings
        saveMappings()
    }

    public func applyOutMappings(_ newOutMappings: [FlexFxMidiTarget: MidiOutMapping]) {
        self.outMappings = newOutMappings
        saveOutMappings()
    }

    public func clearAllOutMappings() {
        outMappings.removeAll()
        saveOutMappings()
    }

    // Button debounce tracking: Target -> last trigger timestamp
    private var lastButtonTriggerTimes: [FlexFxMidiTarget: TimeInterval] = [:]

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
                let existing = mappings[target]
                let iType = existing?.interactionType ?? target.defaultInteractionType
                let bMode = existing?.buttonMode ?? .toggle
                let newMapping = MidiMapping(type: msgType, number: d1, channel: channel, interactionType: iType, buttonMode: bMode)
                // Remove any existing target that used this exact message to avoid conflicts
                for (t, m) in mappings where m == newMapping {
                    mappings.removeValue(forKey: t)
                }
                mappings[target] = newMapping
                saveMappings()

                // Synchronously disable Learn Mode so that subsequent MIDI events take effect immediately live!
                self.isLearnModeActive = false
                self.selectedTarget = nil
                return true
            }
            return false
        }

        // 2. Normal Mode: check if message matches any mapped target
        var handled = false
        let isNoteOff = (typeNibble == 0x80) || (typeNibble == 0x90 && d2 == 0)
        let isPressed = isNoteMessage ? !isNoteOff : (d2 > 0)
        let now = Date().timeIntervalSince1970

        for (target, mapping) in mappings {
            if mapping.type == msgType && mapping.number == d1 {
                // If channel is specified, verify match
                if mapping.channel != 255 && mapping.channel != channel {
                    continue
                }

                // If it's a button configured as Toggle or Trigger (or a direct select button like FX selection),
                // ignore button release (Note-Off / velocity 0) so we only trigger once on press!
                if mapping.interactionType == .button {
                    if (mapping.buttonMode == .toggle || mapping.buttonMode == .trigger) && !isPressed {
                        handled = true
                        continue
                    }
                    // For direct selectors (e.g. fxFilter, fxFlanger, fxPhaser, fxEcho, fxDubDelay, fxReverb, prevBeat, nextBeat)
                    // ignore release as well so it doesn't trigger actions twice
                    switch target {
                    case .fxFilter, .fxFlanger, .fxPhaser, .fxEcho, .fxDubDelay, .fxReverb, .prevBeat, .nextBeat:
                        if !isPressed {
                            handled = true
                            continue
                        }
                    default:
                        break
                    }

                    // Debounce button press events within 120ms to prevent duplicate triggers / contact bouncing / MIDI bursts
                    if isPressed {
                        if let lastTime = lastButtonTriggerTimes[target], (now - lastTime) < 0.12 {
                            handled = true
                            continue
                        }
                        lastButtonTriggerTimes[target] = now
                    }
                }

                handled = true
                let normVal = Float(d2) / 127.0
                let iType = mapping.interactionType
                let bMode = mapping.buttonMode
                DispatchQueue.main.async { [weak self] in
                    self?.executeTargetAction(target: target, rawValue: d2, normValue: normVal, isPressed: isPressed, interactionType: iType, buttonMode: bMode)
                }
            }
        }
        return handled
    }

    private func executeTargetAction(target: FlexFxMidiTarget, rawValue: UInt8, normValue: Float, isPressed: Bool, interactionType: ControlInteractionType, buttonMode: ButtonMode = .toggle) {
        let flex = RaneFlexFxService.shared

        // Encoder relative step calculation (65 / 1 = +1, 63 / 127 = -1)
        let isRelativeIncrement = (rawValue == 1 || rawValue == 65)
        let isRelativeDecrement = (rawValue == 127 || rawValue == 63)

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
        case .fxDubDelay:
            if interactionType == .button {
                if isPressed { flex.currentEffect = .dubDelay }
            } else {
                flex.currentEffect = .dubDelay
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
                case .toggle, .trigger:
                    if isPressed { flex.isEnabled.toggle() }
                case .hold:
                    flex.isEnabled = isPressed
                case .direct:
                    flex.isEnabled = isPressed
                }
            } else {
                flex.isEnabled = (normValue > 0.5 || rawValue > 0)
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
        case .tempo:
            if interactionType == .encoder {
                let step = isRelativeIncrement ? 0.5 : (isRelativeDecrement ? -0.5 : (normValue > 0.5 ? 0.5 : -0.5))
                flex.setManualBpm(flex.bpm + step)
            } else {
                // Absolute mapping: 60 BPM (at 0) to 200 BPM (at 127)
                let targetBpm = 60.0 + Double(normValue) * 140.0
                flex.setManualBpm(round(targetBpm * 10.0) / 10.0)
            }
        case .prePost:
            if interactionType == .button {
                switch buttonMode {
                case .toggle, .trigger:
                    if isPressed { flex.isPreFader.toggle() }
                case .hold:
                    flex.isPreFader = isPressed
                case .direct:
                    flex.isPreFader = isPressed
                }
            } else {
                flex.isPreFader = (normValue > 0.5 || rawValue > 0)
            }
        case .modulePower:
            if interactionType == .button {
                switch buttonMode {
                case .toggle:
                    if isPressed { flex.isModuleEnabled.toggle() }
                case .hold:
                    flex.isModuleEnabled = isPressed
                case .direct:
                    flex.isModuleEnabled = isPressed
                case .trigger:
                    // Trigger: Ein Trigger schaltet um (True/False bzw. 0/1...an..aus)
                    if isPressed {
                        flex.isModuleEnabled.toggle()
                    }
                }
            } else {
                flex.isModuleEnabled = (normValue > 0.5 || rawValue > 0)
            }
        case .abletonLink:
            if interactionType == .button {
                switch buttonMode {
                case .toggle, .trigger:
                    if isPressed { flex.isLinkEnabled.toggle() }
                case .hold, .direct:
                    flex.isLinkEnabled = isPressed
                }
            } else {
                flex.isLinkEnabled = (normValue > 0.5 || rawValue > 0)
            }
        case .inputSelect:
            if interactionType == .button {
                if isPressed { flex.cycleInputSource() }
            } else {
                let all = FlexFxInputSource.allCases
                let idx = min(all.count - 1, max(0, Int(normValue * Float(all.count))))
                flex.inputSource = all[idx]
            }
        case .inputFlexFx:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .flexFxSend }
        case .inputPgm1:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .pgm1 }
        case .inputPgm2:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .pgm2 }
        case .inputPgm3:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .pgm3 }
        case .inputPgm4:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .pgm4 }
        case .inputMainMix:
            if isPressed || interactionType == .faderKnob { flex.inputSource = .mainMix }
        }

        onMidiActionTriggered?(target, normValue)
        for obs in midiActionObservers.values {
            obs(target, normValue)
        }
    }
}
