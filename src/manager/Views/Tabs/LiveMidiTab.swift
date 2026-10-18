/* SPDX-License-Identifier: MIT */
/* LiveMidiTab.swift - Tab 3: Traktor-Style Controller Manager, MIDI Filter / Blacklist & Live Event Monitor */

import Cocoa

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {

    // Persistent Table & Filter References
    private struct ControllerManagerRefs {
        static var mappingTableView: NSTableView?
        static var filterTableView: NSTableView?
        static var tableModeSegment: NSSegmentedControl?
        static var controllerDevicePopup: NSPopUpButton?
        static var isOutTableActive: Bool = false

        static var filterTypePopup: NSPopUpButton?
        static var filterNumberField: NSTextField?
        static var filterChannelPopup: NSPopUpButton?
        static var filterLabelField: NSTextField?

        static var channelFilterSegment: NSSegmentedControl?
        static var selectedFilterIndex: Int = 0 // 0: Alle, 1: PGM 1, 2: PGM 2, 3: PGM 3, 4: PGM 4, 5: FlexFX, 6: Global/Mixer

        static var allInMappingRows: [FlexFxMidiTarget] = [
            // ── PGM 1 (Deck 1) ──
            .pgm1Slot1Toggle,
            .pgm1Slot1PreGain,
            .pgm1Slot1PostGain,
            .pgm1Slot2Toggle,
            .pgm1Slot2PreGain,
            .pgm1Slot2PostGain,
            .pgm1DryPreGain,
            .pgm1DryPostGain,

            // ── PGM 2 (Deck 2) ──
            .pgm2Slot1Toggle,
            .pgm2Slot1PreGain,
            .pgm2Slot1PostGain,
            .pgm2Slot2Toggle,
            .pgm2Slot2PreGain,
            .pgm2Slot2PostGain,
            .pgm2DryPreGain,
            .pgm2DryPostGain,

            // ── PGM 3 (Deck 3) ──
            .pgm3Slot1Toggle,
            .pgm3Slot1PreGain,
            .pgm3Slot1PostGain,
            .pgm3Slot2Toggle,
            .pgm3Slot2PreGain,
            .pgm3Slot2PostGain,
            .pgm3DryPreGain,
            .pgm3DryPostGain,

            // ── PGM 4 (Deck 4) ──
            .pgm4Slot1Toggle,
            .pgm4Slot1PreGain,
            .pgm4Slot1PostGain,
            .pgm4Slot2Toggle,
            .pgm4Slot2PreGain,
            .pgm4Slot2PostGain,
            .pgm4DryPreGain,
            .pgm4DryPostGain,

            // ── FlexFX Return Bus ──
            .flexFxSlot1Toggle,
            .flexFxSlot1PreGain,
            .flexFxSlot1PostGain,
            .flexFxSlot2Toggle,
            .flexFxSlot2PreGain,
            .flexFxSlot2PostGain,
            .flexFxDryPreGain,
            .flexFxDryPostGain,

            // ── Aktiver Kanal (UI Fokus) ──
            .vst1Toggle,
            .fx1PreGain,
            .fx1PostGain,
            .vst2Toggle,
            .fx2PreGain,
            .fx2PostGain,
            .dryPreGain,
            .dryPostGain,

            // ── Master Tempo, Link & Module ──
            .tempo,
            .abletonLink,
            .modulePower,
            .prePost,

            // ── Direct Stereo Input Pair Selectors (Ch 1–12) ──
            .inputPgm1,
            .inputPgm2,
            .inputPgm3,
            .inputPgm4,
            .inputFlexFx,
            .inputMainMix,

            // ── Direct Stereo Output Pair Selectors (Ch 1–10) ──
            .outputPgm1,
            .outputPgm2,
            .outputPgm3,
            .outputPgm4,
            .outputFlexFx
        ]

        // Out mapping rows: Targets that have status / LED indicators
        static var allOutMappingRows: [FlexFxMidiTarget] = [
            // ── PGM 1 (Deck 1) ──
            .pgm1Slot1Toggle,
            .pgm1Slot2Toggle,

            // ── PGM 2 (Deck 2) ──
            .pgm2Slot1Toggle,
            .pgm2Slot2Toggle,

            // ── PGM 3 (Deck 3) ──
            .pgm3Slot1Toggle,
            .pgm3Slot2Toggle,

            // ── PGM 4 (Deck 4) ──
            .pgm4Slot1Toggle,
            .pgm4Slot2Toggle,

            // ── FlexFX Return Bus ──
            .flexFxSlot1Toggle,
            .flexFxSlot2Toggle,

            // ── Aktiver Kanal (UI Fokus) ──
            .vst1Toggle,
            .vst2Toggle,

            // ── Global / Mixer LEDs ──
            .abletonLink,
            .modulePower,
            .prePost,
            .inputPgm1,
            .inputPgm2,
            .inputPgm3,
            .inputPgm4,
            .inputFlexFx,
            .inputMainMix,
            .outputPgm1,
            .outputPgm2,
            .outputPgm3,
            .outputPgm4,
            .outputFlexFx
        ]

        static var currentRows: [FlexFxMidiTarget] {
            let base = isOutTableActive ? allOutMappingRows : allInMappingRows
            switch selectedFilterIndex {
            case 1: // PGM 1
                return base.filter { $0.channelIndexAndControl?.channelIndex == 0 }
            case 2: // PGM 2
                return base.filter { $0.channelIndexAndControl?.channelIndex == 1 }
            case 3: // PGM 3
                return base.filter { $0.channelIndexAndControl?.channelIndex == 2 }
            case 4: // PGM 4
                return base.filter { $0.channelIndexAndControl?.channelIndex == 3 }
            case 5: // FlexFX
                return base.filter { $0.channelIndexAndControl?.channelIndex == 4 }
            case 6: // Global / Aktiv
                return base.filter { $0.channelIndexAndControl == nil }
            default: // 0: Alle
                return base
            }
        }
    }

    func buildMidiPage() -> NSView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 8
        page.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        // =========================================================================
        // SECTION 1: TRAKTOR CONTROLLER MANAGER MAPPING TABLE (IN / OUT TOGGLE)
        // =========================================================================
        let sec1Outer = NSStackView()
        sec1Outer.orientation = .vertical
        sec1Outer.alignment = .leading
        sec1Outer.spacing = 6

        let sec1TopBar = NSStackView()
        sec1TopBar.orientation = .horizontal
        sec1TopBar.alignment = .centerY
        sec1TopBar.spacing = 8
        sec1TopBar.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "slider.horizontal.2.square", accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        }
        iconView.contentTintColor = .systemOrange
        sec1TopBar.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: Localization.tr(
            en: "Controller Manager",
            de: "Controller Manager"
        ))
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
        sec1TopBar.addArrangedSubview(titleLabel)

        // Segmented Control: [Add In... (Inputs)] vs [Add Out... (LED Outputs)]
        let modeSegment = NSSegmentedControl(labels: ["Add In... (Controller Input)", "Add Out... (LED Feedback)"], trackingMode: .selectOne, target: self, action: #selector(onTableModeChanged(_:)))
        modeSegment.selectedSegment = ControllerManagerRefs.isOutTableActive ? 1 : 0
        modeSegment.controlSize = .small
        modeSegment.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        sec1TopBar.addArrangedSubview(modeSegment)
        ControllerManagerRefs.tableModeSegment = modeSegment

        // Channel Category Filter: [Alle | PGM 1 | PGM 2 | PGM 3 | PGM 4 | FlexFX | Global]
        let chFilterSegment = NSSegmentedControl(
            labels: ["Alle", "PGM 1", "PGM 2", "PGM 3", "PGM 4", "FlexFX", "Global"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(onChannelFilterChanged(_:))
        )
        chFilterSegment.selectedSegment = ControllerManagerRefs.selectedFilterIndex
        chFilterSegment.controlSize = .small
        chFilterSegment.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        sec1TopBar.addArrangedSubview(chFilterSegment)
        ControllerManagerRefs.channelFilterSegment = chFilterSegment

        // Controller MIDI Input Device Selector
        let devLabel = NSTextField(labelWithString: "MIDI-In:")
        devLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        devLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        sec1TopBar.addArrangedSubview(devLabel)

        let devPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        devPopup.controlSize = .small
        devPopup.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        devPopup.target = self
        devPopup.action = #selector(onControllerMidiDeviceSelected(_:))
        rebuildControllerDeviceMenu(for: devPopup)
        sec1TopBar.addArrangedSubview(devPopup)
        ControllerManagerRefs.controllerDevicePopup = devPopup

        let spacer1 = NSView()
        spacer1.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sec1TopBar.addArrangedSubview(spacer1)

        let clearAllBtn = NSButton(title: "✕ Reset All", target: self, action: #selector(onClearAllMappingsClicked))
        clearAllBtn.bezelStyle = .inline
        clearAllBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        clearAllBtn.wantsLayer = true
        clearAllBtn.layer?.cornerRadius = 4
        clearAllBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.20).cgColor
        clearAllBtn.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.6).cgColor
        clearAllBtn.layer?.borderWidth = 1.0
        clearAllBtn.contentTintColor = NSColor.systemRed
        sec1TopBar.addArrangedSubview(clearAllBtn)

        sec1Outer.addArrangedSubview(sec1TopBar)
        sec1TopBar.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true

        // Mapping Table View
        let tableScroll = NSScrollView()
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = false
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .noBorder
        tableScroll.drawsBackground = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.identifier = NSUserInterfaceItemIdentifier("MappingTable")
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor(white: 0.22, alpha: 0.8)
        tableView.backgroundColor = NSColor(red: 0.12, green: 0.125, blue: 0.14, alpha: 1.0)

        tableView.dataSource = self
        tableView.delegate = self
        tableScroll.documentView = tableView
        ControllerManagerRefs.mappingTableView = tableView

        configureMappingTableColumns(tableView: tableView)

        let tableCard = tableScroll.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.12, green: 0.125, blue: 0.14, alpha: 1.0),
            padding: NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        )
        sec1Outer.addArrangedSubview(tableCard)
        tableCard.widthAnchor.constraint(equalTo: sec1Outer.widthAnchor).isActive = true
        tableScroll.heightAnchor.constraint(equalToConstant: 225).isActive = true

        let sec1Inset = sec1Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        )
        page.addArrangedSubview(sec1Inset)
        sec1Inset.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // =========================================================================
        // SECTION 2: MIDI INPUT FILTER & BLACKLIST (Block Faders, CCs, Notes)
        // =========================================================================
        let sec2Outer = NSStackView()
        sec2Outer.orientation = .vertical
        sec2Outer.alignment = .leading
        sec2Outer.spacing = 6

        let sec2TopBar = NSStackView()
        sec2TopBar.orientation = .horizontal
        sec2TopBar.alignment = .centerY
        sec2TopBar.spacing = 8
        sec2TopBar.translatesAutoresizingMaskIntoConstraints = false

        let filterIconView = NSImageView()
        if let img = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil) {
            filterIconView.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        }
        filterIconView.contentTintColor = .systemTeal
        sec2TopBar.addArrangedSubview(filterIconView)

        let filterTitle = NSTextField(labelWithString: Localization.tr(
            en: "MIDI Input Filter / Blacklist (Fader & Störsignal-Filter)",
            de: "MIDI Input Filter / Blacklist (Fader & Störsignal-Filter)"
        ))
        filterTitle.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        filterTitle.textColor = NSColor(white: 0.92, alpha: 1.0)
        sec2TopBar.addArrangedSubview(filterTitle)

        let fSpacer = NSView()
        fSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sec2TopBar.addArrangedSubview(fSpacer)

        let presetFadersBtn = NSButton(title: "⚡ Filter Sixty-Eight Faders", target: self, action: #selector(onFilterPresetFadersClicked))
        presetFadersBtn.bezelStyle = .inline
        presetFadersBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        presetFadersBtn.wantsLayer = true
        presetFadersBtn.layer?.cornerRadius = 4
        presetFadersBtn.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.20).cgColor
        presetFadersBtn.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.6).cgColor
        presetFadersBtn.layer?.borderWidth = 1.0
        presetFadersBtn.contentTintColor = NSColor.systemTeal
        sec2TopBar.addArrangedSubview(presetFadersBtn)

        let clearFilterBtn = NSButton(title: "✕ Reset Filter", target: self, action: #selector(onClearAllFiltersClicked))
        clearFilterBtn.bezelStyle = .inline
        clearFilterBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        clearFilterBtn.wantsLayer = true
        clearFilterBtn.layer?.cornerRadius = 4
        clearFilterBtn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.6).cgColor
        clearFilterBtn.contentTintColor = NSColor(white: 0.8, alpha: 1.0)
        sec2TopBar.addArrangedSubview(clearFilterBtn)

        sec2Outer.addArrangedSubview(sec2TopBar)
        sec2TopBar.widthAnchor.constraint(equalTo: sec2Outer.widthAnchor).isActive = true

        // Filter Input Bar (Add custom rule)
        let addRuleBar = NSStackView()
        addRuleBar.orientation = .horizontal
        addRuleBar.alignment = .centerY
        addRuleBar.spacing = 8

        let typePop = NSPopUpButton(title: "CC #", target: nil, action: nil)
        typePop.addItems(withTitles: ["CC #", "Note"])
        typePop.controlSize = .small
        addRuleBar.addArrangedSubview(typePop)
        ControllerManagerRefs.filterTypePopup = typePop

        let numField = NSTextField(string: "112")
        numField.placeholderString = "Nr. (0..127)"
        numField.controlSize = .small
        numField.alignment = .center
        numField.translatesAutoresizingMaskIntoConstraints = false
        numField.widthAnchor.constraint(equalToConstant: 75).isActive = true
        addRuleBar.addArrangedSubview(numField)
        ControllerManagerRefs.filterNumberField = numField

        let chPop = NSPopUpButton(title: "All Channels", target: nil, action: nil)
        var chTitles = ["All Channels"]
        for c in 1...16 { chTitles.append("Ch \(c)") }
        chPop.addItems(withTitles: chTitles)
        chPop.controlSize = .small
        addRuleBar.addArrangedSubview(chPop)
        ControllerManagerRefs.filterChannelPopup = chPop

        let labelField = NSTextField(string: "")
        labelField.placeholderString = "Bezeichnung (z. B. Mixer Fader)"
        labelField.controlSize = .small
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        addRuleBar.addArrangedSubview(labelField)
        ControllerManagerRefs.filterLabelField = labelField

        let addBtn = NSButton(title: "+ Add Filter", target: self, action: #selector(onAddFilterRuleClicked))
        addBtn.bezelStyle = .inline
        addBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 4
        addBtn.layer?.backgroundColor = NSColor.systemIndigo.withAlphaComponent(0.3).cgColor
        addBtn.layer?.borderColor = NSColor.systemIndigo.cgColor
        addBtn.layer?.borderWidth = 1.0
        addBtn.contentTintColor = NSColor.systemIndigo
        addRuleBar.addArrangedSubview(addBtn)

        sec2Outer.addArrangedSubview(addRuleBar)

        // Filter Table View
        let filterScroll = NSScrollView()
        filterScroll.hasVerticalScroller = true
        filterScroll.hasHorizontalScroller = false
        filterScroll.autohidesScrollers = true
        filterScroll.borderType = .noBorder
        filterScroll.drawsBackground = false
        filterScroll.translatesAutoresizingMaskIntoConstraints = false

        let fTableView = NSTableView()
        fTableView.identifier = NSUserInterfaceItemIdentifier("FilterTable")
        fTableView.headerView = NSTableHeaderView()
        fTableView.usesAlternatingRowBackgroundColors = true
        fTableView.rowHeight = 19
        fTableView.gridStyleMask = [.solidHorizontalGridLineMask]
        fTableView.gridColor = NSColor(white: 0.20, alpha: 0.8)
        fTableView.backgroundColor = NSColor(red: 0.11, green: 0.115, blue: 0.13, alpha: 1.0)

        let colFilterType = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FType"))
        colFilterType.title = "Message"
        colFilterType.width = 90
        fTableView.addTableColumn(colFilterType)

        let colFilterNum = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FNum"))
        colFilterNum.title = "Number"
        colFilterNum.width = 70
        fTableView.addTableColumn(colFilterNum)

        let colFilterCh = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FCh"))
        colFilterCh.title = "Channel"
        colFilterCh.width = 90
        fTableView.addTableColumn(colFilterCh)

        let colFilterDesc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FDesc"))
        colFilterDesc.title = "Description / Label"
        colFilterDesc.width = 210
        fTableView.addTableColumn(colFilterDesc)

        let colFilterAction = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FAction"))
        colFilterAction.title = "Action"
        colFilterAction.width = 65
        fTableView.addTableColumn(colFilterAction)

        fTableView.dataSource = self
        fTableView.delegate = self
        filterScroll.documentView = fTableView
        ControllerManagerRefs.filterTableView = fTableView

        let fTableCard = filterScroll.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.11, green: 0.115, blue: 0.13, alpha: 1.0),
            padding: NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        )
        sec2Outer.addArrangedSubview(fTableCard)
        fTableCard.widthAnchor.constraint(equalTo: sec2Outer.widthAnchor).isActive = true
        filterScroll.heightAnchor.constraint(equalToConstant: 105).isActive = true

        let sec2Inset = sec2Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        )
        page.addArrangedSubview(sec2Inset)
        sec2Inset.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        // =========================================================================
        // SECTION 3: LIVE MONITOR
        // =========================================================================
        let sec3Outer = NSStackView()
        sec3Outer.orientation = .vertical
        sec3Outer.alignment = .leading
        sec3Outer.spacing = 6

        let sec3TopBar = createSectionTopBar(
            icon: "terminal",
            title: Localization.tr(en: "Live MIDI Event Stream (Bidirectional)", de: "Live MIDI Event Stream (Bidirektional)"),
            tintColor: .systemGreen
        )
        sec3Outer.addArrangedSubview(sec3TopBar)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        midiLogScrollView = scroll

        let contentSize = scroll.contentSize
        midiLogTextView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        midiLogTextView.minSize = NSSize(width: 0.0, height: contentSize.height)
        midiLogTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        midiLogTextView.isVerticallyResizable = true
        midiLogTextView.isHorizontallyResizable = false
        midiLogTextView.autoresizingMask = [.width]
        midiLogTextView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        midiLogTextView.textContainer?.widthTracksTextView = true
        midiLogTextView.isEditable = false
        midiLogTextView.isSelectable = true
        midiLogTextView.backgroundColor = NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0)
        midiLogTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        midiLogTextView.textColor = NSColor(white: 0.90, alpha: 1.0)
        scroll.documentView = midiLogTextView

        let innerScrollCard = scroll.wrapInCard(
            cornerRadius: 8,
            borderColor: NSColor(white: 0.28, alpha: 0.45),
            fillColor: NSColor(red: 0.10, green: 0.105, blue: 0.12, alpha: 1.0),
            padding: NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        )
        sec3Outer.addArrangedSubview(innerScrollCard)
        innerScrollCard.widthAnchor.constraint(equalTo: sec3Outer.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 95).isActive = true

        let sec3Inset = sec3Outer.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        )
        page.addArrangedSubview(sec3Inset)
        sec3Inset.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        setupControllerManagerCallbacks()

        return page
    }

    // MARK: - Controller Manager & Filter Callbacks
    private func setupControllerManagerCallbacks() {
        let learn = RaneMidiLearnService.shared
        learn.addMappingObserver {
            DispatchQueue.main.async {
                if !ControllerManagerRefs.isOutTableActive {
                    ControllerManagerRefs.mappingTableView?.reloadData()
                }
            }
        }

        learn.addOutMappingObserver {
            DispatchQueue.main.async {
                if ControllerManagerRefs.isOutTableActive {
                    ControllerManagerRefs.mappingTableView?.reloadData()
                }
            }
        }

        learn.addSelectedTargetObserver { _ in
            DispatchQueue.main.async {
                ControllerManagerRefs.mappingTableView?.reloadData()
            }
        }

        learn.addLearnModeObserver { _ in
            DispatchQueue.main.async {
                ControllerManagerRefs.mappingTableView?.reloadData()
            }
        }

        learn.addFilterRulesObserver {
            DispatchQueue.main.async {
                ControllerManagerRefs.filterTableView?.reloadData()
            }
        }
    }

    func configureMappingTableColumns(tableView: NSTableView) {
        while !tableView.tableColumns.isEmpty {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        if ControllerManagerRefs.isOutTableActive {
            // OUT TABLE COLUMNS: Control | LED Output (Type / # / Ch) | On Color | Off Color | Test | Action
            let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Control"))
            col1.title = "Control (Target)"
            col1.width = 160
            tableView.addTableColumn(col1)

            let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutMidi"))
            col2.title = "LED Output (Type / # / Ch)"
            col2.width = 190
            tableView.addTableColumn(col2)

            let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OnColor"))
            col3.title = "On Value (0-127)"
            col3.width = 110
            tableView.addTableColumn(col3)

            let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OffColor"))
            col4.title = "Off Value (0-127)"
            col4.width = 110
            tableView.addTableColumn(col4)

            let col5 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TestLed"))
            col5.title = "Test LED"
            col5.width = 80
            tableView.addTableColumn(col5)

            let col6 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Reset"))
            col6.title = "Action"
            col6.width = 70
            tableView.addTableColumn(col6)
        } else {
            // IN TABLE COLUMNS: Control | Type | Option | Mapped MIDI | Learn | Action
            let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Control"))
            col1.title = "Control (Target)"
            col1.width = 160
            tableView.addTableColumn(col1)

            let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Type"))
            col2.title = "Type"
            col2.width = 120
            tableView.addTableColumn(col2)

            let col3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Option"))
            col3.title = "Option (Mode)"
            col3.width = 120
            tableView.addTableColumn(col3)

            let col4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Midi"))
            col4.title = "Mapped MIDI (Type / # / Ch)"
            col4.width = 190
            tableView.addTableColumn(col4)

            let col5 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Learn"))
            col5.title = "Learn"
            col5.width = 80
            tableView.addTableColumn(col5)

            let col6 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Reset"))
            col6.title = "Action"
            col6.width = 70
            tableView.addTableColumn(col6)
        }
    }

    func rebuildControllerDeviceMenu(for popup: NSPopUpButton) {
        popup.removeAllItems()
        let currentSourceId = RaneMidiLearnService.shared.controllerMidiSourceId

        let omniItem = NSMenuItem(title: "Alle Controller (Omni)", action: nil, keyEquivalent: "")
        omniItem.representedObject = "OMNI"
        popup.menu?.addItem(omniItem)

        let devices = RaneMidiService.shared.availableInputDevices
        if !devices.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            for dev in devices {
                let item = NSMenuItem(title: "🎛 \(dev.displayName)", action: nil, keyEquivalent: "")
                item.representedObject = dev.id
                popup.menu?.addItem(item)
            }
        }

        if currentSourceId != "OMNI" && !popup.itemArray.contains(where: { ($0.representedObject as? String) == currentSourceId }) {
            let item = NSMenuItem(title: "🎛 \(currentSourceId) (Offline)", action: nil, keyEquivalent: "")
            item.representedObject = currentSourceId
            popup.menu?.addItem(item)
        }

        if let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == currentSourceId }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    @objc func onControllerMidiDeviceSelected(_ sender: NSPopUpButton) {
        guard let sourceId = sender.selectedItem?.representedObject as? String else { return }
        RaneMidiLearnService.shared.controllerMidiSourceId = sourceId
        appendMidiLog("Controller Manager MIDI-Eingang gewählt: [\(sender.selectedItem?.title ?? sourceId)]")
    }

    @objc func onTableModeChanged(_ sender: NSSegmentedControl) {
        ControllerManagerRefs.isOutTableActive = (sender.selectedSegment == 1)
        if let tv = ControllerManagerRefs.mappingTableView {
            configureMappingTableColumns(tableView: tv)
            tv.reloadData()
        }
        let modeName = ControllerManagerRefs.isOutTableActive ? "Add Out... (LED Feedback)" : "Add In... (Controller Input)"
        appendMidiLog("Controller Manager Modus gewechselt: [\(modeName)]")
    }

    @objc func onChannelFilterChanged(_ sender: NSSegmentedControl) {
        ControllerManagerRefs.selectedFilterIndex = sender.selectedSegment
        ControllerManagerRefs.mappingTableView?.reloadData()
        let filterName = sender.label(forSegment: sender.selectedSegment) ?? ""
        appendMidiLog("Controller Manager Kanalfilter: [\(filterName)]")
    }

    // MARK: - NSTableViewDataSource & NSTableViewDelegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView.identifier?.rawValue == "FilterTable" {
            return RaneMidiLearnService.shared.filterRules.count
        }
        return ControllerManagerRefs.currentRows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn else { return nil }

        // FILTER TABLE
        if tableView.identifier?.rawValue == "FilterTable" {
            let rules = RaneMidiLearnService.shared.filterRules
            guard row < rules.count else { return nil }
            let rule = rules[row]
            let cellId = col.identifier.rawValue

            if cellId == "FType" {
                let lbl = NSTextField(labelWithString: rule.type == .cc ? "Control Change" : "Note On/Off")
                lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                lbl.textColor = rule.type == .cc ? NSColor.systemTeal : NSColor.systemPurple
                return lbl
            } else if cellId == "FNum" {
                let lbl = NSTextField(labelWithString: "\(rule.number)")
                lbl.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
                lbl.textColor = NSColor.white
                return lbl
            } else if cellId == "FCh" {
                let chStr = (rule.channel == 255) ? "All" : "Ch \(rule.channel + 1)"
                let lbl = NSTextField(labelWithString: chStr)
                lbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
                lbl.textColor = NSColor(white: 0.75, alpha: 1.0)
                return lbl
            } else if cellId == "FDesc" {
                let lbl = NSTextField(labelWithString: rule.label.isEmpty ? "Blacklist Rule" : rule.label)
                lbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
                lbl.textColor = NSColor(white: 0.65, alpha: 1.0)
                return lbl
            } else if cellId == "FAction" {
                let btn = NSButton(title: "Remove", target: self, action: #selector(onRemoveFilterRuleClicked(_:)))
                btn.tag = row
                btn.bezelStyle = .inline
                btn.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                btn.wantsLayer = true
                btn.layer?.cornerRadius = 4
                btn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.20).cgColor
                btn.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
                btn.layer?.borderWidth = 1.0
                btn.contentTintColor = NSColor.systemRed
                return btn
            }
            return nil
        }

        // MAPPING TABLE
        if ControllerManagerRefs.isOutTableActive {
            guard row < ControllerManagerRefs.currentRows.count else { return nil }
            let target = ControllerManagerRefs.currentRows[row]
            let learn = RaneMidiLearnService.shared
            let outMap = learn.outMappingFor(target: target)
            let cellId = col.identifier.rawValue

            if cellId == "Control" {
                let label = NSTextField(labelWithString: target.displayName)
                label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
                label.textColor = NSColor.white
                return label
            } else if cellId == "OutMidi" {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.spacing = 4
                stack.alignment = .centerY

                // Type Popup (CC / Note)
                let typePop = NSPopUpButton(frame: .zero, pullsDown: false)
                typePop.controlSize = .small
                typePop.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
                typePop.tag = row
                typePop.addItems(withTitles: ["CC", "Note"])
                typePop.selectItem(at: (outMap?.type == .cc) ? 0 : 1) // default Note
                typePop.target = self
                typePop.action = #selector(onTableRowOutMidiTypeChanged(_:))
                stack.addArrangedSubview(typePop)

                // Number Field (0..127)
                let numField = NSTextField()
                numField.controlSize = .small
                numField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                numField.alignment = .center
                numField.tag = row
                numField.placeholderString = "--"
                if let m = outMap {
                    numField.stringValue = "\(m.number)"
                    numField.textColor = NSColor.systemTeal
                } else {
                    numField.stringValue = ""
                    numField.textColor = NSColor(white: 0.5, alpha: 1.0)
                }
                numField.target = self
                numField.action = #selector(onTableRowOutMidiNumberChanged(_:))
                numField.translatesAutoresizingMaskIntoConstraints = false
                numField.widthAnchor.constraint(equalToConstant: 40).isActive = true
                stack.addArrangedSubview(numField)

                // Channel Popup (Ch 1..16)
                let chPop = NSPopUpButton(frame: .zero, pullsDown: false)
                chPop.controlSize = .small
                chPop.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                chPop.tag = row
                var chTitles: [String] = []
                for c in 1...16 { chTitles.append("Ch \(c)") }
                chPop.addItems(withTitles: chTitles)
                let ch = outMap?.channel ?? 0
                chPop.selectItem(at: min(Int(ch), 15))
                chPop.target = self
                chPop.action = #selector(onTableRowOutMidiChannelChanged(_:))
                stack.addArrangedSubview(chPop)

                return stack
            } else if cellId == "OnColor" {
                let numField = NSTextField()
                numField.controlSize = .small
                numField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                numField.alignment = .center
                numField.tag = row
                numField.placeholderString = "127"
                numField.stringValue = "\(outMap?.onValue ?? 127)"
                numField.textColor = NSColor.systemYellow
                numField.target = self
                numField.action = #selector(onTableRowOnValueChanged(_:))
                return numField
            } else if cellId == "OffColor" {
                let numField = NSTextField()
                numField.controlSize = .small
                numField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                numField.alignment = .center
                numField.tag = row
                numField.placeholderString = "0"
                numField.stringValue = "\(outMap?.offValue ?? 0)"
                numField.textColor = NSColor(white: 0.65, alpha: 1.0)
                numField.target = self
                numField.action = #selector(onTableRowOffValueChanged(_:))
                return numField
            } else if cellId == "TestLed" {
                let btn = NSButton(title: "Test", target: self, action: #selector(onTableRowTestLedClicked(_:)))
                btn.tag = row
                btn.bezelStyle = .inline
                btn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
                btn.wantsLayer = true
                btn.layer?.cornerRadius = 4
                btn.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.25).cgColor
                btn.layer?.borderColor = NSColor.systemTeal.cgColor
                btn.layer?.borderWidth = 1.0
                btn.contentTintColor = NSColor.systemTeal
                return btn
            } else if cellId == "Reset" {
                let btn = NSButton(title: "Clear", target: self, action: #selector(onTableRowClearOutClicked(_:)))
                btn.tag = row
                btn.bezelStyle = .inline
                btn.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                btn.wantsLayer = true
                btn.layer?.cornerRadius = 4
                btn.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.7).cgColor
                btn.contentTintColor = outMap != nil ? NSColor.systemOrange : NSColor(white: 0.4, alpha: 1.0)
                btn.isEnabled = (outMap != nil)
                return btn
            }
            return nil
        }

        // IN MAPPING TABLE
        guard row < ControllerManagerRefs.currentRows.count else { return nil }
        let target = ControllerManagerRefs.currentRows[row]
        let learn = RaneMidiLearnService.shared
        let mapping = learn.mappingFor(target: target)
        let isLearningThis = (learn.isLearnModeActive && learn.selectedTarget == target)

        let cellId = col.identifier.rawValue

        if cellId == "Control" {
            let label = NSTextField(labelWithString: target.displayName)
            label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            label.textColor = isLearningThis ? NSColor.systemYellow : NSColor.white
            return label
        } else if cellId == "Type" {
            let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            typePopup.controlSize = .small
            typePopup.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            typePopup.tag = row
            typePopup.target = self
            typePopup.action = #selector(onTableRowTypeChanged(_:))

            let types = ControlInteractionType.allCases
            typePopup.addItems(withTitles: types.map { $0.rawValue })

            let currentType = mapping?.interactionType ?? target.defaultInteractionType
            if let idx = types.firstIndex(of: currentType) {
                typePopup.selectItem(at: idx)
            }
            return typePopup
        } else if cellId == "Option" {
            let currentType = mapping?.interactionType ?? target.defaultInteractionType
            if currentType == .button {
                let optPopup = NSPopUpButton(frame: .zero, pullsDown: false)
                optPopup.controlSize = .small
                optPopup.font = NSFont.systemFont(ofSize: 10, weight: .medium)
                optPopup.tag = row
                optPopup.target = self
                optPopup.action = #selector(onTableRowOptionChanged(_:))

                let modes = ButtonMode.allCases
                optPopup.addItems(withTitles: modes.map { $0.rawValue })
                let currentMode = mapping?.buttonMode ?? .toggle
                if let idx = modes.firstIndex(of: currentMode) {
                    optPopup.selectItem(at: idx)
                }
                return optPopup
            } else {
                let lbl = NSTextField(labelWithString: "—")
                lbl.alignment = .center
                lbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                lbl.textColor = NSColor(white: 0.40, alpha: 1.0)
                return lbl
            }
        } else if cellId == "Midi" {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 4
            stack.alignment = .centerY

            // Type Popup (CC / Note)
            let typePop = NSPopUpButton(frame: .zero, pullsDown: false)
            typePop.controlSize = .small
            typePop.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            typePop.tag = row
            typePop.addItems(withTitles: ["CC", "Note"])
            typePop.selectItem(at: (mapping?.type == .note) ? 1 : 0)
            typePop.target = self
            typePop.action = #selector(onTableRowMidiTypeChanged(_:))
            stack.addArrangedSubview(typePop)

            // Number Field (0..127)
            let numField = NSTextField()
            numField.controlSize = .small
            numField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            numField.alignment = .center
            numField.tag = row
            numField.placeholderString = "--"
            if let m = mapping {
                numField.stringValue = "\(m.number)"
                numField.textColor = NSColor.systemGreen
            } else {
                numField.stringValue = ""
                numField.textColor = NSColor(white: 0.5, alpha: 1.0)
            }
            numField.target = self
            numField.action = #selector(onTableRowMidiNumberChanged(_:))
            numField.translatesAutoresizingMaskIntoConstraints = false
            numField.widthAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(numField)

            // Channel Popup (All / Ch 1..16)
            let chPop = NSPopUpButton(frame: .zero, pullsDown: false)
            chPop.controlSize = .small
            chPop.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            chPop.tag = row
            var chTitles = ["All"]
            for c in 1...16 { chTitles.append("Ch \(c)") }
            chPop.addItems(withTitles: chTitles)
            if let m = mapping {
                chPop.selectItem(at: (m.channel == 255) ? 0 : Int(m.channel + 1))
            } else {
                chPop.selectItem(at: 0)
            }
            chPop.target = self
            chPop.action = #selector(onTableRowMidiChannelChanged(_:))
            stack.addArrangedSubview(chPop)

            return stack
        } else if cellId == "Learn" {
            let btn = NSButton(
                title: isLearningThis ? "● Learning..." : "Learn",
                target: self,
                action: #selector(onTableRowLearnClicked(_:))
            )
            btn.tag = row
            btn.bezelStyle = .inline
            btn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 4
            if isLearningThis {
                btn.layer?.backgroundColor = NSColor.systemPurple.cgColor
                btn.contentTintColor = NSColor.white
            } else {
                btn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.8).cgColor
                btn.contentTintColor = NSColor.systemTeal
            }
            return btn
        } else if cellId == "Reset" {
            let btn = NSButton(title: "Clear", target: self, action: #selector(onTableRowClearClicked(_:)))
            btn.tag = row
            btn.bezelStyle = .inline
            btn.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 4
            btn.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.7).cgColor
            btn.contentTintColor = mapping != nil ? NSColor.systemOrange : NSColor(white: 0.4, alpha: 1.0)
            btn.isEnabled = (mapping != nil)
            return btn
        }

        return nil
    }

    // MARK: - Actions (Mapping Table)
    @objc func onTableRowTypeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let types = ControlInteractionType.allCases
        let selectedType = types[min(max(0, sender.indexOfSelectedItem), types.count - 1)]

        let learn = RaneMidiLearnService.shared
        if var existing = learn.mappingFor(target: target) {
            existing.interactionType = selectedType
            learn.setMapping(for: target, mapping: existing)
        } else {
            // Create initial template mapping with this interaction type
            let defaultType: MidiMessageType = (selectedType == .button) ? .note : .cc
            let mapping = MidiMapping(type: defaultType, number: 0, channel: 255, interactionType: selectedType)
            learn.setMapping(for: target, mapping: mapping)
        }
        appendMidiLog("Controller Manager: [\(target.displayName)] Typ -> [\(selectedType.rawValue)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowOptionChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let modes = ButtonMode.allCases
        let selectedMode = modes[min(max(0, sender.indexOfSelectedItem), modes.count - 1)]

        let learn = RaneMidiLearnService.shared
        if var existing = learn.mappingFor(target: target) {
            existing.buttonMode = selectedMode
            learn.setMapping(for: target, mapping: existing)
        } else {
            let mapping = MidiMapping(type: .note, number: 0, channel: 255, interactionType: .button, buttonMode: selectedMode)
            learn.setMapping(for: target, mapping: mapping)
        }
        appendMidiLog("Controller Manager: [\(target.displayName)] Option (Modus) -> [\(selectedMode.rawValue)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowMidiTypeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let isNote = (sender.indexOfSelectedItem == 1)
        let newType: MidiMessageType = isNote ? .note : .cc

        let learn = RaneMidiLearnService.shared
        let existing = learn.mappingFor(target: target)
        let num = existing?.number ?? 0
        let ch = existing?.channel ?? 255
        let iType = existing?.interactionType ?? (isNote ? .button : .faderKnob)
        let bMode = existing?.buttonMode ?? .toggle

        let updated = MidiMapping(type: newType, number: num, channel: ch, interactionType: iType, buttonMode: bMode)
        learn.setMapping(for: target, mapping: updated)
        appendMidiLog("Controller Manager: [\(target.displayName)] Nachrichtentyp -> [\(isNote ? "Note" : "CC")]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowMidiNumberChanged(_ sender: NSTextField) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let num = UInt8(text), num <= 127 else {
            sender.stringValue = ""
            return
        }

        let learn = RaneMidiLearnService.shared
        let existing = learn.mappingFor(target: target)
        let mType = existing?.type ?? .cc
        let ch = existing?.channel ?? 255
        let iType = existing?.interactionType ?? target.defaultInteractionType

        let updated = MidiMapping(type: mType, number: num, channel: ch, interactionType: iType, buttonMode: existing?.buttonMode ?? .toggle)
        learn.setMapping(for: target, mapping: updated)
        appendMidiLog("Controller Manager: [\(target.displayName)] Nummer -> [\(num)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowMidiChannelChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let chIdx = sender.indexOfSelectedItem
        let channel: UInt8 = (chIdx == 0) ? 255 : UInt8(chIdx - 1)

        let learn = RaneMidiLearnService.shared
        let existing = learn.mappingFor(target: target)
        let mType = existing?.type ?? .cc
        let num = existing?.number ?? 0
        let iType = existing?.interactionType ?? target.defaultInteractionType
        let bMode = existing?.buttonMode ?? .toggle

        let updated = MidiMapping(type: mType, number: num, channel: channel, interactionType: iType, buttonMode: bMode)
        learn.setMapping(for: target, mapping: updated)
        let chDesc = (channel == 255) ? "All Channels" : "Kanal \(channel + 1)"
        appendMidiLog("Controller Manager: [\(target.displayName)] Kanal -> [\(chDesc)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }
    @objc func onTableRowLearnClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let learn = RaneMidiLearnService.shared

        if learn.isLearnModeActive && learn.selectedTarget == target {
            learn.isLearnModeActive = false
            learn.selectedTarget = nil
            appendMidiLog("MIDI Learn beendet.")
        } else {
            learn.isLearnModeActive = true
            learn.selectedTarget = target
            appendMidiLog("Controller Manager: [\(target.displayName)] im Learn-Modus – bewege jetzt Taste/Regler am Controller!")
        }
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowClearClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        RaneMidiLearnService.shared.clearMapping(for: target)
        appendMidiLog("Controller Manager: Mapping für [\(target.displayName)] gelöscht.")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    // MARK: - Actions (Out Mapping Table)
    @objc func onTableRowOutMidiTypeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let isNote = (sender.indexOfSelectedItem == 1)
        let newType: MidiMessageType = isNote ? .note : .cc

        let learn = RaneMidiLearnService.shared
        var existing = learn.outMappingFor(target: target) ?? MidiOutMapping(type: newType, number: 0, channel: 0)
        existing.type = newType
        learn.setOutMapping(for: target, mapping: existing)
        appendMidiLog("Controller Manager Out: [\(target.displayName)] Typ -> [\(isNote ? "Note" : "CC")]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowOutMidiNumberChanged(_ sender: NSTextField) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let num = UInt8(text), num <= 127 else {
            sender.stringValue = ""
            return
        }

        let learn = RaneMidiLearnService.shared
        var existing = learn.outMappingFor(target: target) ?? MidiOutMapping(type: .note, number: num, channel: 0)
        existing.number = num
        learn.setOutMapping(for: target, mapping: existing)
        appendMidiLog("Controller Manager Out: [\(target.displayName)] Nummer -> [\(num)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowOutMidiChannelChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let channel = UInt8(max(0, sender.indexOfSelectedItem))

        let learn = RaneMidiLearnService.shared
        var existing = learn.outMappingFor(target: target) ?? MidiOutMapping(type: .note, number: 0, channel: channel)
        existing.channel = channel
        learn.setOutMapping(for: target, mapping: existing)
        appendMidiLog("Controller Manager Out: [\(target.displayName)] Kanal -> [Ch \(channel + 1)]")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowOnValueChanged(_ sender: NSTextField) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let val = UInt8(text), val <= 127 else {
            sender.stringValue = "127"
            return
        }

        let learn = RaneMidiLearnService.shared
        var existing = learn.outMappingFor(target: target) ?? MidiOutMapping(type: .note, number: 0, channel: 0)
        existing.onValue = val
        learn.setOutMapping(for: target, mapping: existing)
        appendMidiLog("Controller Manager Out: [\(target.displayName)] ON Wert -> [\(val)]")
        RaneFlexFxService.shared.updateHardwareLeds()
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowOffValueChanged(_ sender: NSTextField) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let val = UInt8(text), val <= 127 else {
            sender.stringValue = "0"
            return
        }

        let learn = RaneMidiLearnService.shared
        var existing = learn.outMappingFor(target: target) ?? MidiOutMapping(type: .note, number: 0, channel: 0)
        existing.offValue = val
        learn.setOutMapping(for: target, mapping: existing)
        appendMidiLog("Controller Manager Out: [\(target.displayName)] OFF Wert -> [\(val)]")
        RaneFlexFxService.shared.updateHardwareLeds()
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onTableRowTestLedClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        let learn = RaneMidiLearnService.shared
        let midi = RaneMidiService.shared

        guard let outMap = learn.outMappingFor(target: target) else {
            appendMidiLog("Controller Manager Out: [\(target.displayName)] hat noch keine zugewiesene LED-Nummer!")
            return
        }

        let ch = (outMap.channel == 255) ? 0 : outMap.channel
        let vel = outMap.onValue
        if outMap.type == .note {
            midi.sendNoteOn(note: outMap.number, velocity: vel, channel: ch)
            appendMidiLog("LED Test: Note ON \(outMap.number) Vel=\(vel) Ch=\(ch + 1) gesendet")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let offVel = outMap.offValue
                if offVel > 0 {
                    midi.sendNoteOn(note: outMap.number, velocity: offVel, channel: ch)
                } else {
                    midi.sendNoteOff(note: outMap.number, channel: ch)
                }
            }
        } else {
            midi.sendCC(cc: outMap.number, value: vel, channel: ch)
            appendMidiLog("LED Test: CC #\(outMap.number) Val=\(vel) Ch=\(ch + 1) gesendet")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let offVel = outMap.offValue
                midi.sendCC(cc: outMap.number, value: offVel, channel: ch)
            }
        }
    }

    @objc func onTableRowClearOutClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < ControllerManagerRefs.currentRows.count else { return }
        let target = ControllerManagerRefs.currentRows[row]
        RaneMidiLearnService.shared.clearOutMapping(for: target)
        appendMidiLog("Controller Manager Out: LED-Mapping für [\(target.displayName)] gelöscht.")
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    @objc func onClearAllMappingsClicked() {
        if ControllerManagerRefs.isOutTableActive {
            RaneMidiLearnService.shared.clearAllOutMappings()
            appendMidiLog("Controller Manager: Alle LED Out-Mappings zurückgesetzt.")
        } else {
            RaneMidiLearnService.shared.clearAllMappings()
            appendMidiLog("Controller Manager: Alle MIDI In-Mappings zurückgesetzt.")
        }
        ControllerManagerRefs.mappingTableView?.reloadData()
    }

    // MARK: - Actions (Filter & Blacklist)
    @objc func onAddFilterRuleClicked() {
        guard let numField = ControllerManagerRefs.filterNumberField,
              let typePop = ControllerManagerRefs.filterTypePopup,
              let chPop = ControllerManagerRefs.filterChannelPopup else { return }

        let text = numField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let num = UInt8(text), num <= 127 else {
            let alert = NSAlert()
            alert.messageText = "Ungültige MIDI-Nummer"
            alert.informativeText = "Bitte eine Zahl von 0 bis 127 für CC oder Note eingeben."
            alert.runModal()
            return
        }

        let isCC = (typePop.indexOfSelectedItem == 0)
        let chIdx = chPop.indexOfSelectedItem
        let channel: UInt8 = (chIdx == 0) ? 255 : UInt8(chIdx - 1)
        let label = ControllerManagerRefs.filterLabelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let rule = MidiFilterRule(
            type: isCC ? .cc : .note,
            number: num,
            channel: channel,
            label: label
        )

        RaneMidiLearnService.shared.addFilterRule(rule)
        appendMidiLog("MIDI Filter: Regel hinzugefügt -> [\(rule.summary)]")
        ControllerManagerRefs.filterTableView?.reloadData()
    }

    @objc func onRemoveFilterRuleClicked(_ sender: NSButton) {
        let row = sender.tag
        let rules = RaneMidiLearnService.shared.filterRules
        guard row < rules.count else { return }
        let rule = rules[row]
        RaneMidiLearnService.shared.removeFilterRule(id: rule.id)
        appendMidiLog("MIDI Filter: Regel entfernt -> [\(rule.summary)]")
        ControllerManagerRefs.filterTableView?.reloadData()
    }

    @objc func onFilterPresetFadersClicked() {
        // Preset: Blacklist common mixer faders & switch noise CCs
        // Channels 1..4 Faders / DIP / Crossfader: CC 112..127 and CC 21..37
        let faderRules: [(UInt8, String)] = [
            (21, "PGM 1 Phono Sens"),
            (22, "PGM 1 Filter Res"),
            (23, "PGM 1 Rec Src"),
            (24, "PGM 2 Phono Sens"),
            (25, "PGM 2 Filter Res"),
            (26, "PGM 2 Rec Src"),
            (27, "PGM 3 Phono Sens"),
            (28, "PGM 3 Filter Res"),
            (29, "PGM 3 Rec Src"),
            (30, "PGM 4 Phono Sens"),
            (31, "PGM 4 Filter Res"),
            (32, "PGM 4 Rec Src"),
            (112, "PGM 1 Input Select"),
            (113, "PGM 2 Input Select"),
            (114, "PGM 3 Input Select"),
            (115, "PGM 4 Input Select"),
            (120, "Crossfader A / Post"),
            (121, "Crossfader B / Post"),
            (122, "Crossfader PGM 3"),
            (123, "Crossfader PGM 4")
        ]

        for (ccNum, name) in faderRules {
            let rule = MidiFilterRule(type: .cc, number: ccNum, channel: 255, label: name)
            RaneMidiLearnService.shared.addFilterRule(rule)
        }

        appendMidiLog("MIDI Filter: Sixty-Eight Mixer-Fader & Schalter (CC 21..32, 112..123) zur Blacklist hinzugefügt!")
        ControllerManagerRefs.filterTableView?.reloadData()
    }

    @objc func onClearAllFiltersClicked() {
        RaneMidiLearnService.shared.clearAllFilterRules()
        appendMidiLog("MIDI Filter: Alle Filterregeln gelöscht.")
        ControllerManagerRefs.filterTableView?.reloadData()
    }

    @objc func onMidiChannelChanged() {
        // Handled via Presets & CoreMIDI
    }
}
