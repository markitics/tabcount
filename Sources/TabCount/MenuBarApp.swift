import AppKit
import TabCountCore

final class MenuBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let counter = ChromeCounter()
    private let store = HistoryStore()

    private let summaryItem = NSMenuItem()
    private let refreshedItem = NSMenuItem()
    private let chartRangeItem = NSMenuItem()
    private let chartHeaderView = NSView(frame: NSRect(x: 0, y: 0, width: 510, height: 34))
    private let chartTitleField = NSTextField(labelWithString: "Tabs since 6am")
    private let chartRangeControl = NSSegmentedControl()
    private let chartItem = NSMenuItem()
    private let chartView = TabCountChartView(frame: NSRect(x: 0, y: 0, width: 296, height: 220))
    private let tabLoadSettingsItem = NSMenuItem()
    private let tabLoadSettingsMenu = NSMenu(title: "Tab Load Settings")
    private let dataPathItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private var refreshTimer: Timer?
    private var lastSample: TabSample?
    private var chartRange = ChartRange.daySoFar
    private var availableChartRanges: [ChartRange] = [.daySoFar, .last24Hours, .last7Days]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        refreshNow()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 300,
            target: self,
            selector: #selector(refreshNow),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showInMenuBar()
        return true
    }

    private func configureMenu() {
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.image = nil

        summaryItem.isEnabled = false
        refreshedItem.isEnabled = false
        chartRangeItem.isEnabled = false
        chartRangeItem.view = chartHeaderView
        chartTitleField.frame = NSRect(x: 14, y: 8, width: 180, height: 18)
        chartTitleField.font = .systemFont(ofSize: 12, weight: .semibold)
        chartTitleField.textColor = .labelColor
        chartHeaderView.addSubview(chartTitleField)
        chartRangeControl.frame = NSRect(x: 214, y: 4, width: 282, height: 26)
        chartRangeControl.segmentStyle = .texturedRounded
        chartRangeControl.trackingMode = .selectOne
        chartRangeControl.target = self
        chartRangeControl.action = #selector(chartRangeChanged)
        chartHeaderView.addSubview(chartRangeControl)
        chartItem.isEnabled = false
        chartItem.view = chartView
        tabLoadSettingsItem.title = "Tab Load Settings"
        tabLoadSettingsItem.submenu = tabLoadSettingsMenu
        rebuildTabLoadSettingsMenu()
        dataPathItem.isEnabled = false
        errorItem.isEnabled = false

        let menu = NSMenu()
        menu.addItem(summaryItem)
        menu.addItem(refreshedItem)
        menu.addItem(chartRangeItem)
        menu.addItem(chartItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Data Folder", action: #selector(openDataFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Copy History Path", action: #selector(copyHistoryPath), keyEquivalent: "c"))
        menu.addItem(tabLoadSettingsItem)
        menu.addItem(NSMenuItem(title: "Open Privacy Settings", action: #selector(openPrivacySettings), keyEquivalent: ""))
        menu.addItem(dataPathItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide TabCount from Menu Bar", action: #selector(hideFromMenuBar), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Quit TabCount", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func refreshNow() {
        do {
            let sample = try counter.count()
            try store.record(sample)
            lastSample = sample
            updateMenu(sample: sample, error: nil)
        } catch {
            let fallback = fallbackSample(for: error)
            lastSample = fallback
            updateMenu(sample: fallback, error: String(describing: error))
        }
    }

    private func fallbackSample(for error: Error) -> TabSample? {
        if case ChromeCounterError.accessibilityRequiredForSuspiciousResult = error,
           let samples = try? store.loadSamples(),
           let lastReliableSample = samples.reversed().first(where: { sample in
               sample.windows != 1 || sample.tabs != 1
           }) {
            return lastReliableSample
        }

        return try? store.loadLatestSample()
    }

    @objc private func chartRangeChanged() {
        let index = chartRangeControl.selectedSegment
        guard availableChartRanges.indices.contains(index) else {
            return
        }

        chartRange = availableChartRanges[index]
        updateChart()
    }

    @objc private func editTabLoadEmoji(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let band = TabLoadBand(rawValue: rawValue) else {
            return
        }

        let preferences = TabLoadPreferences.load()
        guard let value = promptForValue(
            title: "Set \(band.title) Emoji",
            message: "Choose the emoji shown for \(band.description).",
            currentValue: preferences.emoji(for: band)
        ), !value.isEmpty else {
            return
        }

        TabLoadPreferences.saveEmoji(value, for: band)
        refreshTabLoadSettings()
    }

    @objc private func editTabLoadThreshold(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let threshold = TabLoadThreshold(rawValue: rawValue) else {
            return
        }

        let preferences = TabLoadPreferences.load()
        guard let value = promptForValue(
            title: "Set \(threshold.title)",
            message: threshold.message,
            currentValue: "\(preferences.value(for: threshold))"
        ), let intValue = Int(value), intValue > 0 else {
            return
        }

        TabLoadPreferences.saveThreshold(intValue, for: threshold)
        refreshTabLoadSettings()
    }

    @objc private func resetTabLoadSettings() {
        TabLoadPreferences.reset()
        refreshTabLoadSettings()
    }

    @objc private func openDataFolder() {
        try? store.ensureDirectoryExists()
        NSWorkspace.shared.open(store.directoryURL)
    }

    @objc private func copyHistoryPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.historyURL.path, forType: .string)
    }

    @objc private func openPrivacySettings() {
        PrivacyPermissions.openPrivacySettings()
    }

    @objc private func hideFromMenuBar() {
        statusItem.isVisible = false
    }

    private func showInMenuBar() {
        statusItem.isVisible = true
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateMenu(sample: TabSample?, error: String?) {
        if let sample {
            statusItem.button?.attributedTitle = statusTitle(for: sample)
            summaryItem.title = "\(formatCount(sample.windows)) Chrome windows, \(formatCount(sample.tabs)) tabs"
            refreshedItem.title = "Last refresh: \(Self.timeFormatter.string(from: sample.recordedAt))"
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "TabCount")
            summaryItem.title = "No tab count yet"
            refreshedItem.title = "Last refresh: never"
        }

        if let error {
            if sample != nil {
                errorItem.title = statusMessage(for: error)
            } else {
                errorItem.title = "Refresh failed: \(error)"
            }
            errorItem.isHidden = false
        } else {
            errorItem.title = ""
            errorItem.isHidden = true
        }

        dataPathItem.title = store.historyURL.path
        updateChart()
    }

    private func statusTitle(for sample: TabSample) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let tabLoadState = TabLoadPreferences.load().state(for: sample.tabs)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: tabLoadState.textColor,
        ]
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize + 1),
            .foregroundColor: tabLoadState.textColor,
        ]

        title.append(NSAttributedString(string: formatCount(sample.windows), attributes: textAttributes))
        title.append(NSAttributedString(string: " ", attributes: textAttributes))

        let attachment = NSTextAttachment()
        attachment.image = statusIconImage(sample: sample)
        attachment.bounds = NSRect(x: 0, y: -3, width: 28, height: 18)
        title.append(NSAttributedString(attachment: attachment))

        title.append(NSAttributedString(string: " \(formatCount(sample.tabs)) ", attributes: textAttributes))
        title.append(NSAttributedString(string: tabLoadState.emoji, attributes: emojiAttributes))
        return title
    }

    private func rebuildTabLoadSettingsMenu() {
        tabLoadSettingsMenu.removeAllItems()
        let preferences = TabLoadPreferences.load()

        for band in TabLoadBand.allCases {
            let item = NSMenuItem(
                title: "\(band.title) emoji: \(preferences.emoji(for: band))",
                action: #selector(editTabLoadEmoji(_:)),
                keyEquivalent: ""
            )
            item.representedObject = band.rawValue
            item.target = self
            tabLoadSettingsMenu.addItem(item)
        }

        tabLoadSettingsMenu.addItem(.separator())

        for threshold in TabLoadThreshold.allCases {
            let item = NSMenuItem(
                title: "\(threshold.title): \(preferences.value(for: threshold))",
                action: #selector(editTabLoadThreshold(_:)),
                keyEquivalent: ""
            )
            item.representedObject = threshold.rawValue
            item.target = self
            tabLoadSettingsMenu.addItem(item)
        }

        tabLoadSettingsMenu.addItem(.separator())
        let resetItem = NSMenuItem(
            title: "Reset Tab Load Defaults",
            action: #selector(resetTabLoadSettings),
            keyEquivalent: ""
        )
        resetItem.target = self
        tabLoadSettingsMenu.addItem(resetItem)
    }

    private func refreshTabLoadSettings() {
        rebuildTabLoadSettingsMenu()
        if let lastSample {
            statusItem.button?.attributedTitle = statusTitle(for: lastSample)
        }
    }

    private func promptForValue(title: String, message: String, currentValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = currentValue
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func statusMessage(for error: String) -> String {
        if error.contains("known undercount") || error.contains("Accessibility is not enabled") {
            return "Using last reliable count. Enable Accessibility for live refresh."
        }

        return "Using last reliable count. Latest refresh did not complete."
    }

    private func statusIconImage(sample: TabSample?) -> NSImage? {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let stackCount = stackCount(for: sample?.windows ?? 0)
        let fillFraction = tabFillFraction(for: sample)
        let fillHeight = size.height * fillFraction
        let fillRect = NSRect(x: 0, y: 0, width: size.width, height: fillHeight)
        let paths = (0..<stackCount).map { index -> NSBezierPath in
            let offset = CGFloat(stackCount - 1 - index) * 2.2
            let rect = NSRect(
                x: 2 + offset,
                y: 2 + offset * 0.55,
                width: 17,
                height: 11
            )
            return NSBezierPath(roundedRect: rect, xRadius: 2.4, yRadius: 2.4)
        }

        NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
        for path in paths {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            fillRect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.labelColor.withAlphaComponent(0.82).setStroke()
        for path in paths {
            path.lineWidth = 1.25
            path.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func stackCount(for windows: Int) -> Int {
        switch windows {
        case ..<10:
            return 1
        case ..<30:
            return 2
        case ..<55:
            return 3
        case ..<80:
            return 4
        default:
            return 5
        }
    }

    private func tabFillFraction(for sample: TabSample?) -> CGFloat {
        guard let sample else {
            return 0.25
        }

        let samples = (try? store.loadSamples()) ?? []
        let maxTabs = max(sample.tabs, samples.map(\.tabs).max() ?? sample.tabs, 1)
        return CGFloat(sample.tabs) / CGFloat(maxTabs)
    }

    private func formatCount(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func updateChart() {
        let now = Date()
        let allSamples = (try? store.loadSamples()) ?? []
        availableChartRanges = ChartRange.availableRanges(for: allSamples, now: now)
        if !availableChartRanges.contains(chartRange) {
            chartRange = availableChartRanges.last ?? .daySoFar
        }
        updateRangeControl()

        let chartData = samplesForChart(
            allSamples: allSamples,
            range: chartRange,
            now: now
        )
        chartView.update(
            samples: chartData.samples,
            actualSamples: chartData.actualSamples,
            rangeStart: chartData.start,
            rangeEnd: chartData.end,
            now: now,
            startLabel: chartData.startLabel,
            endLabel: chartData.endLabel
        )
        chartTitleField.stringValue = chartData.title
    }

    private func updateRangeControl() {
        chartRangeControl.segmentCount = availableChartRanges.count
        var controlWidth: CGFloat = 0

        for (index, range) in availableChartRanges.enumerated() {
            chartRangeControl.setLabel(range.label, forSegment: index)
            chartRangeControl.setWidth(range.width, forSegment: index)
            controlWidth += range.width
        }

        chartRangeControl.selectedSegment = availableChartRanges.firstIndex(of: chartRange) ?? 0
        let headerWidth = chartHeaderView.bounds.width
        chartRangeControl.frame = NSRect(
            x: headerWidth - controlWidth - 14,
            y: 4,
            width: controlWidth,
            height: 26
        )
        chartTitleField.frame = NSRect(
            x: 14,
            y: 8,
            width: max(80, chartRangeControl.frame.minX - 24),
            height: 18
        )
    }

    private func samplesForChart(
        allSamples: [TabSample],
        range: ChartRange,
        now: Date
    ) -> ChartData {
        let sortedSamples = allSamples.sorted { $0.recordedAt < $1.recordedAt }
        let calendar = Calendar.current

        switch range {
        case .daySoFar:
            let start = Self.sessionStart(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return ChartData(
                samples: samplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                actualSamples: actualSamplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                start: start,
                end: end,
                title: "Tabs since 6am",
                startLabel: "6a",
                endLabel: "6a"
            )
        case .last24Hours:
            let start = now.addingTimeInterval(-24 * 60 * 60)
            return ChartData(
                samples: samplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                actualSamples: actualSamplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                start: start,
                end: now,
                title: "Tabs over 24 hours",
                startLabel: "24h",
                endLabel: "now"
            )
        case .last7Days:
            let start = now.addingTimeInterval(-7 * 24 * 60 * 60)
            return ChartData(
                samples: samplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                actualSamples: actualSamplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                start: start,
                end: now,
                title: "Tabs over 7 days",
                startLabel: "7d",
                endLabel: "now"
            )
        case .last30Days:
            let start = now.addingTimeInterval(-30 * 24 * 60 * 60)
            return ChartData(
                samples: samplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                actualSamples: actualSamplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                start: start,
                end: now,
                title: "Tabs over 30 days",
                startLabel: "30d",
                endLabel: "now"
            )
        case .yearToDate:
            let start = calendar.date(
                from: calendar.dateComponents([.year], from: now)
            ) ?? now
            return ChartData(
                samples: samplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                actualSamples: actualSamplesInRange(sortedSamples: sortedSamples, start: start, end: now),
                start: start,
                end: now,
                title: "Tabs this year",
                startLabel: "YTD",
                endLabel: "now"
            )
        case .allTime:
            let first = sortedSamples.first?.recordedAt ?? now
            return ChartData(
                samples: sortedSamples,
                actualSamples: sortedSamples,
                start: first,
                end: now,
                title: "Tabs all time",
                startLabel: ChartRange.allTimeLabel(for: sortedSamples, now: now),
                endLabel: "now"
            )
        }
    }

    private func samplesInRange(
        sortedSamples: [TabSample],
        start: Date,
        end: Date
    ) -> [TabSample] {
        var rangeSamples = sortedSamples.filter { sample in
            sample.recordedAt >= start && sample.recordedAt <= end
        }

        if let startSample = sortedSamples.last(where: { $0.recordedAt <= start }) {
            rangeSamples.insert(
                TabSample(
                    recordedAt: start,
                    windows: startSample.windows,
                    tabs: startSample.tabs
                ),
                at: 0
            )
        } else if let firstSample = rangeSamples.first, firstSample.recordedAt > start {
            rangeSamples.insert(
                TabSample(
                    recordedAt: start,
                    windows: firstSample.windows,
                    tabs: firstSample.tabs
                ),
                at: 0
            )
        }

        return rangeSamples
    }

    private func actualSamplesInRange(
        sortedSamples: [TabSample],
        start: Date,
        end: Date
    ) -> [TabSample] {
        sortedSamples.filter { sample in
            sample.recordedAt >= start && sample.recordedAt <= end
        }
    }

    private func samplesForSparkline(
        allSamples: [TabSample],
        sessionStart: Date,
        now: Date
    ) -> [TabSample] {
        let sortedSamples = allSamples.sorted { $0.recordedAt < $1.recordedAt }
        var sessionSamples = sortedSamples.filter { sample in
            sample.recordedAt >= sessionStart && sample.recordedAt <= now
        }

        if let startSample = sortedSamples.last(where: { $0.recordedAt <= sessionStart }) {
            sessionSamples.insert(
                TabSample(
                    recordedAt: sessionStart,
                    windows: startSample.windows,
                    tabs: startSample.tabs
                ),
                at: 0
            )
        } else if let firstSample = sessionSamples.first, firstSample.recordedAt > sessionStart {
            sessionSamples.insert(
                TabSample(
                    recordedAt: sessionStart,
                    windows: firstSample.windows,
                    tabs: firstSample.tabs
                ),
                at: 0
            )
        }

        return sessionSamples
    }

    private static func sessionStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current

        let startOfDay = calendar.startOfDay(for: date)
        let sixAM = calendar.date(byAdding: .hour, value: 6, to: startOfDay) ?? startOfDay
        if date >= sixAM {
            return sixAM
        }

        return calendar.date(byAdding: .day, value: -1, to: sixAM) ?? sixAM
    }

    private static func progress(for date: Date, sessionStart: Date, sessionEnd: Date) -> CGFloat {
        let duration = max(1, sessionEnd.timeIntervalSince(sessionStart))
        let elapsed = date.timeIntervalSince(sessionStart)
        return CGFloat(min(1, max(0, elapsed / duration)))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}

private struct ChartData {
    let samples: [TabSample]
    let actualSamples: [TabSample]
    let start: Date
    let end: Date
    let title: String
    let startLabel: String
    let endLabel: String
}

private enum ChartRange: Equatable {
    case daySoFar
    case last24Hours
    case last7Days
    case last30Days
    case yearToDate
    case allTime

    var label: String {
        switch self {
        case .daySoFar:
            return "Today"
        case .last24Hours:
            return "24h"
        case .last7Days:
            return "7d"
        case .last30Days:
            return "30d"
        case .yearToDate:
            return "YTD"
        case .allTime:
            return "All"
        }
    }

    var width: CGFloat {
        switch self {
        case .daySoFar:
            return 62
        case .yearToDate:
            return 46
        default:
            return 42
        }
    }

    static func availableRanges(for samples: [TabSample], now: Date) -> [ChartRange] {
        let sortedSamples = samples.sorted { $0.recordedAt < $1.recordedAt }
        var ranges: [ChartRange] = [.daySoFar, .last24Hours, .last7Days]

        guard let firstSample = sortedSamples.first else {
            return ranges
        }

        let historySpan = now.timeIntervalSince(firstSample.recordedAt)
        if historySpan > 30 * 24 * 60 * 60 {
            ranges.append(.last30Days)
        }

        let calendar = Calendar.current
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        if firstSample.recordedAt < startOfYear {
            ranges.append(.yearToDate)
        }

        if historySpan > 7 * 24 * 60 * 60 {
            ranges.append(.allTime)
        }

        return ranges
    }

    static func allTimeLabel(for samples: [TabSample], now: Date) -> String {
        guard let firstSample = samples.first else {
            return "all"
        }

        let days = max(1, Int(ceil(now.timeIntervalSince(firstSample.recordedAt) / (24 * 60 * 60))))
        return "\(days)d"
    }
}

private struct TabLoadPreferences {
    private enum Key {
        static let calmEmoji = "tabLoad.calmEmoji"
        static let focusedEmoji = "tabLoad.focusedEmoji"
        static let activeEmoji = "tabLoad.activeEmoji"
        static let overloadedEmoji = "tabLoad.overloadedEmoji"
        static let calmBelow = "tabLoad.calmBelow"
        static let focusedThrough = "tabLoad.focusedThrough"
        static let overloadedAt = "tabLoad.overloadedAt"
    }

    let calmEmoji: String
    let focusedEmoji: String
    let activeEmoji: String
    let overloadedEmoji: String
    let calmBelow: Int
    let focusedThrough: Int
    let overloadedAt: Int

    static func load() -> TabLoadPreferences {
        let defaults = UserDefaults.standard
        return TabLoadPreferences(
            calmEmoji: defaults.string(forKey: Key.calmEmoji) ?? "🧘",
            focusedEmoji: defaults.string(forKey: Key.focusedEmoji) ?? "🤓",
            activeEmoji: defaults.string(forKey: Key.activeEmoji) ?? "🏃",
            overloadedEmoji: defaults.string(forKey: Key.overloadedEmoji) ?? "🤯",
            calmBelow: defaults.integerValue(forKey: Key.calmBelow, defaultValue: 12),
            focusedThrough: defaults.integerValue(forKey: Key.focusedThrough, defaultValue: 50),
            overloadedAt: defaults.integerValue(forKey: Key.overloadedAt, defaultValue: 200)
        )
    }

    static func saveEmoji(_ emoji: String, for band: TabLoadBand) {
        UserDefaults.standard.set(emoji, forKey: key(for: band))
    }

    static func saveThreshold(_ value: Int, for threshold: TabLoadThreshold) {
        UserDefaults.standard.set(value, forKey: key(for: threshold))
    }

    static func reset() {
        let defaults = UserDefaults.standard
        [
            Key.calmEmoji,
            Key.focusedEmoji,
            Key.activeEmoji,
            Key.overloadedEmoji,
            Key.calmBelow,
            Key.focusedThrough,
            Key.overloadedAt,
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    func emoji(for band: TabLoadBand) -> String {
        switch band {
        case .calm:
            return calmEmoji
        case .focused:
            return focusedEmoji
        case .active:
            return activeEmoji
        case .overloaded:
            return overloadedEmoji
        }
    }

    func value(for threshold: TabLoadThreshold) -> Int {
        switch threshold {
        case .calmBelow:
            return calmBelow
        case .focusedThrough:
            return focusedThrough
        case .overloadedAt:
            return overloadedAt
        }
    }

    func state(for tabs: Int) -> TabLoadState {
        if tabs < calmBelow {
            return TabLoadState(emoji: calmEmoji, textColor: .labelColor)
        }

        if tabs <= focusedThrough {
            return TabLoadState(emoji: focusedEmoji, textColor: .labelColor)
        }

        if tabs < overloadedAt {
            return TabLoadState(emoji: activeEmoji, textColor: .systemOrange)
        }

        return TabLoadState(emoji: overloadedEmoji, textColor: .systemRed)
    }

    private static func key(for band: TabLoadBand) -> String {
        switch band {
        case .calm:
            return Key.calmEmoji
        case .focused:
            return Key.focusedEmoji
        case .active:
            return Key.activeEmoji
        case .overloaded:
            return Key.overloadedEmoji
        }
    }

    private static func key(for threshold: TabLoadThreshold) -> String {
        switch threshold {
        case .calmBelow:
            return Key.calmBelow
        case .focusedThrough:
            return Key.focusedThrough
        case .overloadedAt:
            return Key.overloadedAt
        }
    }
}

private struct TabLoadState {
    let emoji: String
    let textColor: NSColor
}

private enum TabLoadBand: String, CaseIterable {
    case calm
    case focused
    case active
    case overloaded

    var title: String {
        switch self {
        case .calm:
            return "Calm"
        case .focused:
            return "Focused"
        case .active:
            return "Active"
        case .overloaded:
            return "Overloaded"
        }
    }

    var description: String {
        switch self {
        case .calm:
            return "low tab counts"
        case .focused:
            return "moderate tab counts"
        case .active:
            return "high tab counts"
        case .overloaded:
            return "very high tab counts"
        }
    }
}

private enum TabLoadThreshold: String, CaseIterable {
    case calmBelow
    case focusedThrough
    case overloadedAt

    var title: String {
        switch self {
        case .calmBelow:
            return "Calm below"
        case .focusedThrough:
            return "Focused through"
        case .overloadedAt:
            return "Overloaded at"
        }
    }

    var message: String {
        switch self {
        case .calmBelow:
            return "Tabs below this number use the calm emoji."
        case .focusedThrough:
            return "Tabs up to this number use the focused emoji."
        case .overloadedAt:
            return "Tabs at or above this number use the overloaded emoji."
        }
    }
}

private extension UserDefaults {
    func integerValue(forKey key: String, defaultValue: Int) -> Int {
        guard object(forKey: key) != nil else {
            return defaultValue
        }

        return integer(forKey: key)
    }
}
