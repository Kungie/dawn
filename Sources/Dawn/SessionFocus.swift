import AppKit
import ApplicationServices
import Darwin
import Foundation

/// Where a Claude Code session runs: the app that hosts it (Terminal, iTerm2, an editor, the Claude app…)
/// and the terminal device of the session, if it has one.
struct SessionInfo: Equatable {
    var hostPID: Int32?
    var hostBundleID: String?
    var tty: String?

    init(hostPID: Int32? = nil, hostBundleID: String? = nil, tty: String? = nil) {
        self.hostPID = hostPID
        self.hostBundleID = hostBundleID
        self.tty = tty
    }

    init(userInfo: [AnyHashable: Any]?) {
        hostPID = (userInfo?["hostPID"] as? NSNumber)?.int32Value
        hostBundleID = userInfo?["hostBundleID"] as? String
        tty = userInfo?["tty"] as? String
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let hostPID { info["hostPID"] = NSNumber(value: hostPID) }
        if let hostBundleID { info["hostBundleID"] = hostBundleID }
        if let tty { info["tty"] = tty }
        return info
    }

    /// Called inside `Dawn hook`: walk up from Claude Code's process to the first GUI app, and pick up
    /// the session's terminal on the way.
    static func current() -> SessionInfo {
        var info = SessionInfo()
        var pid = getppid()
        for _ in 0..<24 {
            guard pid > 1, let proc = kinfo(pid) else { break }
            if info.tty == nil, proc.kp_eproc.e_tdev != -1, let name = devname(proc.kp_eproc.e_tdev, S_IFCHR) {
                info.tty = "/dev/" + String(cString: name)
            }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                info.hostPID = pid
                info.hostBundleID = app.bundleIdentifier
                break
            }
            pid = proc.kp_eproc.e_ppid
        }
        return info
    }

    private static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        return proc
    }
}

/// Takes you to a Claude Code session: the right tab in Terminal or iTerm2, otherwise the host app
/// (and, with Accessibility allowed, the window of that project). macOS switches to the Desktop the
/// window is on; the window itself is never moved to the current Desktop.
enum SessionFocus {
    static func open(_ s: SessionInfo, project: String) {
        if let tty = s.tty, let bundle = s.hostBundleID {
            switch bundle {
            case "com.apple.Terminal":
                if runScript(terminalScript(tty: tty)) { return }
            case "com.googlecode.iterm2":
                if runScript(itermScript(tty: tty)) { return }
            default:
                break
            }
        }
        guard let pid = s.hostPID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        raiseWindow(of: pid, titleContaining: project)
        activate(app)
    }

    private static func activate(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Raise the host's window whose title mentions the project. Needs Accessibility; silently skipped otherwise.
    private static func raiseWindow(of pid: pid_t, titleContaining project: String) {
        guard !project.isEmpty, AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if let t = title as? String, t.localizedCaseInsensitiveContains(project) {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }

    @discardableResult
    private static func runScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is \(quoted(tty)) then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            error "tab not found"
        end tell
        """
    }

    private static func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is \(quoted(tty)) then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            error "session not found"
        end tell
        """
    }
}
