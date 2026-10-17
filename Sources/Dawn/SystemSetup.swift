import AppKit
import Foundation
import ServiceManagement

/// The scheduled wake, via macOS's own `pmset`. Needs an administrator password once.
/// Note: macOS keeps only one repeating wake/power-on event, so this replaces any other one.
enum WakeSchedule {
    /// pmset weekday letters, Monday first.
    private static let letters: [Int: String] = [2: "M", 3: "T", 4: "W", 5: "R", 6: "F", 7: "S", 1: "U"]

    /// The repeating events as macOS reports them, e.g. "wake at 6:29AM every day".
    static func current() -> String? {
        let out = PingRunner.run("/usr/bin/pmset", ["-g", "sched"], timeout: 5).output ?? ""
        guard let range = out.range(of: "Repeating power events:") else { return nil }
        let lines = out[range.upperBound...].split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .prefix { !$0.isEmpty && !$0.hasSuffix(":") }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    static func install(hour: Int, minute: Int, weekdays: Set<Int>) -> String? {
        // Wake one minute early so the network is back when the ping goes out.
        let total = (hour * 60 + minute + 24 * 60 - 1) % (24 * 60)
        let days = [2, 3, 4, 5, 6, 7, 1].filter(weekdays.contains).compactMap { letters[$0] }.joined()
        guard !days.isEmpty else { return "Pick at least one day." }
        let time = String(format: "%02d:%02d:00", total / 60, total % 60)
        return admin("/usr/bin/pmset repeat wake \(days) \(time)")
    }

    static func remove() -> String? {
        admin("/usr/bin/pmset repeat cancel")
    }

    /// Runs one fixed pmset command through the standard macOS administrator prompt. Returns an error message or nil.
    private static func admin(_ command: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")
        script?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return "Cancelled." }
        return (error[NSAppleScript.errorMessage] as? String) ?? "pmset failed."
    }
}

/// Adds or removes Dawn's entry in Claude Code's Notification hook (~/.claude/settings.json).
/// Claude Code then calls `Dawn hook` whenever it is waiting for you, and the menu bar shows a dot.
/// Other settings and hooks are kept; a backup is written next to the file before the first change.
enum ClaudeHook {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var command: String {
        "\"\(Bundle.main.executablePath ?? "/Applications/Dawn.app/Contents/MacOS/Dawn")\" hook"
    }

    private static func isOurs(_ entry: Any) -> Bool {
        guard let hooks = (entry as? [String: Any])?["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { (($0["command"] as? String) ?? "").hasSuffix("/Contents/MacOS/Dawn\" hook") }
    }

    private static func load() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Dawn", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object."])
        }
        return json
    }

    static func isInstalled() -> Bool {
        guard let json = try? load(), let hooks = json["hooks"] as? [String: Any],
              let list = hooks["Notification"] as? [Any] else { return false }
        return list.contains(where: isOurs)
    }

    static func install() -> String? { update(add: true) }
    static func remove() -> String? { update(add: false) }

    private static func update(add: Bool) -> String? {
        do {
            var json = try load()
            var hooks = json["hooks"] as? [String: Any] ?? [:]
            var list = (hooks["Notification"] as? [Any] ?? []).filter { !isOurs($0) }
            if add { list.append(["matcher": "", "hooks": [["type": "command", "command": command]]]) }
            if list.isEmpty { hooks.removeValue(forKey: "Notification") } else { hooks["Notification"] = list }
            if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

            let fm = FileManager.default
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let backup = settingsURL.appendingPathExtension("dawn-backup")
            if fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: settingsURL, to: backup)
            }
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: settingsURL, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// `Dawn hook`: called by Claude Code with the notification as JSON on stdin. Forwards it to the running app and exits.
enum HookCommand {
    static let notification = Notification.Name("labs.vektor.dawn.ask")

    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = (json["message"] as? String) ?? "Claude Code is waiting for you"
        let cwd = (json["cwd"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: nil,
            userInfo: ["message": String(message.prefix(200)), "project": cwd],
            deliverImmediately: true)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
