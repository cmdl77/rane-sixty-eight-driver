/* SPDX-License-Identifier: MIT */
/* MainWindowController.swift - Primary window controller and UI lifecycle */

import Cocoa

class MainWindowController: NSWindowController, NSWindowDelegate {
    static var shared: MainWindowController?

    // Top Bar Components
    var headerStatusBadge: NSTextField!
    var segmentedNav: NSSegmentedControl!
    var contentContainer: NSView!
    var ioMonitorBar: RaneIOMonitorBarView!

    // Page Views
    var prefsView: NSView!
    var pgmView: NSView!
    var midiView: NSView!
    var systemView: NSView!
    var activePageConstraints: [NSLayoutConstraint] = []

    // Preferences Controls (Tab 1)
    var lowToneSlider: NSSlider!
    var highToneSlider: NSSlider!
    var lowToneBadge: NSTextField!
    var highToneBadge: NSTextField!
    var usb6RecordSegment: NSSegmentedControl!
    var backlightSwitch: NSSwitch!
    var controlPointSegment: NSSegmentedControl!
    var lcdContrastSlider: NSSlider!
    var lcdContrastBadge: NSTextField!
    var bufferSizePopup: NSPopUpButton!
    var usbStatusBadge: NSTextField!

    // PGM 1-4 Controls (Tab 2)
    var channels: [PgmChannelControls] = []

    // MIDI Settings (Tab 3)
    var midiOutPopup: NSPopUpButton!
    var midiInPopup: NSPopUpButton!
    var midiLogTextView: NSTextView!
    var midiLogScrollView: NSScrollView!
    var midiLogBuffer: [String] = []
    var isMidiLogFlushScheduled = false
    let midiLogLock = NSLock()
    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    // Mixer Quittierung & Entkopplung (Anti-Stutter System)
    var pendingChanges: [UInt8: PendingControlChange] = [:]
    let pendingChangesLock = NSLock()

    // Slider Throttling (Schutz vor USB-Überlastung beim Ziehen)
    var lastSliderSendTime: [UInt8: TimeInterval] = [:]
    var pendingSliderValues: [UInt8: UInt8] = [:]
    var sliderThrottleTimer: Timer?
    var lastLowVal: UInt8 = 255
    var lastHighVal: UInt8 = 255
    var lastLcdVal: UInt8 = 255

    // System Status (Tab 4)
    var statusLabel: NSTextField!
    var kextStatusLabel: NSTextField!
    var agentStatusLabel: NSTextField!
    var deviceStatusLabel: NSTextField!
    var firmwareStatusLabel: NSTextField!
    var sysLogTextView: NSTextView!

    // LED Light Check
    var ledTestButton: NSButton?
    var isLedTestRunning = false
    var ledTestTimer: Timer?
    var ledTestStep = 0

    // Hardware Stress Test
    var stressTestButton: NSButton?
    var isStressTestRunning = false
    var stressTestProcess: Process?

    // Diagnostics & Refresh Timer
    var isRefreshing = false
    var timer: Timer?
    let driverPath = "/Library/Audio/Plug-Ins/HAL/RaneHAL.driver"

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
                              styleMask: mask,
                              backing: .buffered,
                              defer: false)
        window.title = "Rane Sixty-Eight Control Panel"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.137, green: 0.141, blue: 0.157, alpha: 1.0)
        window.center()
        window.minSize = NSSize(width: 880, height: 580)

        self.init(window: window)
        MainWindowController.shared = self
        window.delegate = self

        setupModernUI()
        setupMidiListener()
        refreshStatus()

        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func rebuildUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        // 1. Snapshot current UI state
        let currentTab = segmentedNav?.selectedSegment ?? 0
        let lowVal = lowToneSlider?.integerValue ?? 64
        let highVal = highToneSlider?.integerValue ?? 64
        let lcdVal = lcdContrastSlider?.integerValue ?? 64
        let backlightState = backlightSwitch?.state ?? .on
        let controlPointIdx = controlPointSegment?.selectedSegment ?? 0
        let usb6Seg = usb6RecordSegment?.selectedSegment ?? 0
        let bufSizeIdx = bufferSizePopup?.indexOfSelectedItem ?? 2

        let pgmSensIndices = channels.map { $0.phonoPopup.indexOfSelectedItem }
        let pgmResIndices = channels.map { $0.resonanceSegment.selectedSegment }
        let pgmRecIndices = channels.map { $0.recordSegment.selectedSegment }
        let pgmXfaderBadges = channels.map { ($0.crossfaderBadge.stringValue, $0.crossfaderBadge.textColor, $0.crossfaderBadge.layer?.backgroundColor) }
        let pgmInputTypeBadges = channels.map { ($0.inputTypeBadge.stringValue, $0.inputTypeBadge.textColor, $0.inputTypeBadge.layer?.backgroundColor) }
        let pgmSourceBadges = channels.map { ($0.sourceBadge.stringValue, $0.sourceBadge.textColor, $0.sourceBadge.layer?.backgroundColor) }

        let outMidiIdx = midiOutPopup?.indexOfSelectedItem ?? 0
        let inMidiIdx = midiInPopup?.indexOfSelectedItem ?? 16
        let midiLogText = midiLogTextView?.string ?? ""
        let sysLogText = sysLogTextView?.string ?? ""

        // 2. Remove old views
        contentView.subviews.forEach { $0.removeFromSuperview() }

        // 3. Rebuild UI with new localization
        setupModernUI()

        // 4. Restore state
        segmentedNav.selectedSegment = currentTab
        onTabChanged()

        lowToneSlider.integerValue = lowVal
        let lowDb = (Double(lowVal) - 64.0) / 64.0 * 6.0
        lowToneBadge.stringValue = String(format: "%+.1f dB", lowDb)

        highToneSlider.integerValue = highVal
        let highDb = (Double(highVal) - 64.0) / 64.0 * 6.0
        highToneBadge.stringValue = String(format: "%+.1f dB", highDb)

        lcdContrastSlider.integerValue = lcdVal
        let pct = Int(round(Double(lcdVal) / 127.0 * 100.0))
        lcdContrastBadge.stringValue = "\(pct)%"

        backlightSwitch.state = backlightState

        controlPointSegment.selectedSegment = controlPointIdx
        usb6RecordSegment.selectedSegment = usb6Seg
        if bufSizeIdx < bufferSizePopup.numberOfItems {
            bufferSizePopup.selectItem(at: bufSizeIdx)
        }

        for (i, ch) in channels.enumerated() {
            if i < pgmSensIndices.count && pgmSensIndices[i] < ch.phonoPopup.numberOfItems {
                ch.phonoPopup.selectItem(at: pgmSensIndices[i])
            }
            if i < pgmResIndices.count {
                ch.resonanceSegment.selectedSegment = pgmResIndices[i]
            }
            if i < pgmRecIndices.count {
                ch.recordSegment.selectedSegment = pgmRecIndices[i]
            }
            if i < pgmXfaderBadges.count {
                ch.crossfaderBadge.stringValue = pgmXfaderBadges[i].0
                ch.crossfaderBadge.textColor = pgmXfaderBadges[i].1
                ch.crossfaderBadge.layer?.backgroundColor = pgmXfaderBadges[i].2
            }
            if i < pgmInputTypeBadges.count {
                ch.inputTypeBadge.stringValue = pgmInputTypeBadges[i].0
                ch.inputTypeBadge.textColor = pgmInputTypeBadges[i].1
                ch.inputTypeBadge.layer?.backgroundColor = pgmInputTypeBadges[i].2
            }
            if i < pgmSourceBadges.count {
                ch.sourceBadge.stringValue = pgmSourceBadges[i].0
                ch.sourceBadge.textColor = pgmSourceBadges[i].1
                ch.sourceBadge.layer?.backgroundColor = pgmSourceBadges[i].2
            }
        }

        if outMidiIdx < midiOutPopup.numberOfItems { midiOutPopup.selectItem(at: outMidiIdx) }
        if inMidiIdx < midiInPopup.numberOfItems { midiInPopup.selectItem(at: inMidiIdx) }

        if let tv = midiLogTextView, !midiLogText.isEmpty {
            tv.string = midiLogText
            if let scroll = midiLogScrollView, let doc = scroll.documentView {
                let clip = scroll.contentView
                let maxY = max(0, doc.bounds.height - clip.bounds.height)
                clip.scroll(to: NSPoint(x: 0, y: maxY))
                scroll.reflectScrolledClipView(clip)
            }
        }
        if let stv = sysLogTextView, !sysLogText.isEmpty {
            stv.string = sysLogText
        }

        if RaneMidiService.shared.isConnected {
            headerStatusBadge.stringValue = Localization.tr(en: "  ● Connected  ", de: "  ● Verbunden  ")
            headerStatusBadge.textColor = NSColor.systemGreen
            headerStatusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        } else {
            headerStatusBadge.stringValue = Localization.tr(en: "  ● Disconnected  ", de: "  ● Getrennt  ")
            headerStatusBadge.textColor = NSColor.systemRed
            headerStatusBadge.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        }

        let ledTitle = isLedTestRunning ? Localization.tr(en: "⏹ Stop LED Check", de: "⏹ LED-Test Beenden")
                                        : Localization.tr(en: "💡 Mixer LED Light Test", de: "💡 Mixer LED-Lichtcheck")
        ledTestButton?.title = ledTitle
        ledTestButton?.isEnabled = RaneMidiService.shared.isConnected

        let stressTitle = isStressTestRunning ? Localization.tr(en: "⏹ Stop Stress Test", de: "⏹ Stresstest Beenden")
                                              : Localization.tr(en: "🔥 Hardware Stress Test", de: "🔥 Hardware-Stresstest")
        stressTestButton?.title = stressTitle
        stressTestButton?.isEnabled = RaneMidiService.shared.isConnected

        refreshStatus()
    }

    // MARK: - Setup UI
    private func setupModernUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        // Visual Effect Background (Deep dark sleek slate)
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .underWindowBackground
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(visualEffect)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        // Main Layout Stack - Breitere Ränder (38 pt links/rechts)
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 54, left: 38, bottom: 26, right: 38)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])

        // 1. Header Bar with Top-Down Rane Sixty-Eight Mixer Image & Single-Line Title (Zentriert)
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 10
        headerStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let mixerView = NSImageView()
        mixerView.wantsLayer = true
        mixerView.layer?.cornerRadius = 6
        mixerView.layer?.masksToBounds = true
        mixerView.layer?.borderColor = NSColor(white: 0.35, alpha: 0.9).cgColor
        mixerView.layer?.borderWidth = 1.0

        if let path = Bundle.main.path(forResource: "mixer_topdown", ofType: "jpg"),
           let img = NSImage(contentsOfFile: path) {
            mixerView.image = img
        } else if let resPath = Bundle.main.resourcePath,
                  let img = NSImage(contentsOfFile: (resPath as NSString).appendingPathComponent("mixer_topdown.jpg")) {
            mixerView.image = img
        } else {
            let execUrl = URL(fileURLWithPath: CommandLine.arguments[0])
            let candidate = execUrl.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/mixer_topdown.jpg")
            if let img = NSImage(contentsOf: candidate) {
                mixerView.image = img
            }
        }
        mixerView.imageScaling = .scaleAxesIndependently
        mixerView.translatesAutoresizingMaskIntoConstraints = false
        mixerView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        mixerView.widthAnchor.constraint(equalToConstant: 36).isActive = true
        headerStack.addArrangedSubview(mixerView)

        let brandTitleLabel = NSTextField(labelWithString: "RANE SIXTY-EIGHT")
        brandTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .black)
        brandTitleLabel.textColor = NSColor.white
        headerStack.addArrangedSubview(brandTitleLabel)

        let panelSubtitleLabel = NSTextField(labelWithString: "Control Panel v2.0.0")
        panelSubtitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .light)
        panelSubtitleLabel.textColor = NSColor(white: 0.82, alpha: 1.0)
        headerStack.addArrangedSubview(panelSubtitleLabel)

        // Kleiner Abstand vor dem Status Verbunden
        let smallGap = NSView()
        smallGap.translatesAutoresizingMaskIntoConstraints = false
        smallGap.widthAnchor.constraint(equalToConstant: 12).isActive = true
        headerStack.addArrangedSubview(smallGap)

        headerStatusBadge = createBadge(text: Localization.tr(en: "● Offline", de: "● Offline"), isConnected: false)
        headerStack.addArrangedSubview(headerStatusBadge)

        mainStack.addArrangedSubview(headerStack)
        headerStack.centerXAnchor.constraint(equalTo: mainStack.centerXAnchor).isActive = true

        // 2. Segmented Navigation Bar (Zentriert)
        segmentedNav = NSSegmentedControl(labels: [
            Localization.tr(en: "  🎛 Mixer Audio  ", de: "  🎛 Mixer Audio  "),
            Localization.tr(en: "  🎚 PGM Channels 1–4  ", de: "  🎚 PGM Kanäle 1–4  "),
            Localization.tr(en: "  🎹 Live MIDI  ", de: "  🎹 Live MIDI  "),
            Localization.tr(en: "  ⚙️ System Status  ", de: "  ⚙️ System Status  ")
        ], trackingMode: .selectOne, target: self, action: #selector(onTabChanged))
        segmentedNav.selectedSegment = 0
        segmentedNav.segmentStyle = .texturedRounded
        segmentedNav.controlSize = .regular
        segmentedNav.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        mainStack.addArrangedSubview(segmentedNav)
        segmentedNav.centerXAnchor.constraint(equalTo: mainStack.centerXAnchor).isActive = true

        // 3. Content Container (Füllt volle Breite)
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(contentContainer)
        contentContainer.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        contentContainer.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Build Pages
        prefsView = buildPreferencesPage()
        pgmView = buildPgmPage()
        midiView = buildMidiPage()
        systemView = buildSystemPage()

        for page in [prefsView, pgmView, midiView, systemView] {
            guard let p = page else { continue }
            p.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(p)
            NSLayoutConstraint.activate([
                p.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                p.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                p.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
            ])
            p.isHidden = true
        }

        // 4. Grouped Horizontal Slim Audio VU-Meter Rack (waagerecht schmal darunter)
        ioMonitorBar = RaneIOMonitorBarView()
        mainStack.addArrangedSubview(ioMonitorBar)
        ioMonitorBar.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        ioMonitorBar.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        onTabChanged()
        setControlsEnabled(RaneMidiService.shared.isConnected)
    }

    // MARK: - Navigation & Dynamische Fensterhöhe
    @objc func onTabChanged() {
        let sel = segmentedNav.selectedSegment
        let pages = [prefsView, pgmView, midiView, systemView]

        NSLayoutConstraint.deactivate(activePageConstraints)
        activePageConstraints.removeAll()

        for (i, p) in pages.enumerated() {
            guard let page = p else { continue }
            let isSelected = (i == sel)
            page.isHidden = !isSelected
            if isSelected {
                let bottomC = page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
                activePageConstraints.append(bottomC)
                bottomC.isActive = true
            }
        }

        if sel == 3 {
            refreshStatus()
        }
        updateWindowHeightForTab(index: sel, animated: true)
    }

    private func targetWindowHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return 680   // Mixer Audio
        case 1: return 650   // PGM Channels 1–4
        case 2: return 665   // Live MIDI
        case 3: return 660   // System Status
        default: return 670
        }
    }

    private func updateWindowHeightForTab(index: Int, animated: Bool = true) {
        guard let window = self.window else { return }
        let targetHeight = targetWindowHeight(for: index)
        var frame = window.frame
        if abs(frame.size.height - targetHeight) > 2 {
            let heightDiff = targetHeight - frame.size.height
            frame.origin.y -= heightDiff
            frame.size.height = targetHeight
            window.setFrame(frame, display: true, animate: animated)
        }
    }
}
