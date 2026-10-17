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
        .background(Ident.black)
        .overlay(Rectangle().strokeBorder(Ident.line, lineWidth: 1))
        .foregroundColor(Ident.cream)
        .environment(\.colorScheme, .dark)
    }
}

struct PanelHeader: View {
    var trailing: String?
    var body: some View {
        HStack(spacing: 10) {
            DawnChip(size: 22)
            Wordmark()
            Spacer()
            if let trailing { Text(trailing).dawnLabel() }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }
}

/// A row separated from the one above by a hairline.
private struct Ruled<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Ident.line).frame(height: 1)
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
                    .padding(.horizontal, 12).padding(.bottom, 10)
            } else if let done = model.done {
                DoneBanner(done: done, open: { model.openSession(done) }) { model.dismissDone() }
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            ScreenCard(model: model).padding(.horizontal, 12)

            if model.window == nil { actions }
            morningRow
            autoRefreshRow

            if let notice = model.notice {
                Text(notice).font(Fonts.grotesk(12)).foregroundColor(Ident.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .onTapGesture { model.notice = nil }
            }

            Ruled { stats.padding(.horizontal, 16).padding(.vertical, 12) }
            Ruled { footer.padding(.horizontal, 16).padding(.vertical, 12) }
        }
    }

    private var morningRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Morning ping").dawnLabel()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%02d:%02d", model.settings.hour, model.settings.minute))
                        .font(Fonts.vt(34)).foregroundColor(model.settings.enabled ? Ident.cream : Ident.dim)
                    Text(model.settings.enabled ? model.daysSummary : "Off")
                        .font(Fonts.grotesk(13)).foregroundColor(Ident.cream2)
                }
            }
            Spacer()
            DawnSwitch(isOn: $model.settings.enabled)
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 12, trailing: 16))
    }

    /// Under the morning ping: keep a window going all day, a new one a minute after the last one ends.
    private var autoRefreshRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Automatically refresh window")
                .font(Fonts.grotesk(13, weight: 500))
                .foregroundColor(model.settings.enabled ? Ident.cream : Ident.dim)
            Spacer()
            DawnSwitch(isOn: $model.settings.followUps)
                .opacity(model.settings.enabled ? 1 : 0.45)
                .disabled(!model.settings.enabled)
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
        .help("After the morning ping, Dawn pings again 5 h 1 min after the last ping, until the next morning.")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(model.firing ? "Sending…" : "Start a window now") { model.fireNow() }
                .buttonStyle(DawnPrimaryButtonStyle())
                .disabled(model.firing)
                .help("Sends one short message through Claude Code now.")
            Button("I started in Claude.ai") { model.markStartedNow() }
                .buttonStyle(DawnTextButtonStyle())
                .help("Chats in Claude.ai and the desktop app don't show up in Claude Code's logs. Tell Dawn here.")
        }
        .padding(16)
    }

    private var stats: some View {
        HStack {
            Text(statsText).font(Fonts.grotesk(13)).foregroundColor(Ident.cream2)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(model.history.filter { $0.trigger != .sync }.prefix(4).reversed())) { r in
                    PingSquare(record: r)
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
            Text("v\(DawnInfo.version)").font(Fonts.vt(17)).foregroundColor(Ident.dim)
            HStack {
                Button { model.showSettings = true } label: {
                    HStack(spacing: 6) {
                        Text("Settings")
                        if model.setupNeedsAttention { Rectangle().fill(Ident.red).frame(width: 6, height: 6) }
                    }
                }
                .buttonStyle(DawnTextButtonStyle())
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(DawnTextButtonStyle(color: Ident.dim, hoverColor: Ident.red))
            }
        }
    }
}

struct PingSquare: View {
    let record: FireRecord
    var body: some View {
        if !record.ok {
            Rectangle().fill(Ident.red).frame(width: 10, height: 10)
        } else if record.trigger == .skipped {
            Rectangle().strokeBorder(Ident.dim, lineWidth: 1).frame(width: 10, height: 10)
        } else {
            Rectangle().fill(Ident.cream).frame(width: 10, height: 10)
        }
    }
}

// MARK: - Screen card

/// Dawn's "screen": black glass with a red glow and scanlines, VT323 numerals and the striped sun.
struct ScreenCard: View {
    @ObservedObject var model: DawnModel

    private struct Face {
        var label: String
        var labelColor: Color
        var right: String
        var rightColor: Color
        var big: String
        var bigSize: CGFloat
        var rise: Double
        var sunWidth: CGFloat
        var fill: Double
        var bottomLeft: String
        var bottomRight: String
        var canSync = false
    }

    private var face: Face {
        if model.firing {
            return Face(label: "Sending one ping", labelColor: Ident.red, right: "NOW", rightColor: Ident.cream2,
                        big: Fmt.hm.string(from: model.now), bigSize: 96, rise: 0.6, sunWidth: 80, fill: 0,
                        bottomLeft: "$ CLAUDE -P \"PING\"", bottomRight: "MAC AWAKE")
        }
        if let w = model.window {
            let left = max(0, w.interval.end.timeIntervalSince(model.now))
            return Face(label: "Time left", labelColor: Ident.red,
                        right: "RESETS \(Fmt.hm.string(from: w.interval.end))", rightColor: Ident.cream2,
                        big: DawnModel.hm(left), bigSize: 116, rise: 1, sunWidth: 96, fill: left / w.interval.duration,
                        bottomLeft: "FROM \(Fmt.hm.string(from: w.interval.start)) · \(sourceName(w.source))",
                        bottomRight: w.official ? (w.usedPercent.map { "\(Int($0.rounded()))% USED" } ?? "FROM CLAUDE") : "ESTIMATE",
                        canSync: !w.official)
        }
        if let next = model.nextFire {
            return Face(label: "Next ping", labelColor: Ident.dim, right: Fmt.day.string(from: next).uppercased(), rightColor: Ident.red,
                        big: Fmt.hm.string(from: next), bigSize: 96, rise: 0, sunWidth: 80, fill: 0,
                        bottomLeft: "NO WINDOW RUNNING", bottomRight: model.daysSummary.uppercased())
        }
        return Face(label: "Next ping", labelColor: Ident.dim, right: "OFF", rightColor: Ident.dim,
                    big: "--:--", bigSize: 96, rise: 0, sunWidth: 80, fill: 0,
                    bottomLeft: "NO WINDOW RUNNING", bottomRight: "MORNING PING OFF")
    }

    private func sourceName(_ s: WindowSource) -> String {
        switch s {
        case .ping: return "DAWN'S PING"
        case .claudeCode: return "CLAUDE CODE"
        case .manual: return "YOU"
        }
    }

    var body: some View {
        let f = face
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(f.label).dawnLabel(f.labelColor)
                Spacer()
                Text(f.right).font(Fonts.vt(20)).foregroundColor(f.rightColor)
            }
            HStack(alignment: .bottom) {
                Text(f.big).font(Fonts.vt(f.bigSize)).foregroundColor(Ident.cream).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(height: f.bigSize * 0.78, alignment: .bottom)
                Spacer(minLength: 8)
                DawnSun(rise: f.rise).frame(width: f.sunWidth, height: f.sunWidth / 2)
            }
            .padding(.top, 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Ident.line)
                    Rectangle().fill(Ident.cream).frame(width: geo.size.width * min(1, max(0, f.fill)))
                }
            }
            .frame(height: 4)
            HStack {
                Text(f.bottomLeft)
                Spacer()
                if f.canSync {
                    Button("SYNC ↻") { model.syncWithClaude() }
                        .buttonStyle(.plain)
                        .foregroundColor(Ident.red)
                        .pointerCursor()
                        .help("This is an estimate. Sends one short ping inside the open window to get Claude's own reset time.")
                } else {
                    Text(f.bottomRight)
                }
            }
            .font(Fonts.vt(18)).foregroundColor(Ident.dim).lineLimit(1)
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .background(
            ZStack {
                Ident.black
                EllipticalGradient(colors: [Ident.red.opacity(0.18), Ident.red.opacity(0)],
                                   center: UnitPoint(x: 0.65, y: 0.45), startRadiusFraction: 0, endRadiusFraction: 0.7)
                Scanlines(opacity: 0.45)
            }
        )
        .overlay(Rectangle().strokeBorder(Ident.line, lineWidth: 1))
    }
}

struct AskBanner: View {
    let ask: Ask
    let open: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Ident.cream).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code is waiting\(ask.project.isEmpty ? "" : " · \(ask.project)")").dawnLabel(Ident.cream)
                Text(ask.message).font(Fonts.grotesk(12.5, weight: 500)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text("↗").font(Fonts.mono(13, bold: true)).help("Go to this Claude Code session")
            Button("×") { dismiss() }.buttonStyle(.plain).font(Fonts.mono(13, bold: true)).pointerCursor()
        }
        .foregroundColor(Ident.cream)
        .padding(10)
        .background(Ident.red)
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
            Circle().fill(Ident.red).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude finished\(done.project.isEmpty ? "" : " · \(done.project)")").dawnLabel(Ident.cream)
                Text("at \(Fmt.hm.string(from: done.date))").font(Fonts.vt(17)).foregroundColor(Ident.dim)
            }
            Spacer(minLength: 4)
            Text("↗").font(Fonts.mono(13, bold: true)).foregroundColor(Ident.cream2)
            Button("×") { dismiss() }.buttonStyle(.plain).font(Fonts.mono(13, bold: true)).foregroundColor(Ident.cream).pointerCursor()
        }
        .padding(10)
        .background(Ident.black2)
        .overlay(Rectangle().strokeBorder(Ident.line, lineWidth: 1))
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
                    HStack(spacing: 6) {
                        TimeStepper(value: $model.settings.hour, range: 0...23, step: 1)
                        Text(":").font(Fonts.vt(26)).foregroundColor(Ident.dim)
                        TimeStepper(value: $model.settings.minute, range: 0...55, step: 5)
                    }
                }
                row("Days") { DayPicker(days: $model.settings.weekdays) }
                row("Auto refresh every 5 h 1 min") { DawnSwitch(isOn: $model.settings.followUps) }
                Text("After the morning ping, a new window starts a minute after the last one ends, until the next morning.")
                    .font(Fonts.grotesk(11.5)).foregroundColor(Ident.dim).fixedSize(horizontal: false, vertical: true)
            }

            section("Setup") {
                SetupRow(title: "Claude Code",
                         status: model.claudePath.map { ($0 as NSString).abbreviatingWithTildeInPath }
                             ?? (model.claudeChecked ? "Not found. Install it and sign in once." : "Looking…"),
                         ok: model.claudePath != nil) {
                    if model.claudePath == nil {
                        Button("Install") { NSWorkspace.shared.open(URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!) }
                            .buttonStyle(GhostButtonStyle(compact: true))
                    } else {
                        Button("Recheck") { model.refreshSystem() }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                SetupRow(title: "Wake the Mac",
                         status: model.wakeStatus ?? "No scheduled wake. The Mac must already be awake.",
                         ok: model.wakeMatchesSchedule) {
                    if model.wakeMatchesSchedule {
                        Button("Remove") { model.removeWake() }.buttonStyle(GhostButtonStyle(compact: true))
                    } else {
                        Button(model.wakeStatus == nil ? "Set up" : "Replace") { model.setUpWake() }
                            .buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                SetupRow(title: "Claude Code hook",
                         status: model.hookInstalled ? "Real reset time, a dot when Claude Code waits, a ping when it's done." : "Off. Add it for the real reset time and the dots.",
                         ok: model.hookInstalled) {
                    Button(model.hookInstalled ? "Remove" : "Add") { model.toggleHook() }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
            }

            section("Sound") {
                row("Space ping") { DawnSwitch(isOn: $model.settings.doneSound) }
                HStack {
                    Text(model.hookInstalled ? "When Claude Code ends a task and when Auto refresh starts a window." : "When Auto refresh starts a window. Add the hook above for finished tasks too.")
                        .font(Fonts.grotesk(11.5)).foregroundColor(Ident.dim)
                    Spacer()
                    Button("Play") { SpacePing.play() }.buttonStyle(GhostButtonStyle(compact: true))
                }
            }

            section("General") {
                row("Show time in the menu bar") { DawnSwitch(isOn: $model.settings.showMenuBarTime) }
                row("Open at login") {
                    DawnSwitch(isOn: Binding(get: { model.loginItem }, set: { model.setLoginItem($0) }))
                }
            }

            if !model.history.isEmpty {
                section("Recent pings") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(model.history.prefix(4)) { r in
                            HStack(spacing: 8) {
                                Text(Fmt.day.string(from: r.date).uppercased()).frame(width: 34, alignment: .leading)
                                Text(Fmt.hm.string(from: r.date))
                                Text(label(r)).foregroundColor(r.ok ? (r.trigger == .skipped ? Ident.dim : Ident.ok) : Ident.red)
                                Spacer()
                            }
                            .font(Fonts.vt(17)).foregroundColor(Ident.cream2)
                            .help(r.detail)
                        }
                    }
                }
            }

            if let notice = model.notice {
                Text(notice).font(Fonts.grotesk(12)).foregroundColor(Ident.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .onTapGesture { model.notice = nil }
            }

            Ruled {
                HStack {
                    Button("← Back") { model.showSettings = false }.buttonStyle(DawnTextButtonStyle())
                    Spacer()
                    Text("v\(DawnInfo.version)").font(Fonts.vt(17)).foregroundColor(Ident.dim)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private func label(_ r: FireRecord) -> String {
        switch (r.trigger, r.ok) {
        case (.skipped, _): return "SKIPPED · WINDOW WAS OPEN"
        case (_, false): return "FAILED"
        case (.manual, true): return "SENT BY HAND"
        case (.followUp, true): return "SENT · AUTO REFRESH"
        case (.sync, true): return "SYNCED WITH CLAUDE"
        case (.scheduled, true): return "SENT"
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, first: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { Rectangle().fill(Ident.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 12) {
                Text(title).dawnLabel()
                content()
            }
            .padding(EdgeInsets(top: first ? 4 : 14, leading: 16, bottom: 14, trailing: 16))
        }
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(Fonts.grotesk(13, weight: 500)).foregroundColor(Ident.cream)
            Spacer(minLength: 8)
            trailing()
        }
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
                Text(title).font(Fonts.grotesk(13, weight: 600))
                Text(status).font(Fonts.grotesk(11)).foregroundColor(Ident.dim).lineLimit(2)
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
                    Text(letter).font(Fonts.mono(10, bold: true))
                        .frame(width: 18, height: 20)
                        .foregroundColor(on ? Ident.cream : Ident.dim)
                        .background(on ? Ident.red : Ident.black2)
                        .overlay(Rectangle().strokeBorder(on ? Color.clear : Ident.line, lineWidth: 1))
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

// MARK: - Notch

/// Where the notch points, in panel coordinates. Set by the status panel so it sits under the sun.
final class PanelGeometry: ObservableObject {
    @Published var arrowX: CGFloat = PanelView.width / 2
}

/// The panel with its pixel notch on top. The notch points at the menu bar sun; under it, red pixels
/// bleed into the panel's top edge and thin out in an ordered dither.
struct PanelContainer: View {
    @ObservedObject var model: DawnModel
    @ObservedObject var geometry: PanelGeometry

    static let notchHeight: CGFloat = PixelNotch.rows * PixelNotch.pixel

    var body: some View {
        VStack(spacing: 0) {
            PixelNotch()
                .frame(width: PixelNotch.width, height: Self.notchHeight)
                .padding(.leading, max(0, geometry.arrowX - PixelNotch.width / 2))
                .frame(maxWidth: .infinity, alignment: .leading)
            PanelView(model: model)
                .overlay(alignment: .top) { PixelBleed(centerX: geometry.arrowX).frame(height: PixelNotch.pixel * 3) }
        }
        .frame(width: PanelView.width)
    }
}

/// A stepped triangle of 2 pt pixels, 1-3-5-7-9 wide.
struct PixelNotch: View {
    static let pixel: CGFloat = 2
    static let rows: CGFloat = 5
    static var width: CGFloat { (rows * 2 - 1) * pixel }

    var body: some View {
        Canvas { ctx, size in
            let p = Self.pixel
            let cx = size.width / 2
            for r in 0..<Int(Self.rows) {
                let count = 2 * r + 1
                for k in 0..<count {
                    let x = cx - CGFloat(count) * p / 2 + CGFloat(k) * p
                    // The tip is bright; the base row alternates with red-deep where it meets the panel.
                    let color = (r == Int(Self.rows) - 1 && k % 2 == 1) ? Ident.redDeep : Ident.red
                    ctx.fill(Path(CGRect(x: x, y: CGFloat(r) * p, width: p, height: p)), with: .color(color))
                }
            }
        }
    }
}

/// Red pixels along the panel's top edge, densest under the notch, fading out with a 4 × 4 Bayer dither.
struct PixelBleed: View {
    let centerX: CGFloat
    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    var body: some View {
        Canvas { ctx, size in
            let p = PixelNotch.pixel
            let reach: [CGFloat] = [90, 56, 28] // how far each row reaches from the notch
            for row in 0..<3 {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    let d = abs(x + p / 2 - centerX)
                    let density = max(0, 1 - d / reach[row])
                    let threshold = (Self.bayer[row % 4][col % 4] + 0.5) / 16
                    if density > threshold {
                        ctx.fill(Path(CGRect(x: x, y: CGFloat(row) * p, width: p, height: p)),
                                 with: .color(density > 0.6 ? Ident.red : Ident.redDeep))
                    }
                    x += p
                    col += 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}
