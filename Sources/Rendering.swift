import AppKit

enum Palette {
    static let accent = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    static let warn = NSColor(srgbRed: 0.96, green: 0.72, blue: 0.26, alpha: 1)
    static let crit = NSColor(srgbRed: 0.95, green: 0.33, blue: 0.31, alpha: 1)
    static let track = NSColor(white: 1, alpha: 0.16)
    static let dim = NSColor(white: 1, alpha: 0.55)

    // Token chart hues: deliberately not the status colours used by the limit gauges.
    static let tokensIn = NSColor(srgbRed: 0.45, green: 0.68, blue: 0.96, alpha: 1)
    static let tokensOut = NSColor(srgbRed: 0.45, green: 0.85, blue: 0.70, alpha: 1)

    static func color(for percent: Double) -> NSColor {
        percent >= 90 ? crit : percent >= 70 ? warn : accent
    }
}

func percentText(_ percent: Double) -> String {
    String(format: "%.0f%%", percent)
}

func tokenText(_ count: Double) -> String {
    if count >= 999_500 { return String(format: "%.1fM", count / 1_000_000) }
    if count >= 1000 { return String(format: "%.0fk", count / 1000) }
    return String(format: "%.0f", count)
}

func resetText(_ date: Date?) -> String {
    guard let date else { return "" }
    let seconds = date.timeIntervalSinceNow
    if seconds <= 0 { return "reset" }
    if seconds < 86400 {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "resets in \(minutes / 60)h \(minutes % 60)m" : "resets in \(max(1, minutes))m"
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE HH:mm"
    return "resets \(formatter.string(from: date))"
}

private func drawBar(in rect: NSRect, percent: Double) {
    let radius = rect.height / 2
    Palette.track.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    guard percent > 0 else { return }
    var fill = rect
    fill.size.width = max(rect.height, rect.width * CGFloat(percent / 100))
    Palette.color(for: percent).setFill()
    NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
}

private func drawText(_ string: String, font: NSFont, color: NSColor, in rect: NSRect,
                      align: NSTextAlignment = .left) {
    let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let size = text.size()
    var x = rect.minX
    if align == .right { x = rect.maxX - size.width }
    if align == .center { x = rect.midX - size.width / 2 }
    text.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
}

/// The small always-visible Control Strip tile. The system fixes the tile width (~54pt) and
/// scales larger images down, so this is drawn at the size it is actually shown:
/// two rows of "5h 42%" with a hairline gauge under each.
func compactImage(usage: Usage?, note: String?) -> NSImage {
    let size = NSSize(width: 44, height: 28)
    return NSImage(size: size, flipped: false) { bounds in
        guard let usage, !usage.limits.isEmpty else {
            drawText(note == nil ? "…" : "⚠︎", font: .systemFont(ofSize: 14, weight: .medium),
                     color: Palette.dim, in: bounds, align: .center)
            return true
        }
        let rows = Array(usage.limits.prefix(2))
        let rowHeight = bounds.height / CGFloat(rows.count)
        for (index, limit) in rows.enumerated() {
            let row = NSRect(x: 0, y: bounds.height - rowHeight * CGFloat(index + 1),
                             width: bounds.width, height: rowHeight)
            let text = NSRect(x: row.minX, y: row.minY + 3, width: row.width, height: row.height - 3)
            drawText(limit.short, font: .systemFont(ofSize: 9, weight: .medium), color: Palette.dim,
                     in: text)
            drawText(percentText(limit.percent),
                     font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                     color: Palette.color(for: limit.percent), in: text, align: .right)
            drawBar(in: NSRect(x: row.minX, y: row.minY + 0.5, width: row.width, height: 2),
                    percent: limit.percent)
        }
        return true
    }
}

/// One gauge in the expanded Touch Bar: name + reset time on top, bar + percentage below.
final class LimitView: NSView {
    private let limit: Limit

    init(limit: Limit) {
        self.limit = limit
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 30))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let top = NSRect(x: 0, y: 15, width: bounds.width, height: 14)
        let bottom = NSRect(x: 0, y: 1, width: bounds.width, height: 14)
        drawText(limit.label, font: .systemFont(ofSize: 11, weight: .semibold), color: .white, in: top)
        drawText(resetText(limit.resetsAt), font: .systemFont(ofSize: 9), color: Palette.dim,
                 in: top, align: .right)
        drawBar(in: NSRect(x: 0, y: bottom.midY - 3, width: bounds.width - 44, height: 6),
                percent: limit.percent)
        drawText(percentText(limit.percent),
                 font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                 color: Palette.color(for: limit.percent), in: bottom, align: .right)
    }
}

/// Hourly tokens over the last 24 hours as a mirrored bar chart: input grows up from the
/// centre line, output grows down. Each half has its own scale, since input is far larger.
final class TokenView: NSView {
    private let series: TokenSeries

    init(series: TokenSeries) {
        self.series = series
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 30))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let chartWidth: CGFloat = 126
        let slot = chartWidth / CGFloat(TokenSeries.hours)
        let middle = bounds.midY
        let reach: CGFloat = 13
        let maxInput = max(series.input.max() ?? 0, 1)
        let maxOutput = max(series.output.max() ?? 0, 1)

        for hour in 0..<TokenSeries.hours {
            let x = CGFloat(hour) * slot
            let width = slot - 1
            Palette.track.setFill()
            NSRect(x: x, y: middle - 0.5, width: width, height: 1).fill()

            if series.input[hour] > 0 {
                let height = max(1.5, reach * CGFloat(series.input[hour] / maxInput))
                Palette.tokensIn.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: middle + 1, width: width, height: height),
                             xRadius: 1, yRadius: 1).fill()
            }
            if series.output[hour] > 0 {
                let height = max(1.5, reach * CGFloat(series.output[hour] / maxOutput))
                Palette.tokensOut.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: middle - 1 - height, width: width, height: height),
                             xRadius: 1, yRadius: 1).fill()
            }
        }

        let labels = NSRect(x: chartWidth + 8, y: 0, width: bounds.width - chartWidth - 8, height: bounds.height)
        let top = NSRect(x: labels.minX, y: 15, width: labels.width, height: 14)
        let bottom = NSRect(x: labels.minX, y: 1, width: labels.width, height: 14)
        let small = NSFont.systemFont(ofSize: 9, weight: .medium)
        let value = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        drawText("in", font: small, color: Palette.dim, in: top)
        drawText(tokenText(series.totalInput), font: value, color: Palette.tokensIn, in: top, align: .right)
        drawText("out", font: small, color: Palette.dim, in: bottom)
        drawText(tokenText(series.totalOutput), font: value, color: Palette.tokensOut, in: bottom, align: .right)
    }
}
