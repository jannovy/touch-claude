import AppKit

/// Colours and metrics for one place the gauges are drawn: the Touch Bar (always dark, 30pt
/// tall) or the menu bar (22pt tall, light or dark depending on the wallpaper).
struct Style {
    var primary = NSColor.white
    var dim = NSColor(white: 1, alpha: 0.55)
    var track = NSColor(white: 1, alpha: 0.16)
    var accent = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    var warn = NSColor(srgbRed: 0.96, green: 0.72, blue: 0.26, alpha: 1)
    var crit = NSColor(srgbRed: 0.95, green: 0.33, blue: 0.31, alpha: 1)
    // Token chart hues: deliberately not the status colours used by the limit gauges.
    var tokensIn = NSColor(srgbRed: 0.45, green: 0.68, blue: 0.96, alpha: 1)
    var tokensOut = NSColor(srgbRed: 0.45, green: 0.85, blue: 0.70, alpha: 1)

    var height: CGFloat = 30
    var limitWidth: CGFloat = 190
    var chartWidth: CGFloat = 126
    var tokenWidth: CGFloat = 190
    var labelFont: CGFloat = 11
    var smallFont: CGFloat = 9
    var valueFont: CGFloat = 11
    var percentFont: CGFloat = 12
    var percentWidth: CGFloat = 44
    var barHeight: CGFloat = 6
    var shortResets = false

    var compactSize = NSSize(width: 44, height: 28)
    var compactLabelFont: CGFloat = 9
    var compactValueFont: CGFloat = 11
    var compactBarHeight: CGFloat = 2

    static let touchBar = Style()

    static func menuBar(dark: Bool) -> Style {
        var style = Style()
        if !dark {
            style.primary = NSColor(white: 0, alpha: 0.85)
            style.dim = NSColor(white: 0, alpha: 0.55)
            style.track = NSColor(white: 0, alpha: 0.14)
            style.accent = NSColor(srgbRed: 0.78, green: 0.38, blue: 0.25, alpha: 1)
            style.warn = NSColor(srgbRed: 0.80, green: 0.53, blue: 0.0, alpha: 1)
            style.crit = NSColor(srgbRed: 0.83, green: 0.20, blue: 0.18, alpha: 1)
            style.tokensIn = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.82, alpha: 1)
            style.tokensOut = NSColor(srgbRed: 0.10, green: 0.58, blue: 0.42, alpha: 1)
        }
        style.height = 22
        style.limitWidth = 96
        style.chartWidth = 60
        style.tokenWidth = 108
        style.labelFont = 9
        style.smallFont = 8
        style.valueFont = 9.5
        style.percentFont = 10
        style.percentWidth = 34
        style.barHeight = 4
        style.shortResets = true
        style.compactSize = NSSize(width: 42, height: 22)
        style.compactLabelFont = 8
        style.compactValueFont = 9.5
        style.compactBarHeight = 1.5
        return style
    }

    func color(for percent: Double) -> NSColor {
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

/// `short` drops the "resets" wording where there is no room for it (menu bar).
func resetText(_ date: Date?, short: Bool = false) -> String {
    guard let date else { return "" }
    let seconds = date.timeIntervalSinceNow
    if seconds <= 0 { return "reset" }
    if seconds < 86400 {
        let minutes = Int(seconds / 60)
        let left = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(1, minutes))m"
        return short ? left : "resets in \(left)"
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE HH:mm"
    let day = formatter.string(from: date)
    return short ? day : "resets \(day)"
}

private func drawBar(in rect: NSRect, percent: Double, style: Style) {
    let radius = rect.height / 2
    style.track.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    guard percent > 0 else { return }
    var fill = rect
    fill.size.width = max(rect.height, rect.width * CGFloat(percent / 100))
    style.color(for: percent).setFill()
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

/// Splits a block into its two text rows.
private func rows(of bounds: NSRect) -> (top: NSRect, bottom: NSRect) {
    let half = bounds.height / 2
    return (NSRect(x: bounds.minX, y: bounds.minY + half, width: bounds.width, height: half - 1),
            NSRect(x: bounds.minX, y: bounds.minY + 1, width: bounds.width, height: half - 1))
}

/// The small two-row summary, "5h 42%" over "7d 74%" with a hairline gauge under each.
/// In the Control Strip the system fixes the tile width (~54pt) and scales larger images down,
/// so this is drawn at the size it is actually shown.
func compactImage(usage: Usage?, note: String?, style: Style = .touchBar) -> NSImage {
    NSImage(size: style.compactSize, flipped: false) { bounds in
        guard let usage, !usage.limits.isEmpty else {
            drawText(note == nil ? "…" : "⚠︎", font: .systemFont(ofSize: 14, weight: .medium),
                     color: style.dim, in: bounds, align: .center)
            return true
        }
        let limits = Array(usage.limits.prefix(2))
        let rowHeight = bounds.height / CGFloat(limits.count)
        let inset = style.compactBarHeight + 1
        for (index, limit) in limits.enumerated() {
            let row = NSRect(x: 0, y: bounds.height - rowHeight * CGFloat(index + 1),
                             width: bounds.width, height: rowHeight)
            let text = NSRect(x: row.minX, y: row.minY + inset, width: row.width, height: row.height - inset)
            drawText(limit.short, font: .systemFont(ofSize: style.compactLabelFont, weight: .medium),
                     color: style.dim, in: text)
            drawText(percentText(limit.percent),
                     font: .monospacedDigitSystemFont(ofSize: style.compactValueFont, weight: .semibold),
                     color: style.color(for: limit.percent), in: text, align: .right)
            drawBar(in: NSRect(x: row.minX, y: row.minY + 0.5, width: row.width, height: style.compactBarHeight),
                    percent: limit.percent, style: style)
        }
        return true
    }
}

/// One gauge: name + reset time on top, bar + percentage below.
private func drawLimit(_ limit: Limit, in bounds: NSRect, style: Style) {
    let (top, bottom) = rows(of: bounds)
    drawText(limit.label, font: .systemFont(ofSize: style.labelFont, weight: .semibold),
             color: style.primary, in: top)
    drawText(resetText(limit.resetsAt, short: style.shortResets), font: .systemFont(ofSize: style.smallFont),
             color: style.dim, in: top, align: .right)
    drawBar(in: NSRect(x: bounds.minX, y: bottom.midY - style.barHeight / 2,
                       width: bounds.width - style.percentWidth, height: style.barHeight),
            percent: limit.percent, style: style)
    drawText(percentText(limit.percent),
             font: .monospacedDigitSystemFont(ofSize: style.percentFont, weight: .bold),
             color: style.color(for: limit.percent), in: bottom, align: .right)
}

/// Hourly tokens over the last 24 hours as a mirrored bar chart: input grows up from the
/// centre line, output grows down. Each half has its own scale, since input is far larger.
private func drawTokens(_ series: TokenSeries, in bounds: NSRect, style: Style) {
    let slot = style.chartWidth / CGFloat(TokenSeries.hours)
    let middle = bounds.midY
    let reach = bounds.height / 2 - 2
    let maxInput = max(series.input.max() ?? 0, 1)
    let maxOutput = max(series.output.max() ?? 0, 1)

    for hour in 0..<TokenSeries.hours {
        let x = bounds.minX + CGFloat(hour) * slot
        let width = slot - 1
        style.track.setFill()
        NSRect(x: x, y: middle - 0.5, width: width, height: 1).fill()

        if series.input[hour] > 0 {
            let height = max(1.5, reach * CGFloat(series.input[hour] / maxInput))
            style.tokensIn.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: middle + 1, width: width, height: height),
                         xRadius: 1, yRadius: 1).fill()
        }
        if series.output[hour] > 0 {
            let height = max(1.5, reach * CGFloat(series.output[hour] / maxOutput))
            style.tokensOut.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: middle - 1 - height, width: width, height: height),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    var labels = bounds
    labels.origin.x += style.chartWidth + 8
    labels.size.width -= style.chartWidth + 8
    let (top, bottom) = rows(of: labels)
    let small = NSFont.systemFont(ofSize: style.smallFont, weight: .medium)
    let value = NSFont.monospacedDigitSystemFont(ofSize: style.valueFont, weight: .semibold)
    drawText("in", font: small, color: style.dim, in: top)
    drawText(tokenText(series.totalInput), font: value, color: style.tokensIn, in: top, align: .right)
    drawText("out", font: small, color: style.dim, in: bottom)
    drawText(tokenText(series.totalOutput), font: value, color: style.tokensOut, in: bottom, align: .right)
}

/// One gauge in the expanded Touch Bar.
final class LimitView: NSView {
    private let limit: Limit
    private let size = NSSize(width: Style.touchBar.limitWidth, height: Style.touchBar.height)

    init(limit: Limit) {
        self.limit = limit
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { size }

    override func draw(_ dirtyRect: NSRect) {
        drawLimit(limit, in: bounds, style: .touchBar)
    }
}

/// The token chart in the expanded Touch Bar.
final class TokenView: NSView {
    private let series: TokenSeries
    private let size = NSSize(width: Style.touchBar.tokenWidth, height: Style.touchBar.height)

    init(series: TokenSeries) {
        self.series = series
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { size }

    override func draw(_ dirtyRect: NSRect) {
        drawTokens(series, in: bounds, style: .touchBar)
    }
}

/// What the menu bar item shows: the compact two-row summary, or with `full` the same blocks
/// as the expanded Touch Bar (first two limits and the token chart) laid out side by side.
func menuBarImage(usage: Usage, tokens: TokenSeries?, full: Bool, dark: Bool) -> NSImage {
    let style = Style.menuBar(dark: dark)
    guard full else { return compactImage(usage: usage, note: nil, style: style) }

    let limits = Array(usage.limits.prefix(2))
    let spacing: CGFloat = 12
    var width = CGFloat(limits.count) * (style.limitWidth + spacing) - spacing
    if tokens != nil { width += spacing + style.tokenWidth }

    return NSImage(size: NSSize(width: width, height: style.height), flipped: false) { bounds in
        var x: CGFloat = 0
        for limit in limits {
            drawLimit(limit, in: NSRect(x: x, y: 0, width: style.limitWidth, height: bounds.height), style: style)
            x += style.limitWidth + spacing
        }
        if let tokens {
            drawTokens(tokens, in: NSRect(x: x, y: 0, width: style.tokenWidth, height: bounds.height), style: style)
        }
        return true
    }
}
