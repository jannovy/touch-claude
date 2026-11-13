import AppKit

// MARK: - Arguments

var sourceName = UserDefaults.standard.string(forKey: "source") ?? "file"
var filePath = FileSource.defaultPath
var printOnce = false
var startExpanded = false // opens the detail view right away, as if the tile had been tapped
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--source": sourceName = arguments.next() ?? ""
    case "--file": filePath = arguments.next() ?? ""
    case "--once": printOnce = true
    case "--expanded": startExpanded = true
    case "--help", "-h":
        print("usage: ClaudeUsageBar [--source file|oauth|demo] [--file path] [--once] [--expanded]")
        exit(0)
    default: break // ignore flags AppKit / LaunchServices pass in
    }
}

guard let source = makeSource(named: sourceName, filePath: filePath) else {
    FileHandle.standardError.write("unknown source '\(sourceName)' (demo, file, oauth)\n".data(using: .utf8)!)
    exit(2)
}

/// `--once` prints the current numbers and exits; handy for checking a data source.
if printOnce {
    do {
        for limit in try source.fetch().limits {
            print("\(limit.label): \(percentText(limit.percent)) \(resetText(limit.resetsAt))")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("\(source.name): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let source: UsageSource
    private let touchBar = TouchBarController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "usage-fetch")
    private var usage: Usage?
    private let tokenScanner = TokenScanner()
    private var tokens: TokenSeries?
    private var lastError: String?
    private var touchBarAvailable = false
    private var fetching = false

    init(source: UsageSource) {
        self.source = source
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        touchBarAvailable = touchBar.install()
        touchBar.onRefresh = { [weak self] in
            self?.refresh()
            self?.scanTokens()
        }

        statusItem.button?.title = "✳︎"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        if startExpanded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.touchBar.expand() }
        }
        Timer.scheduledTimer(withTimeInterval: source.interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Keeps the "resets in …" countdown moving between fetches.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.render()
        }
        scanTokens()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.scanTokens()
        }
    }

    private func scanTokens() {
        queue.async { [tokenScanner] in
            let series = tokenScanner.scan()
            DispatchQueue.main.async {
                self.tokens = series
                self.render()
            }
        }
    }

    @objc private func refresh() {
        guard !fetching else { return }
        fetching = true
        queue.async { [source] in
            let result = Result { try source.fetch() }
            DispatchQueue.main.async {
                self.fetching = false
                switch result {
                case .success(let usage):
                    self.usage = usage
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = "\(error)"
                }
                self.render()
            }
        }
    }

    private func render() {
        touchBar.update(usage: usage, note: usage == nil ? lastError : nil, tokens: tokens)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for limit in usage?.limits ?? [] {
            menu.addItem(withTitle: "\(limit.label): \(percentText(limit.percent))  ·  \(resetText(limit.resetsAt))",
                         action: nil, keyEquivalent: "")
        }
        if let tokens {
            menu.addItem(withTitle: "Tokens, last 24 h: \(tokenText(tokens.totalInput)) in  ·  \(tokenText(tokens.totalOutput)) out",
                         action: nil, keyEquivalent: "")
        }
        if let usage {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(withTitle: "Updated \(formatter.string(from: usage.fetchedAt)) (\(source.name))",
                         action: nil, keyEquivalent: "")
        }
        if let lastError {
            menu.addItem(withTitle: "⚠︎ \(lastError)", action: nil, keyEquivalent: "")
        }
        if !touchBarAvailable {
            menu.addItem(withTitle: "⚠︎ Touch Bar item could not be installed", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(source: source)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
