import AppKit

/// Private system API that lets a background app keep an item in the Control Strip.
/// Same mechanism MTMR / Pock use; Apple offers no public equivalent.
private enum SystemTouchBar {
    private static let dfr = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    private static func call(_ symbol: String, _ body: (UnsafeMutableRawPointer) -> Void) -> Bool {
        guard let dfr, let pointer = dlsym(dfr, symbol) else { return false }
        body(pointer)
        return true
    }

    static func setControlStripPresence(_ identifier: String, _ present: Bool) -> Bool {
        call("DFRElementSetControlStripPresenceForIdentifier") {
            typealias Fn = @convention(c) (CFString, Bool) -> Void
            unsafeBitCast($0, to: Fn.self)(identifier as CFString, present)
        }
    }

    static func showCloseBox(_ show: Bool) {
        _ = call("DFRSystemModalShowsCloseBoxWhenFrontMost") {
            typealias Fn = @convention(c) (Bool) -> Void
            unsafeBitCast($0, to: Fn.self)(show)
        }
    }

    static func addTrayItem(_ item: NSTouchBarItem) -> Bool {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard NSTouchBarItem.responds(to: selector) else { return false }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
        return true
    }

    static func present(_ bar: NSTouchBar, trayIdentifier: String) -> Bool {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: selector) else { return false }
        _ = (NSTouchBar.self as AnyObject).perform(selector, with: bar, with: trayIdentifier as NSString)
        return true
    }
}

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private static let trayID = NSTouchBarItem.Identifier("local.claude-usage-bar.tray")
    private static let detailID = NSTouchBarItem.Identifier("local.claude-usage-bar.detail")

    var onRefresh: (() -> Void)?

    private let trayItem = NSCustomTouchBarItem(identifier: trayID)
    private lazy var trayButton = NSButton(image: compactImage(usage: nil, note: nil),
                                           target: self, action: #selector(expand))
    private let detailStack = NSStackView()
    private lazy var detailBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.detailID]
        return bar
    }()

    /// Returns false when the system refuses the Control Strip item (API gone or no Touch Bar).
    func install() -> Bool {
        trayButton.imagePosition = .imageOnly
        trayItem.view = trayButton
        detailStack.orientation = .horizontal
        detailStack.spacing = 26

        SystemTouchBar.showCloseBox(true)
        guard SystemTouchBar.addTrayItem(trayItem) else { return false }
        return SystemTouchBar.setControlStripPresence(Self.trayID.rawValue, true)
    }

    func update(usage: Usage?, note: String?, tokens: TokenSeries?) {
        trayButton.image = compactImage(usage: usage, note: note)

        detailStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let usage {
            usage.limits.forEach { detailStack.addArrangedSubview(LimitView(limit: $0)) }
        } else {
            detailStack.addArrangedSubview(NSTextField(labelWithString: note ?? "Loading Claude usage…"))
        }
        // The bar has room for three blocks next to the Control Strip.
        if let tokens, detailStack.arrangedSubviews.count <= 2 {
            detailStack.addArrangedSubview(TokenView(series: tokens))
        }
    }

    @objc func expand() {
        _ = SystemTouchBar.present(detailBar, trayIdentifier: Self.trayID.rawValue)
        onRefresh?()
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.detailID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = detailStack
        return item
    }
}
