import AppKit
import Combine
import Foundation

struct FireRecord: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable { case scheduled, manual, skipped }
    var id = UUID()
    let date: Date
    let trigger: Trigger
    let ok: Bool
    let detail: String
}

struct Settings: Codable, Equatable {
    var enabled = false
    var hour = 6
    var minute = 30
    var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7] // Calendar weekday numbers, 1 = Sunday
    var model = "haiku"
}

struct Ask: Equatable {
    let message: String
    let project: String
    let date: Date
}

enum WindowSource: String { case claudeCode = "Claude Code", ping = "Dawn's ping", manual = "you" }

struct UsageWindow: Equatable {
    let interval: DateInterval
    let source: WindowSource
}

@MainActor
final class DawnModel: ObservableObject {
    static let shared = DawnModel()

    @Published var settings: Settings { didSet { if settings != oldValue { save(); refreshNextFire() } } }
    @Published private(set) var now = Date()
    @Published private(set) var window: UsageWindow?
    @Published private(set) var history: [FireRecord]
    @Published private(set) var firing = false
    @Published private(set) var ask: Ask?
    @Published private(set) var claudePath: String?
    @Published private(set) var claudeChecked = false
    @Published private(set) var wakeStatus: String?
    @Published private(set) var hookInstalled = false
    @Published private(set) var loginItem = false
    @Published private(set) var nextFire: Date?
    @Published var notice: String?
    @Published var showSetup = false
    /// Hours of window that were already running when your own work started, this week (Claude Code only).
    @Published private(set) var earlyHoursThisWeek: Double = 0

    private let log = UsageLog()
    private let defaults = UserDefaults.standard
    private var manualStarts: [Date] { didSet { defaults.set(manualStarts, forKey: "manualStarts") } }
    private var lastScheduledDay: Date? { didSet { defaults.set(lastScheduledDay, forKey: "lastScheduledDay") } }
    private var ownActivity: [Date] = []
    private var pingActivity: [Date] = []
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private let work = DispatchQueue(label: "labs.vektor.dawn.work", qos: .utility)
    private var demo = false

    init() {
        settings = (defaults.data(forKey: "settings")).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        history = (defaults.data(forKey: "history")).flatMap { try? JSONDecoder().decode([FireRecord].self, from: $0) } ?? []
        manualStarts = (defaults.array(forKey: "manualStarts") as? [Date]) ?? []
        lastScheduledDay = defaults.object(forKey: "lastScheduledDay") as? Date
    }

    // MARK: lifecycle

    func start() {
        refreshSystem()
        rescan()
        refreshNextFire()
        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Give Wi-Fi a moment after a scheduled wake, then check the schedule.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.tick()
            }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: HookCommand.notification, object: nil, queue: .main) { [weak self] note in
            let message = note.userInfo?["message"] as? String ?? "Claude Code is waiting for you"
            let project = note.userInfo?["project"] as? String ?? ""
            Task { @MainActor in
                self?.ask = Ask(message: message, project: project, date: Date())
            }
        })
    }

    private func tick() {
        now = Date()
        if let a = ask, now.timeIntervalSince(a.date) > 15 * 60 { ask = nil }
        updateWindow()
        checkSchedule()
    }

    func refreshSystem() {
        work.async {
            let claude = PingRunner.locateClaude()
            let wake = WakeSchedule.current()
            let hook = ClaudeHook.isInstalled()
            Task { @MainActor in
                self.claudePath = claude
                self.claudeChecked = true
                self.wakeStatus = wake
                self.hookInstalled = hook
                self.loginItem = LoginItem.isEnabled
            }
        }
    }

    // MARK: window

    func rescan() {
        guard !demo else { return }
        let log = self.log
        work.async {
            let acts = log.recentActivity()
            Task { @MainActor in
                self.ownActivity = acts.filter { !$0.isPing }.map(\.date)
                self.pingActivity = acts.filter(\.isPing).map(\.date)
                if let a = self.ask, let last = self.ownActivity.last, last > a.date { self.ask = nil }
                self.updateWindow()
                self.updateWeek()
            }
        }
    }

    private func updateWindow() {
        guard !demo else { return }
        now = Date()
        let day = now.addingTimeInterval(-24 * 3600)
        let pings = (history.filter { $0.ok && $0.trigger != .skipped }.map(\.date) + pingActivity).filter { $0 > day }
        let manual = manualStarts.filter { $0 > day }
        let all = ownActivity + pings + manual
        guard let block = UsageLog.blocks(from: all).last, block.end > now else { window = nil; return }
        let first = all.filter { block.contains($0) }.min() ?? block.start
        let source: WindowSource = pings.contains(first) ? .ping : (manual.contains(first) ? .manual : .claudeCode)
        window = UsageWindow(interval: block, source: source)
    }

    private func updateWeek() {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        var total = 0.0
        for ping in history where ping.ok && ping.trigger == .scheduled && ping.date > weekAgo {
            let start = Calendar.current.dateInterval(of: .hour, for: ping.date)?.start ?? ping.date
            if let firstOwn = ownActivity.first(where: { $0 > ping.date && $0 < start.addingTimeInterval(UsageLog.windowLength) }) {
                total += firstOwn.timeIntervalSince(start) / 3600
            }
        }
        earlyHoursThisWeek = total
    }

    /// The user started a chat in Claude.ai or the desktop app, which Dawn can't see in the logs.
    func markStartedNow() {
        manualStarts = (manualStarts + [Date()]).filter { $0 > Date().addingTimeInterval(-24 * 3600) }
        updateWindow()
    }

    // MARK: schedule

    private func fireDate(on day: Date) -> Date? {
        Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day)
    }

    func refreshNextFire() {
        guard settings.enabled, !settings.weekdays.isEmpty else { nextFire = nil; return }
        let cal = Calendar.current
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()),
                  settings.weekdays.contains(cal.component(.weekday, from: day)),
                  let date = fireDate(on: day) else { continue }
            if offset == 0 && (date < Date() || lastScheduledDay.map { cal.isDateInToday($0) } == true) { continue }
            nextFire = date
            return
        }
        nextFire = nil
    }

    private func checkSchedule() {
        guard settings.enabled, !firing, !demo else { return }
        let cal = Calendar.current
        let now = Date()
        guard settings.weekdays.contains(cal.component(.weekday, from: now)),
              let due = fireDate(on: now), now >= due, now < due.addingTimeInterval(90 * 60) else { return }
        if let last = lastScheduledDay, cal.isDate(last, inSameDayAs: now) { return }
        lastScheduledDay = now
        if let w = window, w.interval.end > now {
            record(FireRecord(date: now, trigger: .skipped, ok: true, detail: "a window was already running"))
            refreshNextFire()
            return
        }
        fire(.scheduled)
    }

    func fireNow() { fire(.manual) }

    private func fire(_ trigger: FireRecord.Trigger) {
        guard !firing else { return }
        firing = true
        let model = settings.model
        let known = claudePath
        work.async {
            guard let claude = known ?? PingRunner.locateClaude() else {
                Task { @MainActor in
                    self.firing = false
                    self.notice = "Claude Code isn't installed, so there is nothing to send the ping with."
                    self.record(FireRecord(date: Date(), trigger: trigger, ok: false, detail: "claude not found"))
                }
                return
            }
            let result = PingRunner.ping(claude: claude, model: model)
            Task { @MainActor in
                self.firing = false
                self.record(FireRecord(date: Date(), trigger: trigger, ok: result.ok, detail: result.detail))
                if !result.ok { self.notice = "Ping failed: \(result.detail)" }
                self.refreshNextFire()
                self.rescan()
            }
        }
    }

    private func record(_ r: FireRecord) {
        history = Array(([r] + history).prefix(30))
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "history") }
        updateWindow()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings") }
    }

    // MARK: setup actions

    func setUpWake() {
        notice = WakeSchedule.install(hour: settings.hour, minute: settings.minute, weekdays: settings.weekdays)
        refreshSystem()
    }

    func removeWake() {
        notice = WakeSchedule.remove()
        refreshSystem()
    }

    func toggleHook() {
        let adding = !hookInstalled
        notice = adding ? ClaudeHook.install() : ClaudeHook.remove()
        if notice == nil && adding && !Bundle.main.bundlePath.hasPrefix("/Applications") {
            notice = "Hook added. It points at this copy of Dawn, so move Dawn to Applications and add it again."
        }
        refreshSystem()
    }

    func setLoginItem(_ on: Bool) {
        notice = LoginItem.set(on)
        loginItem = LoginItem.isEnabled
    }

    func dismissAsk() { ask = nil }

    // MARK: derived

    var wakeMatchesSchedule: Bool {
        guard let s = wakeStatus?.lowercased() else { return false }
        let total = (settings.hour * 60 + settings.minute + 24 * 60 - 1) % (24 * 60)
        let h12 = (total / 60) % 12 == 0 ? 12 : (total / 60) % 12
        let ampm = total / 60 < 12 ? "am" : "pm"
        return s.contains("wake") && s.contains(String(format: "%d:%02d%@", h12, total % 60, ampm))
    }

    /// The short text next to the menu bar icon: time left in the window.
    var menuBarText: String? {
        guard let w = window else { return nil }
        return Self.hm(w.interval.end.timeIntervalSince(now))
    }

    static func hm(_ t: TimeInterval) -> String {
        let m = max(0, Int(t / 60))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // MARK: demo state for README screenshots

    static func demoModel(asking: Bool = false, idle: Bool = false) -> DawnModel {
        let m = DawnModel()
        m.demo = true
        m.settings = Settings(enabled: true, hour: 6, minute: 30, weekdays: [2, 3, 4, 5, 6], model: "haiku")
        let cal = Calendar.current
        let today630 = cal.date(bySettingHour: 6, minute: 30, second: 0, of: Date())!
        m.now = cal.date(bySettingHour: 9, minute: 16, second: 0, of: Date())!
        if !idle {
            m.window = UsageWindow(interval: DateInterval(start: cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!,
                                                          duration: UsageLog.windowLength), source: .ping)
        }
        m.history = (0..<4).map { FireRecord(date: today630.addingTimeInterval(Double(-$0) * 86400), trigger: .scheduled, ok: true, detail: "Pong!") }
        m.claudePath = "/Users/you/.local/bin/claude"
        m.claudeChecked = true
        m.wakeStatus = "wake at 6:29AM weekdays only"
        m.hookInstalled = true
        m.loginItem = true
        m.earlyHoursThisWeek = 9.5
        m.nextFire = cal.date(byAdding: .day, value: 1, to: today630)
        if asking { m.ask = Ask(message: "Claude needs your permission to use Bash", project: "your-app", date: m.now) }
        return m
    }
}
