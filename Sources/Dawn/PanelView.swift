import AppKit
import SwiftUI

/// The window that drops down from the menu bar.
struct PanelView: View {
    @ObservedObject var model: DawnModel

    private var showSetup: Bool { model.showSetup }

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScreenCard(model: model).padding(.horizontal, 14)
            if let ask = model.ask { AskBanner(ask: ask) { model.dismissAsk() }.padding(.horizontal, 14).padding(.top, 8) }
            schedule.padding(.horizontal, 14).padding(.top, 14)
            divider
            setup.padding(.horizontal, 14)
            if !model.history.isEmpty { divider; recent.padding(.horizontal, 14) }
            if let notice = model.notice {
                Text(notice).font(Fonts.grotesk(11.5)).foregroundColor(Ident.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.top, 10)
                    .onTapGesture { model.notice = nil }
            }
            footer.padding(14)
        }
        .frame(width: Self.width)
        .background(Ident.black)
        .foregroundColor(Ident.cream)
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle().fill(Ident.line).frame(height: 1).padding(.vertical, 12)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            IdentChip(size: 18)
            Text("DAWN").font(Fonts.archivo(17)).tracking(-0.3)
            Spacer()
            Text("VEKTOR LABS").font(Fonts.mono(9, bold: true)).foregroundColor(Ident.red)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
    }

    // MARK: schedule

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.settings.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Morning ping").font(Fonts.grotesk(13, weight: 600))
                    Text("Starts your Claude window before you sit down.")
                        .font(Fonts.grotesk(11)).foregroundColor(Ident.dim)
                }
            }
            .toggleStyle(IdentToggleStyle())

            HStack(spacing: 8) {
                TimeStepper(value: $model.settings.hour, range: 0...23, step: 1)
                Text(":").font(Fonts.vt(26)).foregroundColor(Ident.dim)
                TimeStepper(value: $model.settings.minute, range: 0...55, step: 5)
                Spacer()
                DayPicker(days: $model.settings.weekdays)
            }
            .opacity(model.settings.enabled ? 1 : 0.45)
        }
    }

    // MARK: setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { withAnimation(.easeOut(duration: 0.15)) { model.showSetup.toggle() } } label: {
                HStack {
                    Text("SETUP").font(Fonts.mono(10, bold: true)).foregroundColor(Ident.dim)
                    if !setupComplete { Rectangle().fill(Ident.red).frame(width: 6, height: 6) }
                    Spacer()
                    Text(showSetup ? "–" : "+").font(Fonts.mono(12, bold: true)).foregroundColor(Ident.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSetup || !setupComplete {
                SetupRow(title: "Claude Code",
                         status: model.claudePath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? (model.claudeChecked ? "not found: install it and sign in once" : "looking…"),
                         ok: model.claudePath != nil) {
                    if model.claudePath == nil {
                        Button("Install") { NSWorkspace.shared.open(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!) }
                            .buttonStyle(GhostButtonStyle(compact: true))
                    } else {
                        Button("Recheck") { model.refreshSystem() }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                SetupRow(title: "Wake the Mac",
                         status: model.wakeStatus.map { $0 } ?? "no scheduled wake, the Mac must already be awake",
                         ok: model.wakeMatchesSchedule) {
                    if model.wakeMatchesSchedule {
                        Button("Remove") { model.removeWake() }.buttonStyle(GhostButtonStyle(compact: true))
                    } else {
                        Button(model.wakeStatus == nil ? "Set up" : "Replace") { model.setUpWake() }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                SetupRow(title: "Claude Code hook",
                         status: model.hookInstalled ? "a dot appears when Claude Code waits for you" : "off",
                         ok: model.hookInstalled) {
                    Button(model.hookInstalled ? "Remove" : "Add") { model.toggleHook() }.buttonStyle(GhostButtonStyle(compact: true))
                }
                Toggle(isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) })) {
                    Text("Open at login").font(Fonts.grotesk(12, weight: 500))
                }
                .toggleStyle(IdentToggleStyle())
            }
        }
    }

    private var setupComplete: Bool {
        model.claudePath != nil && (!model.settings.enabled || model.wakeMatchesSchedule)
    }

    // MARK: recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("RECENT").font(Fonts.mono(10, bold: true)).foregroundColor(Ident.dim)
                Spacer()
                if model.earlyHoursThisWeek > 0 {
                    Text(String(format: "%.1f H STARTED EARLY THIS WEEK", model.earlyHoursThisWeek))
                        .font(Fonts.vt(15)).foregroundColor(Ident.red)
                }
            }
            .padding(.bottom, 3)
            ForEach(model.history.prefix(4)) { r in
                HStack(spacing: 8) {
                    Text(Fmt.day.string(from: r.date).uppercased()).frame(width: 34, alignment: .leading)
                    Text(Fmt.hm.string(from: r.date))
                    Text(label(r)).foregroundColor(r.ok ? (r.trigger == .skipped ? Ident.dim : Ident.ok) : Ident.red)
                    Spacer()
                }
                .font(Fonts.vt(16)).foregroundColor(Ident.cream2)
                .help(r.detail)
            }
        }
    }

    private func label(_ r: FireRecord) -> String {
        switch (r.trigger, r.ok) {
        case (.skipped, _): return "SKIPPED · WINDOW WAS OPEN"
        case (_, false): return "FAILED"
        case (.manual, true): return "PING · BY HAND"
        case (.scheduled, true): return "PING · OK"
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button { model.fireNow() } label: { Text(model.firing ? "PINGING…" : "START A WINDOW NOW") }
                .buttonStyle(RedButtonStyle())
                .disabled(model.firing || model.window != nil)
                .opacity(model.window != nil ? 0.45 : 1)
                .help(model.window != nil ? "A window is already running." : "Sends one short message through Claude Code now.")
            HStack {
                Button("I started in Claude.ai") { model.markStartedNow() }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .help("Chats in Claude.ai and the desktop app don't show up in Claude Code's logs. Tell Dawn here.")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(GhostButtonStyle(compact: true))
            }
        }
    }
}

// MARK: - Screen card

/// Dawn's "screen": the same black glass, VT323 type and striped sun as the instrument.
struct ScreenCard: View {
    @ObservedObject var model: DawnModel

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x1C0B09), Ident.black], center: .center, startRadius: 4, endRadius: 220)
            content.padding(14)
            Scanlines()
        }
        .frame(height: 156)
        .clipped()
        .overlay(Rectangle().strokeBorder(Ident.line, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        if model.firing {
            VStack(spacing: 4) {
                StripedSun(rise: 0.45).frame(width: 150, height: 70)
                Text("SENDING ONE SHORT PING").font(Fonts.vt(18)).foregroundColor(Ident.cream2)
                Text("$ claude -p \"ping\"").font(Fonts.vt(15)).foregroundColor(Ident.dim)
            }
        } else if let w = model.window {
            open(w)
        } else {
            idle
        }
    }

    private func open(_ w: UsageWindow) -> some View {
        let total = w.interval.duration
        let left = max(0, w.interval.end.timeIntervalSince(model.now))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WINDOW OPEN").foregroundColor(Ident.red)
                Spacer()
                Text("RESET \(Fmt.hm.string(from: w.interval.end))").foregroundColor(Ident.cream2)
            }
            .font(Fonts.vt(17))
            HStack(alignment: .bottom) {
                Text(DawnModel.hm(left)).font(Fonts.vt(72)).foregroundColor(Ident.cream).monospacedDigit()
                Text("LEFT").font(Fonts.vt(17)).foregroundColor(Ident.dim).padding(.bottom, 14)
                Spacer()
                if w.source == .ping { StripedSun(rise: 0.8).frame(width: 64, height: 40).padding(.bottom, 14) }
            }
            .frame(height: 70)
            ProgressStripes(fraction: 1 - left / total).frame(height: 9)
            Text("STARTED \(Fmt.hm.string(from: w.interval.start)) · BY \(w.source.rawValue.uppercased()) · ESTIMATE")
                .font(Fonts.vt(14)).foregroundColor(Ident.dim).padding(.top, 7)
        }
    }

    private var idle: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("NO WINDOW RUNNING").font(Fonts.vt(17)).foregroundColor(Ident.dim)
                Text(model.nextFire.map { Fmt.hm.string(from: $0) } ?? "--:--")
                    .font(Fonts.vt(66)).foregroundColor(Ident.cream).frame(height: 66)
                Text(model.nextFire.map { "NEXT PING · \(Fmt.day.string(from: $0).uppercased())" } ?? "MORNING PING IS OFF")
                    .font(Fonts.vt(16)).foregroundColor(model.nextFire == nil ? Ident.dim : Ident.red)
            }
            Spacer()
            StripedSun(rise: 0.35).frame(width: 110, height: 78)
        }
    }
}

struct ProgressStripes: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ident.line)
                Rectangle().fill(Ident.red).frame(width: geo.size.width * min(1, max(0, fraction)))
                HStack(spacing: 4) {
                    ForEach(0..<60, id: \.self) { _ in Rectangle().fill(Ident.black.opacity(0.55)).frame(width: 1.5) }
                }
            }
        }
        .clipped()
    }
}

struct AskBanner: View {
    let ask: Ask
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Ident.cream).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("CLAUDE CODE IS WAITING\(ask.project.isEmpty ? "" : " · \(ask.project.uppercased())")")
                    .font(Fonts.vt(16))
                Text(ask.message).font(Fonts.grotesk(11.5, weight: 500)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("×") { dismiss() }.buttonStyle(.plain).font(Fonts.mono(13, bold: true))
        }
        .foregroundColor(Ident.cream)
        .padding(10)
        .background(Ident.red)
    }
}

struct SetupRow<Trailing: View>: View {
    let title: String
    let status: String
    let ok: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle().fill(ok ? Ident.ok : Ident.red).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Fonts.grotesk(12, weight: 600))
                Text(status).font(Fonts.grotesk(10.5)).foregroundColor(Ident.dim).lineLimit(2)
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
            arrow("−") { value = value - step < range.lowerBound ? range.upperBound - (range.upperBound % step) : value - step }
            Text(String(format: "%02d", value)).font(Fonts.vt(30)).frame(width: 30).monospacedDigit()
            arrow("+") { value = value + step > range.upperBound ? range.lowerBound : value + step }
        }
    }

    private func arrow(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s).font(Fonts.mono(12, bold: true)).frame(width: 18, height: 22)
                .overlay(Rectangle().strokeBorder(Ident.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    Text(letter).font(Fonts.mono(10, bold: true))
                        .frame(width: 17, height: 20)
                        .foregroundColor(on ? Ident.cream : Ident.dim)
                        .background(on ? Ident.red : Ident.black2)
                        .overlay(Rectangle().strokeBorder(on ? Color.clear : Ident.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum Fmt {
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"; return f }()
}

/// The menu bar item: the striped-sun icon, plus time left while a window runs.
struct MenuBarLabel: View {
    @ObservedObject var model: DawnModel
    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(asking: model.ask != nil))
            if let t = model.menuBarText { Text(t).monospacedDigit() }
        }
    }
}
