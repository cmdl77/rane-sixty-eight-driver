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
    var mainLayoutStack: NSStackView!
    var headerStackView: NSStackView!

    // Mini HUD Mode State
    var isMiniHudMode: Bool = false
    var fullWindowFrame: NSRect = .zero
    var miniHudContainer: NSView?

    // Page Views
    var prefsView: NSView!
    var pgmView: NSView!
    var flexFxView: NSView!
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
    var cpuStatusLabel: NSTextField!
    var sysLogTextView: NSTextView!
    var oledGreetingLine1Field: NSTextField!
    var oledGreetingLine2Field: NSTextField!

    // Header Badges & Controls
    var headerCpuBadge: CpuBadgeView!
    var headerLinkButton: NSButton!
    var headerPresetButton: NSButton?

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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.init(window: window)
        MainWindowController.shared = self
        window.delegate = self

        setupModernUI()
        setupMidiListener()
        refreshStatus()
        if RaneMidiService.shared.isConnected {
            RaneMidiService.shared.showOledGreeting(durationSeconds: 5.0)
        }

        RaneCpuService.shared.onCpuUpdate = { [weak self] usage in
            DispatchQueue.main.async {
                self?.headerCpuBadge?.update(percent: usage)
                self?.updateDiagnosticsCpu(usage: usage)
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            if self?.segmentedNav?.selectedSegment == 3 {
                self?.refreshStatus()
            }
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
        onOledGreetingFieldEdited()

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

        headerCpuBadge?.updateTooltip()
        headerCpuBadge?.update(percent: RaneCpuService.shared.systemCpuUsage)

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

        // Solid Dark Slate Background (0% GPU/WindowServer blur overhead)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(red: 0.137, green: 0.141, blue: 0.157, alpha: 1.0).cgColor

        // Main Layout Stack - Breitere Ränder (38 pt links/rechts)
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 54, left: 38, bottom: 26, right: 38)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        self.mainLayoutStack = mainStack

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
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

        headerCpuBadge = CpuBadgeView()
        headerCpuBadge.onClick = { [weak self] in
            guard let self = self else { return }
            self.segmentedNav?.selectedSegment = 4
            self.onTabChanged()
        }
        headerCpuBadge.update(percent: RaneCpuService.shared.systemCpuUsage)
        headerStack.addArrangedSubview(headerCpuBadge)

        // Global Ableton Link Toggle Button (between CPU load and Mini-HUD)
        let linkBtn = NSButton(title: " 🔗 Ableton Link: ON ", target: self, action: #selector(onLinkToggleClicked))
        linkBtn.bezelStyle = .inline
        linkBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        linkBtn.wantsLayer = true
        linkBtn.layer?.cornerRadius = 6
        linkBtn.layer?.borderWidth = 1.0
        linkBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.22).cgColor
        linkBtn.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
        linkBtn.contentTintColor = NSColor.systemGreen
        linkBtn.translatesAutoresizingMaskIntoConstraints = false
        linkBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        headerStack.addArrangedSubview(linkBtn)
        self.headerLinkButton = linkBtn

        // Mini HUD Mode Toggle Button
        let hudBtn = NSButton(title: "🎛 Mini-HUD ▾", target: self, action: #selector(toggleMiniHudMode))
        hudBtn.bezelStyle = .inline
        hudBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        hudBtn.wantsLayer = true
        hudBtn.layer?.cornerRadius = 6
        hudBtn.layer?.backgroundColor = NSColor(red: 0.16, green: 0.32, blue: 0.48, alpha: 0.6).cgColor
        hudBtn.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.6).cgColor
        hudBtn.layer?.borderWidth = 1.0
        hudBtn.contentTintColor = NSColor.systemTeal
        hudBtn.translatesAutoresizingMaskIntoConstraints = false
        hudBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        headerStack.addArrangedSubview(hudBtn)

        mainStack.addArrangedSubview(headerStack)
        headerStack.centerXAnchor.constraint(equalTo: mainStack.centerXAnchor).isActive = true
        self.headerStackView = headerStack

        // 2. Segmented Navigation Bar (Über die gesamte Fensterbreite mit Padding)
        segmentedNav = NSSegmentedControl(labels: [
            Localization.tr(en: "🎛 Mixer Audio", de: "🎛 Mixer Audio"),
            Localization.tr(en: "🎚 PGM Channels 1–4", de: "🎚 PGM Kanäle 1–4"),
            Localization.tr(en: "⚡️ FlexFX Engine", de: "⚡️ FlexFX Engine"),
            Localization.tr(en: "🎹 Controller & MIDI", de: "🎹 Controller & MIDI"),
            Localization.tr(en: "⚙️ System Status", de: "⚙️ System Status")
        ], trackingMode: .selectOne, target: self, action: #selector(onTabChanged))
        segmentedNav.selectedSegment = 0
        segmentedNav.segmentStyle = .texturedRounded
        segmentedNav.segmentDistribution = .fillEqually
        segmentedNav.controlSize = .regular
        segmentedNav.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        mainStack.addArrangedSubview(segmentedNav)
        segmentedNav.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        segmentedNav.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

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
        flexFxView = buildFlexFxPage()
        midiView = buildMidiPage()
        systemView = buildSystemPage()

        for page in [prefsView, pgmView, flexFxView, midiView, systemView] {
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

        // 4. Grouped Horizontal Slim Audio VU-Meter Rack (eingebettet in dunklem Inset-Fenster mit 14pt Padding)
        ioMonitorBar = RaneIOMonitorBarView()
        let meterInsetCard = ioMonitorBar.wrapInInsetCard(
            cornerRadius: 12,
            padding: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        )
        mainStack.addArrangedSubview(meterInsetCard)
        meterInsetCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        meterInsetCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        onTabChanged()
        setControlsEnabled(RaneMidiService.shared.isConnected)
    }

    // MARK: - Navigation & Dynamische Fensterhöhe
    @objc func onTabChanged() {
        let sel = segmentedNav.selectedSegment
        let pages = [prefsView, pgmView, flexFxView, midiView, systemView]

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

        if sel == 4 {
            refreshStatus()
        }
        updateWindowHeightForTab(index: sel, animated: true)
    }

    private func targetWindowHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return 715   // Mixer Audio
        case 1: return 675   // PGM Channels 1–4
        case 2: return 720   // FlexFX Engine
        case 3: return 720   // Controller & MIDI
        case 4: return 715   // System Status
        default: return 700
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

    // MARK: - NSWindowDelegate (Pause/Resume on Minimize / Hide)
    func windowDidMiniaturize(_ notification: Notification) {
        RaneMeterService.shared.pause()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        RaneMeterService.shared.resume()
    }

    func windowWillClose(_ notification: Notification) {
        RaneMeterService.shared.pause()
    }

    // MARK: - Header Presets Menu Action
    @objc func onHeaderPresetClicked(_ sender: NSButton) {
        let menu = buildPresetsMenu()
        let location = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    // Dedicated Floating Mini HUD Window (Panel)
    private var miniHudPanel: NSPanel?

    // MARK: - Always-on-Top Floating Mini-Bar Mode (HUD Overlay)
    @objc func toggleMiniHudMode() {
        guard let window = self.window else { return }

        isMiniHudMode.toggle()

        if isMiniHudMode {
            // Create or show dedicated floating HUD panel
            if miniHudPanel == nil {
                let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
                let hudWidth: CGFloat = 950
                let hudHeight: CGFloat = 48
                let targetX = screen.visibleFrame.midX - (hudWidth / 2.0)
                let targetY = screen.visibleFrame.maxY - hudHeight - 8
                let hudFrame = NSRect(x: targetX, y: targetY, width: hudWidth, height: hudHeight)

                let panel = NSPanel(
                    contentRect: hudFrame,
                    styleMask: [.nonactivatingPanel, .borderless],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "Rane FlexFX HUD"
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.hidesOnDeactivate = false
                panel.isMovableByWindowBackground = true

                let hudView = createMiniHudView()
                panel.contentView = hudView
                self.miniHudPanel = panel
            }

            // Hide large main control panel window
            window.orderOut(nil)

            // Show HUD panel floating over Traktor / Fullscreen
            miniHudPanel?.orderFrontRegardless()
            updateMiniHudUI()
        } else {
            // Hide HUD panel and restore main control panel
            miniHudPanel?.orderOut(nil)
            window.makeKeyAndOrderFront(nil)
            updateWindowHeightForTab(index: segmentedNav?.selectedSegment ?? 2, animated: false)
        }
    }

    // References for Mini HUD live controls
    struct MiniHudRefs {
        static var effectBadge: NSTextField!
        static var toggleButton: NSButton!
        static var beatLabel: NSTextField!
        static var bpmLabel: NSTextField!
        static var linkBadge: NSTextField!
        static var prePostBadge: NSButton!
        static var dryWetLabel: NSTextField!
        static var depthLabel: NSTextField!
        static var sendMeter: HorizontalLedBarView!
        static var returnMeter: HorizontalLedBarView!
    }

    private func createMiniHudView() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.98).cgColor
        bar.layer?.cornerRadius = 8
        bar.layer?.borderWidth = 1.2
        bar.layer?.borderColor = NSColor(red: 0.30, green: 0.36, blue: 0.45, alpha: 0.9).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor)
        ])

        // 1. Drag Handle / Brand Tag
        let brandTag = NSTextField(labelWithString: "RANE FX")
        brandTag.font = NSFont.systemFont(ofSize: 11, weight: .black)
        brandTag.textColor = NSColor(white: 0.65, alpha: 1.0)
        stack.addArrangedSubview(brandTag)

        // 2. Effect Name
        let fxName = NSTextField(labelWithString: "ECHO")
        fxName.font = NSFont.systemFont(ofSize: 14, weight: .black)
        fxName.textColor = NSColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1.0)
        stack.addArrangedSubview(fxName)
        MiniHudRefs.effectBadge = fxName

        // 3. FlexFX On/Off Button
        let onBtn = NSButton(title: "ON", target: self, action: #selector(onFlexFxToggleClicked))
        onBtn.bezelStyle = .inline
        onBtn.font = NSFont.systemFont(ofSize: 11, weight: .black)
        onBtn.wantsLayer = true
        onBtn.layer?.cornerRadius = 5
        onBtn.layer?.borderWidth = 1.0
        onBtn.translatesAutoresizingMaskIntoConstraints = false
        onBtn.widthAnchor.constraint(equalToConstant: 42).isActive = true
        onBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(onBtn)
        MiniHudRefs.toggleButton = onBtn

        // 4. Beat Division
        let beatLbl = NSTextField(labelWithString: "1/2")
        beatLbl.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        beatLbl.textColor = NSColor.white
        stack.addArrangedSubview(beatLbl)
        MiniHudRefs.beatLabel = beatLbl

        // Beat buttons
        let prevBtn = NSButton(title: "◀", target: self, action: #selector(onPrevBeatClicked))
        prevBtn.bezelStyle = .inline
        prevBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        stack.addArrangedSubview(prevBtn)

        let nextBtn = NSButton(title: "▶", target: self, action: #selector(onNextBeatClicked))
        nextBtn.bezelStyle = .inline
        nextBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        stack.addArrangedSubview(nextBtn)

        // 5. BPM Display (Handled cleanly via Ableton Link)
        let bpmLbl = NSTextField(labelWithString: "124.0 BPM")
        bpmLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .heavy)
        bpmLbl.textColor = NSColor(red: 0.20, green: 0.95, blue: 0.85, alpha: 1.0)
        stack.addArrangedSubview(bpmLbl)
        MiniHudRefs.bpmLabel = bpmLbl

        // 6. Link Badge
        let linkLbl = NSTextField(labelWithString: "● LINK: 0")
        linkLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        linkLbl.textColor = NSColor.systemGreen
        stack.addArrangedSubview(linkLbl)
        MiniHudRefs.linkBadge = linkLbl

        // 7. Pre/Post Toggle Button
        let ppBtn = NSButton(title: "POST", target: self, action: #selector(onPrePostToggled))
        ppBtn.bezelStyle = .inline
        ppBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        ppBtn.wantsLayer = true
        ppBtn.layer?.cornerRadius = 4
        ppBtn.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        ppBtn.layer?.borderColor = NSColor.systemBlue.cgColor
        ppBtn.layer?.borderWidth = 1.0
        ppBtn.contentTintColor = NSColor.systemBlue
        stack.addArrangedSubview(ppBtn)
        MiniHudRefs.prePostBadge = ppBtn

        // 8. D/W & Depth Labels
        let dwLbl = NSTextField(labelWithString: "W: 50%")
        dwLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        dwLbl.textColor = NSColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1.0)
        stack.addArrangedSubview(dwLbl)
        MiniHudRefs.dryWetLabel = dwLbl

        let dpLbl = NSTextField(labelWithString: "FB: 65%")
        dpLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        dpLbl.textColor = NSColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1.0)
        stack.addArrangedSubview(dpLbl)
        MiniHudRefs.depthLabel = dpLbl

        // 9. Mini Peak Meters (Send Ch 9/10 & Return Ch 9/10)
        let metersStack = NSStackView()
        metersStack.orientation = .vertical
        metersStack.spacing = 2
        metersStack.translatesAutoresizingMaskIntoConstraints = false
        metersStack.widthAnchor.constraint(equalToConstant: 55).isActive = true

        let sMeter = HorizontalLedBarView()
        sMeter.translatesAutoresizingMaskIntoConstraints = false
        sMeter.heightAnchor.constraint(equalToConstant: 4).isActive = true
        metersStack.addArrangedSubview(sMeter)
        MiniHudRefs.sendMeter = sMeter

        let rMeter = HorizontalLedBarView()
        rMeter.translatesAutoresizingMaskIntoConstraints = false
        rMeter.heightAnchor.constraint(equalToConstant: 4).isActive = true
        metersStack.addArrangedSubview(rMeter)
        MiniHudRefs.returnMeter = rMeter

        stack.addArrangedSubview(metersStack)

        // 10. Expand Button (Back to Full Control Panel)
        let expandBtn = NSButton(title: "⤢ FULL", target: self, action: #selector(toggleMiniHudMode))
        expandBtn.bezelStyle = .inline
        expandBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        expandBtn.wantsLayer = true
        expandBtn.layer?.cornerRadius = 5
        expandBtn.layer?.backgroundColor = NSColor(white: 0.30, alpha: 0.8).cgColor
        expandBtn.contentTintColor = NSColor.white
        stack.addArrangedSubview(expandBtn)

        return bar
    }

    func updateMiniHudUI() {
        guard isMiniHudMode else { return }
        let flex = RaneFlexFxService.shared

        MiniHudRefs.effectBadge?.stringValue = flex.currentEffect.displayName
        MiniHudRefs.beatLabel?.stringValue = flex.currentDivision.label
        MiniHudRefs.bpmLabel?.stringValue = "\(String(format: "%.1f", flex.bpm)) BPM"
        MiniHudRefs.dryWetLabel?.stringValue = "W: \(Int(flex.dryWet * 100))%"
        MiniHudRefs.depthLabel?.stringValue = "FB: \(Int(flex.depth * 100))%"

        if !flex.isModuleEnabled {
            MiniHudRefs.effectBadge?.stringValue = "BYPASS"
            MiniHudRefs.toggleButton?.title = "PWR OFF"
            MiniHudRefs.toggleButton?.layer?.backgroundColor = NSColor(red: 0.35, green: 0.12, blue: 0.12, alpha: 0.9).cgColor
            MiniHudRefs.toggleButton?.contentTintColor = NSColor.systemRed
        } else if flex.isEnabled {
            MiniHudRefs.toggleButton?.title = "ON"
            MiniHudRefs.toggleButton?.layer?.backgroundColor = NSColor.systemYellow.cgColor
            MiniHudRefs.toggleButton?.contentTintColor = NSColor.black
        } else {
            MiniHudRefs.toggleButton?.title = "OFF"
            MiniHudRefs.toggleButton?.layer?.backgroundColor = NSColor(white: 0.20, alpha: 0.8).cgColor
            MiniHudRefs.toggleButton?.contentTintColor = NSColor(white: 0.6, alpha: 1.0)
        }

        if flex.isPreFader {
            MiniHudRefs.prePostBadge?.title = "PRE"
            MiniHudRefs.prePostBadge?.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
            MiniHudRefs.prePostBadge?.layer?.borderColor = NSColor.systemOrange.cgColor
            MiniHudRefs.prePostBadge?.contentTintColor = NSColor.systemOrange
        } else {
            MiniHudRefs.prePostBadge?.title = "POST"
            MiniHudRefs.prePostBadge?.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
            MiniHudRefs.prePostBadge?.layer?.borderColor = NSColor.systemBlue.cgColor
            MiniHudRefs.prePostBadge?.contentTintColor = NSColor.systemBlue
        }

        if flex.isLinkEnabled {
            MiniHudRefs.linkBadge?.stringValue = "● LINK: \(flex.linkPeers)"
            MiniHudRefs.linkBadge?.textColor = flex.linkPeers > 0 ? NSColor.systemGreen : NSColor.systemOrange
        } else {
            MiniHudRefs.linkBadge?.stringValue = "○ STANDALONE"
            MiniHudRefs.linkBadge?.textColor = NSColor(white: 0.6, alpha: 1.0)
        }

        // Live Audio Peaks
        MiniHudRefs.sendMeter?.setLevel(linearPeak: flex.liveSendPeak, linearHold: flex.liveSendPeak, clipped: flex.liveSendPeak >= 1.0)
        MiniHudRefs.returnMeter?.setLevel(linearPeak: flex.liveReturnPeak, linearHold: flex.liveReturnPeak, clipped: flex.liveReturnPeak >= 1.0)
    }
}
