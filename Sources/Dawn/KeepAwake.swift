import Foundation
import IOKit.ps

/// How long Keep awake stays on once you switch it on.
enum KeepAwakeFor: Int, Codable, CaseIterable, Labelled {
    case oneHour = 1, twoHours = 2, fourHours = 4, untilOff = 0

    var hours: Int? { self == .untilOff ? nil : rawValue }
    var label: String {
        switch self {
        case .oneHour: return "1 h"
        case .twoHours: return "2 h"
        case .fourHours: return "4 h"
        case .untilOff: return "Never"
        }
    }
}

/// On battery, Keep awake switches itself off at this charge.
enum KeepAwakeCutoff: Int, Codable, CaseIterable, Labelled {
    case ten = 10, twenty = 20, thirty = 30, never = 0

    var label: String { self == .never ? "Never" : "\(rawValue)%" }
}

/// Keeps the Mac awake with the lid closed, the way Awayke does it: macOS's own `pmset -a disablesleep 1`,
/// which is the one switch lid-close sleep listens to (power assertions and `caffeinate` don't stop it).
///
/// `pmset` needs root. Dawn isn't signed by a developer ID, so instead of a privileged helper it asks for your
/// administrator password once and adds a sudoers rule that allows exactly `pmset -a disablesleep 0` and `1`
/// for you and nothing else. After that the switch needs no password. *Remove* in Setup takes the rule out.
/// The setting is system-wide: while it's on, nothing sleeps from a closed lid. Dawn turns it off when you
/// switch it off, when the time you picked is up, when the battery runs low, and when Dawn quits.
enum KeepAwake {
    /// No dot in the name: sudo skips files in sudoers.d that have one.
    static let rulePath = "/etc/sudoers.d/dawn-keepawake"

    struct Battery: Equatable {
        var percent: Int
        var onBattery: Bool
    }

    enum StopReason: Equatable {
        case time
        case battery(Int)
    }

    /// `SleepDisabled` from `pmset -g`, or nil when the line isn't there.
    static func sleepDisabled(pmset output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return nil
    }

    /// The sudoers line for `user`, or nil for a name that isn't a plain short user name.
    static func rule(user: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard !user.isEmpty, user != "ALL", user.first?.isLetter == true || user.first == "_",
              user.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    /// Runs as root through the macOS password prompt: writes the rule under a name sudo ignores, locks it
    /// down, has visudo check it, only then moves it into place, and switches lid sleep off.
    static func installCommand(user: String) -> String? {
        guard let rule = rule(user: user) else { return nil }
        let tmp = rulePath + ".tmp"
        return "(/bin/mkdir -p /etc/sudoers.d && /bin/echo '\(rule)' > \(tmp) && /bin/chmod 0440 \(tmp)"
            + " && /usr/sbin/chown root:wheel \(tmp) && /usr/sbin/visudo -cf \(tmp) && /bin/mv \(tmp) \(rulePath)"
            + " && /usr/bin/pmset -a disablesleep 1); s=$?; /bin/rm -f \(tmp); exit $s"
    }

    static let removeCommand = "/bin/rm -f \(rulePath); /usr/bin/pmset -a disablesleep 0"

    /// Whether to switch off now: the time you picked is up, or the Mac runs on battery at or below the cutoff.
    static func shouldStop(now: Date, until: Date?, battery: Battery?, cutoff: KeepAwakeCutoff) -> StopReason? {
        if let until, now >= until { return .time }
        if cutoff != .never, let battery, battery.onBattery, battery.percent <= cutoff.rawValue {
            return .battery(battery.percent)
        }
        return nil
    }

    // MARK: talking to macOS

    /// Whether lid sleep is off right now, by whoever turned it off.
    static func current() -> Bool? {
        sleepDisabled(pmset: PingRunner.run("/usr/bin/pmset", ["-g"], timeout: 5).output ?? "")
    }

    /// Whether Dawn's rule is in place. Not asked of `sudo -n -l`: an admin may run anything with a
    /// password, and once any NOPASSWD rule exists sudo lists without one, so it says yes to every command.
    /// /etc/sudoers.d can be listed without root. If the rule is there but broken, `set` fails and
    /// switching on writes it again.
    static func ruleInstalled(at path: String = rulePath) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Switches lid sleep without a password, through the rule. False when that didn't work.
    static func set(_ on: Bool) -> Bool {
        PingRunner.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"], timeout: 10).status == 0
    }

    /// The internal battery, or nil on a Mac without one.
    static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Battery(percent: now * 100 / max, onBattery: d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
