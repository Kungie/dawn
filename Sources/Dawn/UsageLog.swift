import Foundation

/// Reads the local Claude Code session logs (~/.claude/projects/*/*.jsonl) and estimates the current five-hour
/// usage window from the timestamps of Claude's replies.
///
/// What it can and can't see: Claude Code in the terminal, in IDEs and in the desktop app's Code tab all write
/// these logs. Chats in Claude.ai or the desktop app's chat do not, so for those the user can tell Dawn
/// "I just started" by hand. Like most community tools, the window start is rounded down to the full hour.
/// Treat the result as an estimate; Anthropic's own usage page is the source of truth.
final class UsageLog {
    struct Activity {
        let date: Date
        let isPing: Bool // written by Dawn's own morning ping
    }

    static let windowLength: TimeInterval = 5 * 3600

    private let root: URL
    private let lookback: TimeInterval = 24 * 3600
    private var cache: [String: (mtime: Date, items: [Activity])] = [:]
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoNoFraction = ISO8601DateFormatter()

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    /// Every Claude reply in the last 24 hours, oldest first.
    func recentActivity(now: Date = Date()) -> [Activity] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var all: [Activity] = []
        var seen = Set<String>()
        for project in projects {
            let isPing = project.lastPathComponent.hasSuffix(PingRunner.projectSuffix)
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      now.timeIntervalSince(mtime) < lookback else { continue }
                seen.insert(file.path)
                if let hit = cache[file.path], hit.mtime == mtime {
                    all += hit.items
                    continue
                }
                let items = parse(file, isPing: isPing, since: now.addingTimeInterval(-lookback))
                cache[file.path] = (mtime, items)
                all += items
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return all.sorted { $0.date < $1.date }
    }

    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
    }

    private func parse(_ file: URL, isPing: Bool, since: Date) -> [Activity] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        let marker = Data("\"type\":\"assistant\"".utf8)
        let decoder = JSONDecoder()
        var out: [Activity] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            if line.range(of: marker) != nil,
               let row = try? decoder.decode(Line.self, from: line),
               row.type == "assistant", let ts = row.timestamp,
               let date = iso.date(from: ts) ?? isoNoFraction.date(from: ts),
               date >= since {
                out.append(Activity(date: date, isPing: isPing))
            }
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
        }
        return out
    }

    /// Splits activity into five-hour blocks the way the window works: a block starts at the first message
    /// (rounded down to the hour) and anything after it ends starts the next block.
    static func blocks(from dates: [Date]) -> [DateInterval] {
        var blocks: [DateInterval] = []
        for date in dates.sorted() {
            if let last = blocks.last, date < last.end { continue }
            let start = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
            blocks.append(DateInterval(start: start, duration: windowLength))
        }
        return blocks
    }
}
