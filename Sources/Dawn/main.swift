import AppKit

// Dawn is one binary with a few ways in:
//   Dawn                 the menu bar app
//   Dawn hook [stop]     called by Claude Code's Notification / Stop hooks, forwards them to the app and exits
//   Dawn ping-sound      plays the "Claude finished" sound
//   Dawn snapshot <dir>  renders the panel with demo data (README screenshots)
//   Dawn status          prints what Dawn sees: claude, the scheduled wake, the current window estimate
//   Dawn icon <file>     renders the 1024 px app icon (used by scripts/build-app.sh)
let args = CommandLine.arguments
switch args.dropFirst().first {
case "hook":
    HookCommand.run(stop: args.count > 2 && args[2] == "stop")
    exit(0)
case "session":
    // Debug: what `Dawn hook` would report about the session it runs in.
    let s = SessionInfo.current()
    print("host:", s.hostBundleID ?? "none", s.hostPID.map(String.init) ?? "", "tty:", s.tty ?? "none")
    exit(0)
case "ping-sound":
    _ = NSApplication.shared
    SpacePing.play()
    Thread.sleep(forTimeInterval: 2.4)
    exit(0)
case "--version":
    print("Dawn \(DawnInfo.version)")
    exit(0)
case "status":
    let acts = UsageLog().recentActivity()
    let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
    print("claude:      \(PingRunner.locateClaude() ?? "not found")")
    print("wake:        \(WakeSchedule.current() ?? "none")")
    print("hook:        \(ClaudeHook.isInstalled() ? "installed" : "not installed")")
    print("activity:    \(acts.count) Claude replies in the last 24 h (\(acts.filter(\.isPing).count) from pings)")
    if let block = UsageLog.blocks(from: acts.map(\.date)).last, block.end > Date() {
        print("window:      \(f.string(from: block.start)) to \(f.string(from: block.end)), \(Int(block.end.timeIntervalSinceNow / 60)) min left (estimate)")
    } else {
        print("window:      none running")
    }
    exit(0)
case "snapshot":
    _ = NSApplication.shared
    Fonts.register()
    MainActor.assumeIsolated { Snapshot.run(to: args.count > 2 ? args[2] : "docs") }
    exit(0)
case "icon":
    _ = NSApplication.shared
    MainActor.assumeIsolated { Snapshot.icon(to: args.count > 2 ? args[2] : "icon.png") }
    exit(0)
default:
    Fonts.register()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
