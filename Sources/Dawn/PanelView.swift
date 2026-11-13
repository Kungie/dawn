import AppKit
import SwiftUI

/// The window that drops down from the menu bar: the main face, or Settings.
struct PanelView: View {
    @ObservedObject var model: DawnModel

    static let width: CGFloat = 340

    var body: some View {
        Group {
            if model.showSettings { SettingsView(model: model) } else { MainView(model: model) }
        }
        .frame(width: Self.width)
        .background(Look.panel)
        .clipShape(RoundedRectangle(cornerRadius: Look.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Look.radius, style: .continuous).strokeBorder(Look.line, lineWidth: 1))
        .foregroundColor(Look.text)
        .font(Fonts.text())
        .environment(\.colorScheme, .dark)
    }
}

struct PanelHeader: View {
    var trailing: String?
    var body: some View {
        HStack(spacing: 8) {
            DawnLogo().frame(width: 16, height: 16)
            Text("Dawn").font(Fonts.text(13, medium: true))
            Spacer()
            if let trailing { Text(trailing).caption(Look.text2) }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }
}

/// A row separated from the one above by a hairline.
private struct Ruled<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Look.line).frame(height: 1)
            content()
        }
    }
}

// MARK: - Main

struct MainView: View {
    @ObservedObject var model: DawnModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader()
            if let ask = model.ask {
                AskBanner(ask: ask, open: { model.openSession(ask) }) { model.dismissAsk() }
                    .padding(.horizontal, 12).padding(.bottom, 8)
            } else if let done = model.done {
                DoneBanner(done: done, open: { model.openSession(done) }) { model.dismissDone() }
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            ScreenCard(model: model).padding(.horizontal, 12)
            keepAwakeBlock

            if model.window == nil { actions }
            morningRow
            autoRefreshRow

            if let notice = model.notice {
                Text(notice).font(Fonts.text(12)).foregroundColor(Look.bad)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .onTapGesture { model.notice = nil }
            }

            UpdateLine(updater: model.updater)
            Ruled { stats.padding(.horizontal, 16).padding(.vertical, 12) }
            Ruled { footer.padding(.horizontal, 16).padding(.vertical, 10) }
        }
    }

    /// Under the countdown: keep the Mac awake with the lid closed, so Auto refresh and long runs go on.
    /// While it's on, how long and the battery stop sit right under it.
    private var keepAwakeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LidIcon(on: model.keepAwake)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep awake with lid closed").font(Fonts.text(13))
                    if let detail = model.keepAwakeDetail {
                        HStack(spacing: 6) {
                            Dot(color: Look.progress)
                            Text(detail).caption(Look.text2)
                        }
                    }
                }
                Spacer()
                DawnSwitch(isOn: Binding(get: { model.keepAwake }, set: { model.setKeepAwake($0) }))
            }
            if model.keepAwake {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn off after").caption()
                    DawnSegmented(selection: $model.settings.keepAwakeFor)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("On battery, turn off at").caption()
                    DawnSegmented(selection: $model.settings.keepAwakeCutoff)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("System-wide while on. Plug in for long runs, and never put the Mac in a bag like this.")
                        .font(Fonts.text(12)).foregroundColor(Look.text3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if model.keepAwakeHelper {
                        Button("Remove rule") { model.removeKeepAwakeHelper() }
                            .buttonStyle(DawnTextButtonStyle())
                            .help("Takes out the sudoers rule that lets Dawn switch this without a password, and lets the Mac sleep again.")
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
        .help("Stops the Mac from sleeping when you close the lid (pmset disablesleep). The first time asks for your password once. Dawn switches it back when you quit.")
    }

    private var morningRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Morning ping").caption()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d:%02d", model.settings.hour, model.settings.minute))
                        .font(Fonts.mono(22, medium: true)).foregroundColor(model.settings.enabled ? Look.text : Look.text3)
                    Text(model.settings.enabled ? model.daysSummary : "Off")
                        .font(Fonts.text(13)).foregroundColor(Look.text2)
                }
            }
            Spacer()
            DawnSwitch(isOn: $model.settings.enabled)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 10, trailing: 16))
    }

    /// Under the morning ping: keep a window going all day, a new one a minute after the last one ends.
    private var autoRefreshRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Automatically refresh window")
                .font(Fonts.text(13))
                .foregroundColor(model.settings.enabled ? Look.text : Look.text3)
            Spacer()
            DawnSwitch(isOn: $model.settings.followUps)
                .opacity(model.settings.enabled ? 1 : 0.45)
                .disabled(!model.settings.enabled)
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
        .help("After the morning ping, Dawn pings again 5 h 1 min after the last ping, until the next morning.")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(model.firing ? "Sending…" : "Start a window now") { model.fireNow() }
                .buttonStyle(DawnPrimaryButtonStyle())
                .disabled(model.firing)
                .help("Sends one short message through Claude Code now.")
            Button("I started in Claude.ai") { model.markStartedNow() }
                .buttonStyle(DawnTextButtonStyle())
                .help("Chats in Claude.ai and the desktop app don't show up in Claude Code's logs. Tell Dawn here.")
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
    }

    private var stats: some View {
        HStack {
            Text(statsText).font(Fonts.text(13)).foregroundColor(Look.text2)
            Spacer()
            HStack(spacing: 5) {
                ForEach(Array(model.history.filter { $0.trigger != .sync }.prefix(4).reversed())) { r in
                    PingDot(record: r)
                }
            }
            .help("The last four pings, oldest on the left. Filled: sent. Outlined: skipped. Red: failed.")
        }
    }

    private var statsText: String {
        if model.earlyHoursThisWeek > 0 { return String(format: "%.1f h started early this week", model.earlyHoursThisWeek) }
        return model.history.isEmpty ? "No pings yet" : "No early hours yet this week"
    }

    private var footer: some View {
        ZStack {
            // The version sits exactly in the middle, whatever the widths of Settings and Quit.
            Text("v\(DawnInfo.version)").font(Fonts.mono(11)).foregroundColor(Look.text3)
            HStack {
                Button { model.showSettings = true } label: {
                    HStack(spacing: 6) {
                        Text("Settings")
                        if model.setupNeedsAttention { Dot(color: Look.attention) }
                    }
                }
                .buttonStyle(DawnTextButtonStyle())
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(DawnTextButtonStyle(color: Look.text3, hoverColor: Look.text))
            }
        }
    }
}

struct PingDot: View {
    let record: FireRecord
    var body: some View {
        if !record.ok {
            Circle().fill(Look.bad).frame(width: 8, height: 8)
        } else if record.trigger == .skipped {
            Circle().strokeBorder(Look.text3, lineWidth: 1).frame(width: 8, height: 8)
        } else {
            Circle().fill(Look.text2).frame(width: 8, height: 8)
        }
    }
}

// MARK: - Screen card

/// The countdown: a card with Geist Mono numbers, the sun and a 2 px bar for the time left.
struct ScreenCard: View {
    @ObservedObject var model: DawnModel

    private struct Face {
        var label: String
        var right: String
        var big: String
        var rise: Double
        var fill: Double
        var bottomLeft: String
        var bottomRight: String
        var canSync = false
    }

    private var face: Face {
        if model.firing {
            return Face(label: "Sending one ping", right: "Now", big: Fmt.hm.string(from: model.now), rise: 0.6, fill: 0,
                        bottomLeft: "claude -p ping", bottomRight: "Mac awake")
        }
        if let w = model.window {
            let left = max(0, w.interval.end.timeIntervalSince(model.now))
            return Face(label: "Time left", right: "Resets \(Fmt.hm.string(from: w.interval.end))",
                        big: DawnModel.hm(left), rise: 1, fill: left / w.interval.duration,
                        bottomLeft: "From \(Fmt.hm.string(from: w.interval.start)) · \(sourceName(w.source))",
                        bottomRight: w.official ? (w.usedPercent.map { "\(Int($0.rounded()))% used" } ?? "From Claude") : "Estimate",
                        canSync: !w.official)
        }
        if let next = model.nextFire {
            return Face(label: "Next ping", right: Fmt.day.string(from: next), big: Fmt.hm.string(from: next), rise: 0, fill: 0,
                        bottomLeft: "No window running", bottomRight: model.daysSummary)
        }
        return Face(label: "Next ping", right: "Off", big: "--:--", rise: 0, fill: 0,
                    bottomLeft: "No window running", bottomRight: "Morning ping off")
    }

    private func sourceName(_ s: WindowSource) -> String {
        switch s {
        case .ping: return "Dawn's ping"
        case .claudeCode: return "Claude Code"
        case .manual: return "you"
        }
    }

    var body: some View {
        let f = face
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(f.label).caption(Look.text2)
                Spacer()
                Text(f.right).font(Fonts.mono(12)).foregroundColor(Look.text2)
            }
            HStack(alignment: .bottom) {
                Text(f.big).font(Fonts.display(44)).foregroundColor(Look.text).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                DawnLogo(lit: f.rise > 0.5).frame(width: 44, height: 44).padding(.bottom, 6)
            }
            .padding(.top, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Look.line)
                    Capsule().fill(Look.red).frame(width: geo.size.width * min(1, max(0, f.fill)))
                }
            }
            .frame(height: 2)
            .padding(.top, 6)
            HStack {
                Text(f.bottomLeft)
                Spacer()
                if f.canSync {
                    Button("Sync") { model.syncWithClaude() }
                        .buttonStyle(ControlButtonStyle())
                        .help("This is an estimate. Asks Claude Code for the real reset time.")
                } else {
                    Text(f.bottomRight)
                }
            }
            .font(Fonts.mono(11)).foregroundColor(Look.text3).lineLimit(1)
            .frame(minHeight: 24)
            .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
        .surface()
    }
}

struct AskBanner: View {
    let ask: Ask
    let open: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Dot(color: Look.attention, size: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code is waiting\(ask.project.isEmpty ? "" : " · \(ask.project)")").caption(Look.text2)
                Text(ask.message).font(Fonts.text(13)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundColor(Look.text2)
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundColor(Look.text3).pointerCursor()
        }
        .padding(10)
        .surface()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .pointerCursor()
        .help("Go to this Claude Code session")
    }
}

struct DoneBanner: View {
    let done: Ask
    let open: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Dot(color: Look.done, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude finished\(done.project.isEmpty ? "" : " · \(done.project)")").font(Fonts.text(13))
                Text("at \(Fmt.hm.string(from: done.date))").font(Fonts.mono(11)).foregroundColor(Look.text3)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundColor(Look.text2)
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundColor(Look.text3).pointerCursor()
        }
        .padding(10)
        .surface()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .pointerCursor()
        .help("Go to this Claude Code session")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: DawnModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(trailing: "Settings")

            section("Morning ping", first: true) {
                row("Send the morning ping") { DawnSwitch(isOn: $model.settings.enabled) }
                row("Time") {
                    HStack(spacing: 4) {
                        TimeStepper(value: $model.settings.hour, range: 0...23, step: 1)
                        Text(":").font(Fonts.mono(16, medium: true)).foregroundColor(Look.text3)
                        TimeStepper(value: $model.settings.minute, range: 0...55, step: 5)
                    }
                }
                row("Days") { DayPicker(days: $model.settings.weekdays) }
                row("Auto refresh every 5 h 1 min") { DawnSwitch(isOn: $model.settings.followUps) }
                Text("After the morning ping, a new window starts a minute after the last one ends, until the next morning.")
                    .font(Fonts.text(12)).foregroundColor(Look.text3).fixedSize(horizontal: false, vertical: true)
            }

            section("Setup") {
                SetupRow(title: "Claude Code",
                         status: model.signedIn == false ? "Signed out. Sign in once in Terminal."
                             : model.claudePath.map { ($0 as NSString).abbreviatingWithTildeInPath }
                             ?? (model.claudeChecked ? "Not found. Install it and sign in once." : "Looking…"),
                         ok: model.claudePath != nil && model.signedIn != false, mono: model.claudePath != nil && model.signedIn != false) {
                    if model.claudePath == nil {
                        Button("Install") { NSWorkspace.shared.open(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!) }
                            .buttonStyle(ControlButtonStyle())
                    } else if model.signedIn == false {
                        Button("Sign in") { model.signIn() }.buttonStyle(ControlButtonStyle())
                    } else {
                        Button("Recheck") { model.refreshSystem() }.buttonStyle(ControlButtonStyle())
                    }
                }
                SetupRow(title: "Wake the Mac",
                         status: model.wakeStatus ?? "No scheduled wake. The Mac must already be awake.",
                         ok: model.wakeMatchesSchedule) {
                    if model.wakeMatchesSchedule {
                        Button("Remove") { model.removeWake() }.buttonStyle(ControlButtonStyle())
                    } else {
                        Button(model.wakeStatus == nil ? "Set up" : "Replace") { model.setUpWake() }
                            .buttonStyle(ControlButtonStyle())
                    }
                }
                SetupRow(title: "Claude Code hook",
                         status: model.hookInstalled ? "Real reset time, a dot when Claude Code waits, a ping when it's done." : "Off. Add it for the real reset time and the dots.",
                         ok: model.hookInstalled) {
                    Button(model.hookInstalled ? "Remove" : "Add") { model.toggleHook() }
                        .buttonStyle(ControlButtonStyle())
                }
            }

            section("Sound") {
                row("Space ping") { DawnSwitch(isOn: $model.settings.doneSound) }
                HStack {
                    Text(model.hookInstalled ? "When Claude Code ends a task and when Auto refresh starts a window." : "When Auto refresh starts a window. Add the hook above for finished tasks too.")
                        .font(Fonts.text(12)).foregroundColor(Look.text3)
                    Spacer()
                    Button("Play") { SpacePing.play() }.buttonStyle(ControlButtonStyle())
                }
            }

            section("General") {
                row("Menu bar shows") { DawnSegmented(selection: $model.settings.menuBar) }
                row("Open at login") {
                    DawnSwitch(isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) }))
                }
            }

            section("Updates") { UpdatesRows(model: model, updater: model.updater) }

            if !model.history.isEmpty {
                section("Recent pings") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.history.prefix(4)) { r in
                            HStack(spacing: 10) {
                                Text(Fmt.day.string(from: r.date)).frame(width: 30, alignment: .leading)
                                Text(Fmt.hm.string(from: r.date))
                                HStack(spacing: 6) {
                                    Dot(color: dotColor(r))
                                    Text(label(r)).font(Fonts.text(12)).foregroundColor(Look.text2)
                                }
                                Spacer()
                            }
                            .font(Fonts.mono(12)).foregroundColor(Look.text3)
                            .help(r.detail)
                        }
                    }
                }
            }

            if let notice = model.notice {
                Text(notice).font(Fonts.text(12)).foregroundColor(Look.bad)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .onTapGesture { model.notice = nil }
            }

            Ruled {
                HStack {
                    Button("Back") { model.showSettings = false }.buttonStyle(DawnTextButtonStyle())
                    Spacer()
                    Text("v\(DawnInfo.version)").font(Fonts.mono(11)).foregroundColor(Look.text3)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private func label(_ r: FireRecord) -> String {
        switch (r.trigger, r.ok) {
        case (.skipped, _): return "Skipped, window was open"
        case (_, false): return "Failed"
        case (.manual, true): return "Sent by hand"
        case (.followUp, true): return "Sent by Auto refresh"
        case (.sync, true): return "Synced with Claude"
        case (.scheduled, true): return "Sent"
        }
    }

    private func dotColor(_ r: FireRecord) -> Color {
        if !r.ok { return Look.bad }
        return r.trigger == .skipped ? Look.text3 : Look.ok
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, first: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { Rectangle().fill(Look.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 12) {
                Text(title).caption()
                content()
            }
            .padding(EdgeInsets(top: first ? 4 : 14, leading: 16, bottom: 14, trailing: 16))
        }
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(Fonts.text(13))
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// One line in the panel while a new Dawn is out, being installed, or failed to install.
struct UpdateLine: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if let line = updater.panelLine {
            Ruled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Dot(color: dotColor)
                        Text(line).font(Fonts.text(13))
                        Spacer(minLength: 8)
                        switch updater.status {
                        case .available:
                            Button("Update") { Task { await updater.install() } }.buttonStyle(ControlButtonStyle())
                        case .failed:
                            Button("Retry") { Task { await updater.install() } }.buttonStyle(ControlButtonStyle())
                        default:
                            EmptyView()
                        }
                    }
                    if case let .failed(message) = updater.status {
                        Text(message).font(Fonts.text(12)).foregroundColor(Look.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private var dotColor: Color {
        switch updater.status {
        case .installing: return Look.progress
        case .failed: return Look.bad
        default: return Look.todo
        }
    }
}

/// Settings › Updates: the daily check, the button, and what happened last.
struct UpdatesRows: View {
    @ObservedObject var model: DawnModel
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Check for updates daily").font(Fonts.text(13))
                Spacer(minLength: 8)
                DawnSwitch(isOn: $model.settings.checkForUpdates)
            }
            HStack(spacing: 8) {
                Text(updater.statusLine(lastCheck: model.settings.lastUpdateCheck))
                    .font(Fonts.mono(11))
                    .foregroundColor(isAvailable ? Look.text : Look.text3)
                Spacer(minLength: 8)
                if isAvailable {
                    Button("Update now") { Task { await updater.install() } }.buttonStyle(ControlButtonStyle())
                } else {
                    Button("Check for updates") { Task { await updater.check(manual: true) } }
                        .buttonStyle(ControlButtonStyle())
                        .disabled(isBusy)
                }
            }
            if case let .failed(message) = updater.status {
                Text(message).font(Fonts.text(12)).foregroundColor(Look.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isAvailable: Bool { if case .available = updater.status { return true }; return false }
    private var isBusy: Bool {
        switch updater.status {
        case .checking, .installing: return true
        default: return false
        }
    }
}

struct SetupRow<Trailing: View>: View {
    let title: String
    let status: String
    let ok: Bool
    /// The status is a path: Geist Mono.
    var mono = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Dot(color: ok ? Look.ok : Look.attention)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Fonts.text(13, medium: true))
                Text(status).font(mono ? Fonts.mono(11) : Fonts.text(12)).foregroundColor(Look.text3).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            trailing()
        }
    }
}

struct TimeStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 2) {
            arrow("minus") { value = value - step < range.lowerBound ? range.upperBound - (range.upperBound % step) : value - step }
            Text(String(format: "%02d", value)).font(Fonts.mono(16, medium: true)).frame(width: 26).monospacedDigit()
            arrow("plus") { value = value + step > range.upperBound ? range.lowerBound : value + step }
        }
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .medium)).foregroundColor(Look.text2)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Look.card))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Look.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

struct DayPicker: View {
    @Binding var days: Set<Int>
    private let order: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(order, id: \.0) { day, letter in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(letter).font(Fonts.text(11, medium: true))
                        .frame(width: 22, height: 22)
                        .foregroundColor(on ? Look.bg : Look.text3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Look.text : Look.card))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Color.clear : Look.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }
}

enum Fmt {
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"; return f }()
}

// MARK: - Caret

/// Where the caret points, in panel coordinates. Set by the status panel so it sits under the sun.
final class PanelGeometry: ObservableObject {
    @Published var arrowX: CGFloat = PanelView.width / 2
}

/// The panel with a small caret on top that points at the menu bar sun.
struct PanelContainer: View {
    @ObservedObject var model: DawnModel
    @ObservedObject var geometry: PanelGeometry

    static let notchHeight: CGFloat = Caret.height

    var body: some View {
        VStack(spacing: -1) {
            Caret()
                .frame(width: Caret.width, height: Caret.height)
                .padding(.leading, max(0, geometry.arrowX - Caret.width / 2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .zIndex(1)
            PanelView(model: model)
        }
        .frame(width: PanelView.width)
    }
}

/// A 14 × 7 triangle in the panel's colour with a hairline on its two sides, so it joins the panel's border.
struct Caret: View {
    static let width: CGFloat = 14
    static let height: CGFloat = 7

    var body: some View {
        Canvas { ctx, size in
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: size.height + 1))
            shape.addLine(to: CGPoint(x: size.width / 2, y: 0.5))
            shape.addLine(to: CGPoint(x: size.width, y: size.height + 1))
            shape.closeSubpath()
            ctx.fill(shape, with: .color(Look.panel))
            var edge = Path()
            edge.move(to: CGPoint(x: 0, y: size.height))
            edge.addLine(to: CGPoint(x: size.width / 2, y: 0.5))
            edge.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.stroke(edge, with: .color(Look.line), lineWidth: 1)
        }
    }
}
