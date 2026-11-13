import Foundation

/// One rate-limit window (5-hour session, weekly, ...).
struct Limit {
    let key: String
    let label: String
    let short: String
    let rawPercent: Double
    let resetsAt: Date?

    /// A window whose reset time has passed is empty again, even if the data is stale.
    var percent: Double {
        if let resetsAt, resetsAt < Date() { return 0 }
        return max(0, min(100, rawPercent))
    }
}

struct Usage {
    let limits: [Limit]
    let fetchedAt: Date
}

struct UsageError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private let knownLimits: [(key: String, label: String, short: String)] = [
    ("five_hour", "Session", "5h"),
    ("seven_day", "Week", "7d"),
    ("seven_day_opus", "Week · Opus", "Op"),
    ("seven_day_sonnet", "Week · Sonnet", "So"),
]

private func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String { return Double(s) }
    return nil
}

private func date(_ value: Any?) -> Date? {
    if let n = value as? NSNumber {
        let v = n.doubleValue
        return Date(timeIntervalSince1970: v > 1e12 ? v / 1000 : v)
    }
    guard let s = value as? String else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: s)
}

/// Accepts both shapes seen in the wild:
///   {"five_hour": {"utilization": 42, "resets_at": "2026-...Z"}, "seven_day": {...}}
///   {"rate_limits": {"five_hour": {"used_percentage": 42, "resets_at": 1790000000}, ...}}
func parseUsage(_ data: Data) throws -> Usage {
    guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw UsageError("response is not JSON")
    }
    if let nested = root["rate_limits"] as? [String: Any] { root = nested }

    var limits: [Limit] = []
    for known in knownLimits {
        guard let entry = root[known.key] as? [String: Any],
              let percent = number(entry["utilization"] ?? entry["used_percentage"]) else { continue }
        limits.append(Limit(key: known.key, label: known.label, short: known.short,
                            rawPercent: percent, resetsAt: date(entry["resets_at"])))
    }
    guard !limits.isEmpty else { throw UsageError("no limits in data") }
    return Usage(limits: limits, fetchedAt: Date())
}

// MARK: - Sources

protocol UsageSource {
    var name: String { get }
    var interval: TimeInterval { get }
    /// Called on a background queue.
    func fetch() throws -> Usage
}

/// Fake, slowly moving numbers for checking the Touch Bar UI.
struct DemoSource: UsageSource {
    let name = "demo"
    let interval: TimeInterval = 2
    let start = Date()

    func fetch() throws -> Usage {
        let t = Date().timeIntervalSince(start)
        let session = (t * 4).truncatingRemainder(dividingBy: 100)
        let limits = [
            Limit(key: "five_hour", label: "Session", short: "5h", rawPercent: session,
                  resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60)),
            Limit(key: "seven_day", label: "Week", short: "7d", rawPercent: 74,
                  resetsAt: Date().addingTimeInterval(3 * 86400)),
            Limit(key: "seven_day_opus", label: "Week · Opus", short: "Op", rawPercent: 93,
                  resetsAt: Date().addingTimeInterval(3 * 86400)),
        ]
        return Usage(limits: limits, fetchedAt: Date())
    }
}

/// Reads a JSON file that something else keeps up to date (e.g. a Claude Code status line hook).
struct FileSource: UsageSource {
    let name = "file"
    let interval: TimeInterval = 5
    let path: String

    static let defaultPath = NSString(string: "~/.claude/usage-touchbar.json").expandingTildeInPath

    func fetch() throws -> Usage {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw UsageError("no file at \(path)")
        }
        let usage = try parseUsage(data)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return Usage(limits: usage.limits, fetchedAt: modified ?? usage.fetchedAt)
    }
}

/// Asks Anthropic directly, using the login Claude Code keeps in the macOS Keychain.
/// Read-only: never refreshes or rewrites the stored token.
struct OAuthSource: UsageSource {
    let name = "oauth"
    let interval: TimeInterval = 180

    func fetch() throws -> Usage {
        let token = try accessToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                                 timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("usage-touchbar/0.1", forHTTPHeaderField: "User-Agent")

        var result: Result<Data, Error> = .failure(UsageError("no response"))
        let done = DispatchSemaphore(value: 0)
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            defer { done.signal() }
            if let error { result = .failure(UsageError(error.localizedDescription)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: result = .success(data ?? Data())
            case 401, 403: result = .failure(UsageError("login expired – open Claude Code"))
            case 429: result = .failure(UsageError("rate limited – retrying later"))
            default: result = .failure(UsageError("HTTP \(status)"))
            }
        }.resume()
        done.wait()
        return try parseUsage(try result.get())
    }

    private func accessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UsageError("no Claude Code login in Keychain") }

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw UsageError("unexpected Keychain entry format")
        }
        if let expires = number(oauth["expiresAt"]), expires / 1000 < Date().timeIntervalSince1970 {
            throw UsageError("login expired – open Claude Code")
        }
        return token
    }
}

func makeSource(named name: String, filePath: String) -> UsageSource? {
    switch name {
    case "demo": return DemoSource()
    case "file": return FileSource(path: filePath)
    case "oauth": return OAuthSource()
    default: return nil
    }
}
