import AppKit
import Foundation

/// Keeps Dawn up to date: looks for a new release once a day (if that's on) and whenever you ask,
/// and on Update downloads, checks and installs it, then restarts Dawn. Your settings stay put.
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    /// The last failure came from Update (not from a check), so the panel says so.
    @Published private(set) var installFailed = false
    let current: String
    private var release: Update.Release?
    private let settings: () -> Settings
    private let saveSettings: (Settings) -> Void
    private let app: URL
    private let publicKey: Data
    private let fetch: @Sendable (URL) async throws -> Data
    private let relaunch: () -> Void
    private var timer: Timer?

    /// `settings` and `saveSettings` go through the model, so it never writes back an older copy.
    init(current: String, settings: @escaping () -> Settings, saveSettings: @escaping (Settings) -> Void, app: URL,
         publicKey: Data = Data(base64Encoded: Update.publicKey)!,
         fetch: @escaping @Sendable (URL) async throws -> Data = Updater.download, relaunch: @escaping () -> Void) {
        self.current = current
        self.settings = settings
        self.saveSettings = saveSettings
        self.app = app
        self.publicKey = publicKey
        self.fetch = fetch
        self.relaunch = relaunch
    }

    /// GitHub over HTTPS, with the User-Agent its API asks for.
    nonisolated static let download: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Dawn", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Starts this Dawn again from where it is, once it has quit.
    static func relaunchApp() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// A first look a little after launch, then every hour whether a day has passed.
    func start() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await self?.checkIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    func checkIfDue() async {
        let s = settings()
        guard Update.isDue(lastCheck: s.lastUpdateCheck, enabled: s.checkForUpdates, now: Date()) else { return }
        await check(manual: false)
    }

    /// `manual` is the Check for updates button: it shows progress and failures. The daily check stays quiet.
    func check(manual: Bool) async {
        if case .installing = status { return }
        if manual { status = .checking; installFailed = false }
        do {
            let data = try await fetch(Update.latestURL)
            var s = settings()
            s.lastUpdateCheck = Date()
            saveSettings(s)
            guard let latest = Update.Release.parse(data) else {
                if manual { status = .failed("GitHub's answer didn't make sense. Try again in a bit.") }
                return
            }
            if Update.isNewer(latest.version, than: current), latest.signature == nil {
                // Newer, but not signed for in-app updates: never install it, and only say so when asked.
                release = nil
                if manual { status = .failed("Dawn \(latest.version) is out, but it can't update itself to it. Download it from GitHub.") }
            } else if Update.isNewer(latest.version, than: current) {
                release = latest
                installFailed = false
                status = .available(version: latest.version)
            } else {
                release = nil
                status = .upToDate(Date())
            }
        } catch {
            if manual { status = .failed("Couldn't reach GitHub. Try again in a bit.") }
        }
    }

    /// Update: only for a signed release a check found. A failed try can be tried again.
    func install() async {
        guard let release, let signatureURL = release.signature else { return }
        switch status {
        case .available: break
        case .failed where installFailed: break
        default: return
        }
        status = .installing(version: release.version)
        installFailed = false
        do {
            async let zip = fetch(release.zip)
            async let signature = fetch(signatureURL)
            let (zipData, sigData) = try await (zip, signature)
            let app = self.app, key = publicKey, version = release.version
            try await Task.detached {
                try UpdateInstaller.install(zip: zipData, signature: sigData, expectedVersion: version, over: app, publicKey: key)
            }.value
            relaunch()
        } catch let failure as UpdateInstaller.Failure {
            installFailed = true
            status = .failed(Self.message(failure))
        } catch {
            installFailed = true
            status = .failed("Couldn't download the update. Try again in a bit.")
        }
    }

    static func message(_ failure: UpdateInstaller.Failure) -> String {
        switch failure {
        case .badSignature: return "The download didn't match Dawn's signature, so I left Dawn as it is."
        case .notDawn: return "The download wasn't a Dawn app, so I left Dawn as it is."
        case let .wrongVersion(v): return "The download was version \(v), not the one GitHub announced, so I left Dawn as it is."
        case .cannotWrite: return "I can't replace myself where I am. Move Dawn to Applications, open it from there and try again."
        }
    }

    // MARK: words for the panel and Settings

    /// The one line in the panel, or nil when there's nothing to say there.
    var panelLine: String? {
        switch status {
        case let .available(v): return "DAWN \(v) IS OUT"
        case let .installing(v): return "UPDATING TO \(v)…"
        case .failed where installFailed: return "UPDATE FAILED"
        default: return nil
        }
    }

    /// The status line under Settings › Updates.
    func statusLine(lastCheck: Date?, now: Date = Date()) -> String {
        switch status {
        case .checking: return "CHECKING…"
        case let .available(v): return "\(v) IS OUT"
        case let .installing(v): return "UPDATING TO \(v)…"
        case .upToDate: return "UP TO DATE · \(current)" + (lastCheck.map { " · CHECKED \(Self.when($0, now: now))" } ?? "")
        case .idle, .failed:
            guard let lastCheck else { return "NOT CHECKED YET · \(current)" }
            return "\(current) · CHECKED \(Self.when(lastCheck, now: now))"
        }
    }

    static func when(_ date: Date, now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date).uppercased()
    }
}
