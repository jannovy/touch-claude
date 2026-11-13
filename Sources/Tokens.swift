import Foundation

/// Tokens per hour for the last 24 hours. Index 0 is the oldest hour, the last is the current one.
struct TokenSeries {
    static let hours = 24
    var input = [Double](repeating: 0, count: hours)
    var output = [Double](repeating: 0, count: hours)

    var totalInput: Double { input.reduce(0, +) }
    var totalOutput: Double { output.reduce(0, +) }
}

/// Reads token counts from Claude Code's session transcripts (~/.claude/projects/**/*.jsonl).
/// Only the `usage` numbers and timestamps are looked at, never message content.
/// Transcripts are append-only, so each scan reads just the bytes added since the last one.
final class TokenScanner {
    private struct Entry {
        var date: Date
        var input: Double
        var output: Double
    }

    private let root = URL(fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath)
    private var offsets: [String: UInt64] = [:]
    /// Keyed by API message id: one reply is written as several lines that repeat its usage.
    private var entries: [String: Entry] = [:]
    private let usageMarker = Data("\"usage\"".utf8)
    private let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Call from one serial background queue.
    func scan() -> TokenSeries {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(TokenSeries.hours) * 3600)

        let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified >= cutoff,
                  let size = values.fileSize else { continue }
            readNewLines(of: url, size: UInt64(size))
        }

        entries = entries.filter { $0.value.date >= cutoff }

        var series = TokenSeries()
        for entry in entries.values {
            let age = Int(now.timeIntervalSince(entry.date) / 3600)
            guard age >= 0, age < TokenSeries.hours else { continue }
            let index = TokenSeries.hours - 1 - age
            series.input[index] += entry.input
            series.output[index] += entry.output
        }
        return series
    }

    private func readNewLines(of url: URL, size: UInt64) {
        var offset = offsets[url.path] ?? 0
        if size < offset { offset = 0 } // file was replaced
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: 0x0A) else { return }

        // Stop at the last complete line; a half-written one is picked up next time.
        offsets[url.path] = offset + UInt64(lastNewline - data.startIndex + 1)
        for line in data[data.startIndex..<lastNewline].split(separator: 0x0A) {
            guard line.range(of: usageMarker) != nil else { continue }
            record(line)
        }
    }

    private func record(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let date = timestamps.date(from: stamp),
              let id = (message["id"] ?? object["uuid"]) as? String else { return }

        func count(_ key: String) -> Double { (usage[key] as? NSNumber)?.doubleValue ?? 0 }
        // Newly sent tokens. Cache reads are left out: they are the same context re-read on
        // every turn and would dwarf everything else by ~50x.
        let input = count("input_tokens") + count("cache_creation_input_tokens")
        let output = count("output_tokens")

        if let existing = entries[id] {
            entries[id] = Entry(date: existing.date, input: max(existing.input, input),
                                output: max(existing.output, output))
        } else {
            entries[id] = Entry(date: date, input: input, output: output)
        }
    }
}
