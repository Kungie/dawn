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

/// Adds or removes Dawn's entries in Claude Code's hooks (~/.claude/settings.json): `Notification` calls
/// `Dawn hook` when Claude Code is waiting for you, `Stop` calls `Dawn hook stop` when it has finished a task.
/// Other settings and hooks are kept; a backup is written next to the file before the first change.
enum ClaudeHook {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var command: String {
        "\"\(Bundle.main.executablePath ?? "/Applications/Dawn.app/Contents/MacOS/Dawn")\" hook"
    }

    /// Hook event → the command Claude Code runs for it.
    private static var events: [String: String] { ["Notification": command, "Stop": command + " stop"] }

    /// Claude Code's status line command: Dawn reads the real reset time from it.
    static var statusLineCommand: String {
        "\"\(Bundle.main.executablePath ?? "/Applications/Dawn.app/Contents/MacOS/Dawn")\" statusline"
    }

    private static func isOurStatusLine(_ value: Any?) -> Bool {
        (((value as? [String: Any])?["command"] as? String) ?? "").contains("/Contents/MacOS/Dawn\" statusline")
    }

    /// The status line you had before Dawn took the slot; Dawn runs it and shows its output.
    private static var originalURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("original-statusline.txt")
    }

    static func originalStatusLine() -> String? {
        try? String(contentsOf: originalURL, encoding: .utf8)
    }

    private static func isOurs(_ entry: Any) -> Bool {
        guard let hooks = (entry as? [String: Any])?["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { (($0["command"] as? String) ?? "").contains("/Contents/MacOS/Dawn\" hook") }
    }

    private static func load() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Dawn", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object."])
        }
        return json
    }

    static func isInstalled() -> Bool {
        guard let json = try? load(), let hooks = json["hooks"] as? [String: Any] else { return false }
        return events.keys.allSatisfy { ((hooks[$0] as? [Any]) ?? []).contains(where: isOurs) }
            && isOurStatusLine(json["statusLine"])
    }

    static func install() -> String? { update(add: true) }
    static func remove() -> String? { update(add: false) }

    private static func update(add: Bool) -> String? {
        do {
            var json = try load()
            var hooks = json["hooks"] as? [String: Any] ?? [:]
            for (event, cmd) in events {
                var list = (hooks[event] as? [Any] ?? []).filter { !isOurs($0) }
                if add { list.append(["matcher": "", "hooks": [["type": "command", "command": cmd]]]) }
                if list.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = list }
            }
            if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

            // Status line: take the slot, keeping your own command (and its padding/refresh settings)
            // to run behind Dawn's; on remove, put yours back exactly.
            let fm0 = FileManager.default
            var line = json["statusLine"] as? [String: Any]
            if add {
                if !isOurStatusLine(line), let own = line?["command"] as? String, !own.isEmpty {
                    try own.write(to: originalURL, atomically: true, encoding: .utf8)
                }
                if line == nil { line = ["type": "command"] }
                line?["command"] = statusLineCommand
                json["statusLine"] = line
            } else if isOurStatusLine(line) {
                if let own = originalStatusLine(), !own.isEmpty {
                    line?["command"] = own
                    json["statusLine"] = line
                } else {
                    json.removeValue(forKey: "statusLine")
                }
                try? fm0.removeItem(at: originalURL)
            }

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

/// `Dawn hook [stop]`: called by Claude Code with the event as JSON on stdin. Forwards it to the running app and exits.
enum HookCommand {
    static let notification = Notification.Name("io.github.kungie.dawn.ask")
    static let doneNotification = Notification.Name("io.github.kungie.dawn.done")

    static func run(stop: Bool) {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        // A `claude -p` another tool runs in the background from its own hook (Binder marks its runs so)
        // isn't your session: no dot, no sound.
        if ProcessInfo.processInfo.environment["BINDER_NESTED"] == "1" { return }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let cwd = (json["cwd"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        if cwd == PingRunner.projectSuffix { return } // Dawn's own ping: no dot, no sound
        var info = SessionInfo.current().userInfo
        info["project"] = cwd
        if stop {
            DistributedNotificationCenter.default().postNotificationName(
                doneNotification, object: nil, userInfo: info, deliverImmediately: true)
            return
        }
        let message = (json["message"] as? String) ?? "Claude Code is waiting for you"
        info["message"] = String(message.prefix(200))
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: nil, userInfo: info, deliverImmediately: true)
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
