import Foundation
import Testing
@testable import Dawn

@Suite struct KeepAwakeTests {
    @Test func readsWhetherLidSleepIsOff() {
        #expect(KeepAwake.sleepDisabled(pmset: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1") == true)
        #expect(KeepAwake.sleepDisabled(pmset: "System-wide power settings:\n SleepDisabled\t\t0\n") == false)
        #expect(KeepAwake.sleepDisabled(pmset: "Currently in use:\n sleep 1") == nil)
    }

    @Test func theRuleAllowsExactlyTheTwoCommands() {
        #expect(KeepAwake.rule(user: "erenmac") ==
                "erenmac ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1")
        for bad in ["", "root;rm -rf /", "eren mac", "o'brien", "a\"b", "ALL", "%admin", "-x"] {
            #expect(KeepAwake.rule(user: bad) == nil, "\(bad)")
        }
    }

    @Test func theRulePassesVisudo() throws {
        let file = makeTempDir("sudoers").appendingPathComponent("dawn-keepawake")
        try Data((try #require(KeepAwake.rule(user: "erenmac")) + "\n").utf8).write(to: file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        p.arguments = ["-cf", file.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    /// sudo skips files in sudoers.d whose names contain a dot, so the final name has none and the
    /// half-written one does: it never counts until visudo has checked it.
    @Test func theInstallCommandChecksBeforeItCounts() throws {
        #expect(!KeepAwake.rulePath.split(separator: "/").last!.contains("."))
        let cmd = try #require(KeepAwake.installCommand(user: "erenmac"))
        let rule = try #require(KeepAwake.rule(user: "erenmac"))
        #expect(cmd.contains("'\(rule)'"))
        let order = ["> \(KeepAwake.rulePath).tmp", "chmod 0440", "chown root:wheel", "visudo -cf \(KeepAwake.rulePath).tmp",
                     "mv \(KeepAwake.rulePath).tmp \(KeepAwake.rulePath)", "&& /usr/bin/pmset -a disablesleep 1)"]
        let positions = try order.map { try #require(cmd.range(of: $0), "\($0)").lowerBound }
        #expect(positions == positions.sorted())
        #expect(!cmd.contains("\"") && !cmd.contains("\\"))
        #expect(KeepAwake.installCommand(user: "x;y") == nil)
        #expect(KeepAwake.removeCommand.contains("rm -f \(KeepAwake.rulePath)"))
        #expect(KeepAwake.removeCommand.contains("pmset -a disablesleep 0"))
    }

    /// Asked of the file, not of `sudo -l`: an admin may run anything with a password, and once any
    /// NOPASSWD rule exists sudo lists without one, so `sudo -n -l` says yes to every command.
    @Test func theRuleCheckLooksAtDawnsOwnFile() throws {
        let dir = makeTempDir("sudoers.d")
        let file = dir.appendingPathComponent("dawn-keepawake")
        #expect(!KeepAwake.ruleInstalled(at: file.path))
        write("someone ALL=(root) NOPASSWD: /bin/ls\n", to: dir.appendingPathComponent("other-tool"))
        #expect(!KeepAwake.ruleInstalled(at: file.path))
        write(try #require(KeepAwake.rule(user: "erenmac")) + "\n", to: file)
        #expect(KeepAwake.ruleInstalled(at: file.path))
    }

    @Test func stopsWhenTimeIsUpOrTheBatteryRunsLow() {
        let now = Date()
        #expect(KeepAwake.shouldStop(now: now, until: now.addingTimeInterval(-1), battery: nil, cutoff: .twenty) == .time)
        #expect(KeepAwake.shouldStop(now: now, until: now.addingTimeInterval(60), battery: nil, cutoff: .twenty) == nil)
        let low = KeepAwake.Battery(percent: 18, onBattery: true)
        #expect(KeepAwake.shouldStop(now: now, until: nil, battery: low, cutoff: .twenty) == .battery(18))
        #expect(KeepAwake.shouldStop(now: now, until: nil, battery: low, cutoff: .ten) == nil)
        #expect(KeepAwake.shouldStop(now: now, until: nil, battery: low, cutoff: .never) == nil)
        // Plugged in, a low battery is charging: keep going.
        #expect(KeepAwake.shouldStop(now: now, until: nil, battery: .init(percent: 5, onBattery: false), cutoff: .thirty) == nil)
    }

    @Test func settingsGetKeepAwakeDefaultsAndKeepTheirOwn() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"enabled": true, "hour": 7}"#.utf8))
        #expect(old.keepAwakeFor == .untilOff && old.keepAwakeCutoff == .twenty)
        #expect(old.enabled && old.hour == 7)
        var s = Settings()
        s.keepAwakeFor = .twoHours
        s.keepAwakeCutoff = .thirty
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(again.keepAwakeFor == .twoHours && again.keepAwakeCutoff == .thirty)
        #expect(KeepAwakeFor.twoHours.hours == 2 && KeepAwakeFor.untilOff.hours == nil)
    }
}
