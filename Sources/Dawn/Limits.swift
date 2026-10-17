import Foundation

/// Claude's own word on the current five-hour window: when it resets and how much of it is used.
///
/// Claude Code hands these to its status line command as `rate_limits.five_hour.resets_at` (Unix seconds)
/// and `used_percentage`, for Pro and Max plans, after the first response of a session. Dawn's status line
/// command picks them up, so the countdown no longer has to be guessed from the logs.
struct WindowLimit: Codable, Equatable {
    let resetsAt: Date
    let usedPercent: Double?
    let updated: Date

    private static var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("window-limit.json")
    }

    static func load() -> WindowLimit? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(WindowLimit.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }

    /// Reads `rate_limits.five_hour` from a status line payload; accepts epoch seconds or an ISO date.
    init?(statusLine json: [String: Any], now: Date = Date()) {
        guard let rl = json["rate_limits"] as? [String: Any], let five = rl["five_hour"] as? [String: Any] else { return nil }
        var reset: Date?
        if let n = five["resets_at"] as? NSNumber {
            reset = Date(timeIntervalSince1970: n.doubleValue)
        } else if let s = five["resets_at"] as? String {
            let f = ISO8601DateFormatter()
            reset = f.date(from: s) ?? { f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: s) }()
        }
        guard let resetsAt = reset else { return nil }
        self.resetsAt = resetsAt
        self.usedPercent = (five["used_percentage"] as? NSNumber)?.doubleValue
        self.updated = now
    }

    init(resetsAt: Date, usedPercent: Double?, updated: Date) {
        self.resetsAt = resetsAt
        self.usedPercent = usedPercent
        self.updated = updated
    }
}

/// `Dawn statusline`: Claude Code's status line command. Passes the window's reset time to the app, then
/// runs the status line you had before (if any) with the same input, so your own status line keeps working.
enum StatusLineCommand {
    static let notification = Notification.Name("io.github.kungie.dawn.limit")

    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let limit = WindowLimit(statusLine: json) {
            limit.save()
            DistributedNotificationCenter.default().postNotificationName(
                notification, object: nil,
                userInfo: ["resetsAt": limit.resetsAt.timeIntervalSince1970, "used": limit.usedPercent ?? -1],
                deliverImmediately: true)
        }
        guard let original = ClaudeHook.originalStatusLine(), !original.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", original]
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError
        do {
            try p.run()
            input.fileHandleForWriting.write(data)
            try? input.fileHandleForWriting.close()
            p.waitUntilExit()
        } catch {}
    }
}
