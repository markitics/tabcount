import AppKit
import TabCountCore

final class TabCountChartView: NSView {
    private var samples: [TabSample] = []
    private var actualSamples: [TabSample] = []
    private var rangeStart = Date()
    private var rangeEnd = Date()
    private var now = Date()
    private var startLabel = "6a"
    private var endLabel = "now"
    private var hoverLocation: NSPoint?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 296).isActive = true
        heightAnchor.constraint(equalToConstant: 220).isActive = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(
        samples: [TabSample],
        actualSamples: [TabSample],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date,
        startLabel: String,
        endLabel: String
    ) {
        self.samples = samples
        self.actualSamples = actualSamples
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.now = now
        self.startLabel = startLabel
        self.endLabel = endLabel
        hoverLocation = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let layout = chartLayout()

        guard !samples.isEmpty,
              let maxValue = samples.map(\.tabs).max() else {
            drawLabels(in: layout.plotRect, chartRect: layout.chartRect, scale: nil)
            drawGrid(in: layout.chartRect, scale: nil)
            drawEmptyState(in: layout.chartRect)
            return
        }

        let scale = AxisScale.make(maxValue: maxValue)
        drawLabels(in: layout.plotRect, chartRect: layout.chartRect, scale: scale)
        drawGrid(in: layout.chartRect, scale: scale)
        drawLine(in: layout.chartRect, scaleMax: scale.scaleMax)
        drawDots(in: layout.chartRect, scaleMax: scale.scaleMax)
        drawCurrentTimeMarker(in: layout.chartRect)
        drawHoverAnnotation(in: layout.plotRect, chartRect: layout.chartRect, scale: scale)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let chartRect = chartLayout().chartRect
        hoverLocation = chartRect.contains(location) ? location : nil
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverLocation = nil
        needsDisplay = true
    }

    private func chartLayout() -> ChartLayout {
        let plotRect = bounds.insetBy(dx: 14, dy: 18)
            .insetBy(dx: 0, dy: 8)
        let leftAxisWidth: CGFloat = 72
        let rightAxisWidth: CGFloat = 14
        let chartRect = NSRect(
            x: plotRect.minX + leftAxisWidth,
            y: plotRect.minY + 20,
            width: plotRect.width - leftAxisWidth - rightAxisWidth,
            height: plotRect.height - 40
        )
        return ChartLayout(plotRect: plotRect, chartRect: chartRect)
    }

    private func drawLabels(in plotRect: NSRect, chartRect: NSRect, scale: AxisScale?) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]

        if let latest = samples.last {
            let latestLabel = NSString(string: Self.formatCount(latest.tabs))
            let latestLabelWidth = latestLabel.size(withAttributes: valueAttributes).width
            latestLabel.draw(
                at: NSPoint(x: plotRect.maxX - latestLabelWidth, y: plotRect.maxY - 12),
                withAttributes: valueAttributes
            )
        }

        drawTickLabels(in: chartRect, scale: scale, attributes: labelAttributes)

        NSString(string: startLabel).draw(
            at: NSPoint(x: chartRect.minX, y: plotRect.minY),
            withAttributes: labelAttributes
        )
        let endLabelWidth = NSString(string: endLabel).size(withAttributes: labelAttributes).width
        NSString(string: endLabel).draw(
            at: NSPoint(x: chartRect.maxX - endLabelWidth, y: plotRect.minY),
            withAttributes: labelAttributes
        )
    }

    private func drawTickLabels(
        in chartRect: NSRect,
        scale: AxisScale?,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let scale else {
            NSString(string: "0").draw(
                at: NSPoint(x: chartRect.minX - 12, y: chartRect.minY - 5),
                withAttributes: attributes
            )
            return
        }

        for tickValue in scale.tickValues {
            let label = NSString(string: Self.formatCount(tickValue))
            let labelSize = label.size(withAttributes: attributes)
            let y = yPosition(for: tickValue, in: chartRect, scaleMax: scale.scaleMax)
            let labelY = min(chartRect.maxY - labelSize.height / 2, max(chartRect.minY - 5, y - labelSize.height / 2))
            label.draw(
                at: NSPoint(x: chartRect.minX - labelSize.width - 6, y: labelY),
                withAttributes: attributes
            )
        }

        guard let maxMarkerValue = scale.maxMarkerValue else {
            return
        }

        let maxLabel = NSString(string: "max: \(Self.formatCount(maxMarkerValue))")
        let maxLabelSize = maxLabel.size(withAttributes: attributes)
        let maxY = yPosition(for: maxMarkerValue, in: chartRect, scaleMax: scale.scaleMax)
        let labelY = min(chartRect.maxY - maxLabelSize.height / 2, max(chartRect.minY, maxY - maxLabelSize.height / 2))
        maxLabel.draw(
            at: NSPoint(x: chartRect.minX - maxLabelSize.width - 6, y: labelY),
            withAttributes: attributes
        )
    }

    private func drawGrid(in chartRect: NSRect, scale: AxisScale?) {
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()

        let tickValues = scale?.tickValues ?? [0, 1, 2]
        let scaleMax = scale?.scaleMax ?? 2

        for tickValue in tickValues {
            let y = yPosition(for: tickValue, in: chartRect, scaleMax: scaleMax)
            let path = NSBezierPath()
            path.lineWidth = 0.5
            path.move(to: NSPoint(x: chartRect.minX, y: y))
            path.line(to: NSPoint(x: chartRect.maxX, y: y))
            path.stroke()
        }

        guard let scale,
              let maxMarkerValue = scale.maxMarkerValue else {
            return
        }

        let y = yPosition(for: maxMarkerValue, in: chartRect, scaleMax: scale.scaleMax)
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.move(to: NSPoint(x: chartRect.minX, y: y))
        path.line(to: NSPoint(x: chartRect.maxX, y: y))
        path.stroke()
    }

    private func drawEmptyState(in chartRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: NSPoint(x: chartRect.minX, y: chartRect.midY))
        path.line(to: NSPoint(x: chartRect.maxX, y: chartRect.midY))
        path.stroke()
    }

    private func drawLine(in chartRect: NSRect, scaleMax: Int) {
        let linePath = NSBezierPath()
        linePath.lineWidth = 2.4
        linePath.lineCapStyle = .round
        linePath.lineJoinStyle = .round

        let fillPath = NSBezierPath()
        let range = max(1, scaleMax)

        for (index, sample) in samples.enumerated() {
            let point = pointForSample(
                sample,
                in: chartRect,
                range: range
            )
            if index == 0 {
                linePath.move(to: point)
                fillPath.move(to: NSPoint(x: point.x, y: chartRect.minY))
                fillPath.line(to: point)
            } else {
                linePath.line(to: point)
                fillPath.line(to: point)
            }
        }

        if let last = samples.last {
            let lastPoint = pointForSample(last, in: chartRect, range: range)
            fillPath.line(to: NSPoint(x: lastPoint.x, y: chartRect.minY))
            fillPath.close()

            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            fillPath.fill()

            NSColor.controlAccentColor.setStroke()
            linePath.stroke()

            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6)).fill()
        }
    }

    private func drawDots(in chartRect: NSRect, scaleMax: Int) {
        let range = max(1, scaleMax)
        let dotColor = NSColor.controlAccentColor.blended(withFraction: 0.18, of: .labelColor)
            ?? NSColor.controlAccentColor
        dotColor.setFill()

        for sample in actualSamples {
            let point = pointForSample(sample, in: chartRect, range: range)
            NSBezierPath(
                ovalIn: NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
            ).fill()
        }
    }

    private func drawCurrentTimeMarker(in chartRect: NSRect) {
        let progress = Self.progress(for: now, rangeStart: rangeStart, rangeEnd: rangeEnd)
        let x = chartRect.minX + progress * chartRect.width
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: x, y: chartRect.minY))
        path.line(to: NSPoint(x: x, y: chartRect.maxY))
        path.stroke()
    }

    private func drawHoverAnnotation(in plotRect: NSRect, chartRect: NSRect, scale: AxisScale) {
        guard let hoverLocation,
              chartRect.contains(hoverLocation),
              let sample = nearestSample(to: hoverLocation, in: chartRect) else {
            return
        }

        let hoverX = min(chartRect.maxX, max(chartRect.minX, hoverLocation.x))
        NSColor.controlAccentColor.withAlphaComponent(0.48).setStroke()
        let hoverLine = NSBezierPath()
        hoverLine.lineWidth = 1
        hoverLine.move(to: NSPoint(x: hoverX, y: chartRect.minY))
        hoverLine.line(to: NSPoint(x: hoverX, y: chartRect.maxY))
        hoverLine.stroke()

        let samplePoint = pointForSample(sample, in: chartRect, range: scale.scaleMax)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: samplePoint.x - 4, y: samplePoint.y - 4, width: 8, height: 8)
        ).fill()

        let label = "\(Self.formatCount(sample.tabs)) tabs @ \(hoverTimestampLabel(for: sample.recordedAt))"
        drawHoverLabel(label, near: NSPoint(x: hoverX, y: samplePoint.y), in: plotRect, chartRect: chartRect)
    }

    private func drawHoverLabel(
        _ label: String,
        near point: NSPoint,
        in plotRect: NSRect,
        chartRect: NSRect
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let labelString = NSString(string: label)
        let labelSize = labelString.size(withAttributes: attributes)
        let paddingX: CGFloat = 7
        let paddingY: CGFloat = 4
        let bubbleSize = NSSize(
            width: labelSize.width + paddingX * 2,
            height: labelSize.height + paddingY * 2
        )

        let preferredX = point.x + 8
        let labelX = min(
            plotRect.maxX - bubbleSize.width,
            max(plotRect.minX, preferredX)
        )
        let preferredY: CGFloat
        if point.y > chartRect.midY {
            preferredY = point.y - bubbleSize.height - 9
        } else {
            preferredY = point.y + 9
        }
        let labelY = min(
            chartRect.maxY - bubbleSize.height,
            max(chartRect.minY, preferredY)
        )

        let bubbleRect = NSRect(origin: NSPoint(x: labelX, y: labelY), size: bubbleSize)
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        bubblePath.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        bubblePath.lineWidth = 0.5
        bubblePath.stroke()

        labelString.draw(
            at: NSPoint(x: bubbleRect.minX + paddingX, y: bubbleRect.minY + paddingY),
            withAttributes: attributes
        )
    }

    private func pointForSample(
        _ sample: TabSample,
        in chartRect: NSRect,
        range: Int
    ) -> NSPoint {
        let progress = Self.progress(for: sample.recordedAt, rangeStart: rangeStart, rangeEnd: rangeEnd)
        let x = chartRect.minX + progress * chartRect.width
        let normalized = CGFloat(max(0, sample.tabs)) / CGFloat(range)
        let y = chartRect.minY + normalized * chartRect.height
        return NSPoint(x: x, y: y)
    }

    private func nearestSample(to location: NSPoint, in chartRect: NSRect) -> TabSample? {
        let candidates = actualSamples.isEmpty ? samples : actualSamples
        guard !candidates.isEmpty else {
            return nil
        }

        let progress = min(1, max(0, (location.x - chartRect.minX) / max(1, chartRect.width)))
        let targetDate = rangeStart.addingTimeInterval(rangeEnd.timeIntervalSince(rangeStart) * TimeInterval(progress))
        return candidates.min { first, second in
            abs(first.recordedAt.timeIntervalSince(targetDate)) < abs(second.recordedAt.timeIntervalSince(targetDate))
        }
    }

    private func yPosition(for value: Int, in chartRect: NSRect, scaleMax: Int) -> CGFloat {
        let normalized = CGFloat(max(0, value)) / CGFloat(max(1, scaleMax))
        return chartRect.minY + normalized * chartRect.height
    }

    private func hoverTimestampLabel(for date: Date) -> String {
        if rangeEnd.timeIntervalSince(rangeStart) <= 36 * 60 * 60 {
            return Self.hoverTimeFormatter.string(from: date)
        }

        return Self.hoverDateTimeFormatter.string(from: date)
    }

    private static func formatCount(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func progress(for date: Date, rangeStart: Date, rangeEnd: Date) -> CGFloat {
        let duration = max(1, rangeEnd.timeIntervalSince(rangeStart))
        let elapsed = date.timeIntervalSince(rangeStart)
        return CGFloat(min(1, max(0, elapsed / duration)))
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let hoverTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let hoverDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private struct ChartLayout {
        let plotRect: NSRect
        let chartRect: NSRect
    }

    private struct AxisScale {
        let tickValues: [Int]
        let scaleMax: Int
        let maxMarkerValue: Int?

        static func make(maxValue: Int) -> AxisScale {
            let topAndStep = topTickAndStep(maxValue: maxValue)
            let topTick = topAndStep.topTick
            let step = max(1, topAndStep.step)
            var tickValues: [Int] = []
            var value = 0
            while value <= topTick {
                tickValues.append(value)
                value += step
            }
            if tickValues.last != topTick {
                tickValues.append(topTick)
            }

            let shouldShowMaxMarker = maxValue > topTick && Double(maxValue) / Double(max(1, topTick)) > 1.10
            return AxisScale(
                tickValues: tickValues,
                scaleMax: max(1, max(maxValue, topTick)),
                maxMarkerValue: shouldShowMaxMarker ? maxValue : nil
            )
        }

        private static func topTickAndStep(maxValue: Int) -> (topTick: Int, step: Int) {
            switch maxValue {
            case ...0:
                return (1, 1)
            case 1...14:
                return (10, 5)
            case 15...23:
                return (20, 10)
            case 24...33:
                return (30, 10)
            case 34...43:
                return (40, 20)
            case 44...53:
                return (50, 25)
            case 54...68:
                return (60, 20)
            case 69...83:
                return (80, 40)
            case 84...110:
                return (100, 50)
            case 111...125:
                return (120, 40)
            case 126...170:
                return (150, 50)
            case 171...240:
                return (200, 100)
            default:
                return scaledTopTickAndStep(maxValue: maxValue)
            }
        }

        private static func scaledTopTickAndStep(maxValue: Int) -> (topTick: Int, step: Int) {
            let maxDouble = Double(maxValue)
            let magnitude = pow(10, floor(log10(maxDouble)))
            let normalized = maxDouble / magnitude
            let topMultiplier: Double
            let stepMultiplier: Double

            switch normalized {
            case ...1.4:
                topMultiplier = 1
                stepMultiplier = 0.5
            case ...2.4:
                topMultiplier = 2
                stepMultiplier = 1
            case ...3.3:
                topMultiplier = 3
                stepMultiplier = 1
            case ...4.3:
                topMultiplier = 4
                stepMultiplier = 2
            case ...5.3:
                topMultiplier = 5
                stepMultiplier = 2.5
            case ...6.8:
                topMultiplier = 6
                stepMultiplier = 2
            case ...8.3:
                topMultiplier = 8
                stepMultiplier = 4
            default:
                topMultiplier = 10
                stepMultiplier = 5
            }

            let topTick = max(1, Int((topMultiplier * magnitude).rounded()))
            let step = max(1, Int((stepMultiplier * magnitude).rounded()))
            return (topTick, step)
        }
    }
}
