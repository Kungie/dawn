import CryptoKit
import Foundation
import Testing
@testable import Dawn

@MainActor
@Suite(.serialized) struct UpdaterTests {
    let key = Curve25519.Signing.PrivateKey()

    /// Stands in for the model's settings.
    final class Store {
        var settings = Settings()
    }

    /// Every URL asked for. The zip and its signature download at the same time, so appends take a lock.
    final class Fetches: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [URL] = []
        var urls: [URL] { lock.withLock { list } }
        func append(_ url: URL) { lock.withLock { list.append(url) } }
    }

    nonisolated static func unsigned(_ version: String) -> Data {
        Data("""
        {"tag_name": "v\(version)", "body": "", "assets": [{"name": "Dawn.zip", "browser_download_url": "https://example.com/Dawn.zip"}]}
        """.utf8)
    }

    nonisolated static func release(_ version: String) -> Data {
        Data("""
        {"tag_name": "v\(version)", "body": "Notes.", "assets": [
          {"name": "Dawn.zip", "browser_download_url": "https://example.com/Dawn.zip"},
          {"name": "Dawn.zip.sig", "browser_download_url": "https://example.com/Dawn.zip.sig"}]}
        """.utf8)
    }

    func updater(current: String = "0.6.0", store: Store = Store(), answer: @escaping @Sendable (URL) throws -> Data,
                 fetches: Fetches = Fetches(), app: URL? = nil, relaunched: (() -> Void)? = nil) -> Updater {
        Updater(current: current, settings: { store.settings }, saveSettings: { store.settings = $0 },
                app: app ?? makeTempDir("apps").appendingPathComponent("Dawn.app"),
                publicKey: key.publicKey.rawRepresentation,
                fetch: { url in fetches.append(url); return try answer(url) },
                relaunch: relaunched ?? {})
    }

    @Test func findsANewerReleaseAndRemembersTheCheck() async {
        let store = Store()
        store.settings.hour = 5
        let u = updater(store: store, answer: { _ in Self.release("0.6.1") })
        await u.check(manual: true)
        #expect(u.status == .available(version: "0.6.1"))
        #expect(store.settings.lastUpdateCheck != nil)
        #expect(store.settings.hour == 5)
        #expect(u.panelLine == "DAWN 0.6.1 IS OUT")
    }

    @Test func saysUpToDateWhenItIs() async {
        let u = updater(current: "0.6.1", answer: { _ in Self.release("0.6.1") })
        await u.check(manual: true)
        guard case .upToDate = u.status else { Issue.record("\(u.status)"); return }
        #expect(u.panelLine == nil)
    }

    @Test func theStatusLineSaysWhatHappened() async {
        let u = updater(current: "0.6.0", answer: { _ in Self.release("0.6.0") })
        #expect(u.statusLine(lastCheck: nil) == "NOT CHECKED YET · 0.6.0")
        let at = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date())!
        await u.check(manual: true)
        #expect(u.statusLine(lastCheck: at) == "UP TO DATE · 0.6.0 · CHECKED 09:41")
        let newer = updater(current: "0.6.0", answer: { _ in Self.release("0.6.1") })
        await newer.check(manual: true)
        #expect(newer.statusLine(lastCheck: at) == "0.6.1 IS OUT")
    }

    @Test func anUnsignedReleaseOfThisVersionIsUpToDate() async {
        let u = updater(current: "0.6.0", answer: { _ in Self.unsigned("0.6.0") })
        await u.check(manual: true)
        guard case .upToDate = u.status else { Issue.record("\(u.status)"); return }
    }

    @Test func aNewerUnsignedReleaseIsNeverInstalled() async {
        let quiet = updater(answer: { _ in Self.unsigned("0.6.1") })
        await quiet.check(manual: false)
        #expect(quiet.status == .idle)
        #expect(quiet.panelLine == nil)
        let asked = updater(answer: { _ in Self.unsigned("0.6.1") })
        await asked.check(manual: true)
        #expect(asked.status == .failed("Dawn 0.6.1 is out, but it can't update itself to it. Download it from GitHub."))
        await asked.install()
        #expect(asked.status == .failed("Dawn 0.6.1 is out, but it can't update itself to it. Download it from GitHub."))
    }

    @Test func dailyCheckRunsOnlyWhenDueAndOn() async {
        let fetches = Fetches()
        let store = Store()
        let u = updater(store: store, answer: { _ in Self.release("0.6.1") }, fetches: fetches)
        store.settings.lastUpdateCheck = Date().addingTimeInterval(-3600)
        await u.checkIfDue()
        #expect(fetches.urls.isEmpty)
        store.settings.lastUpdateCheck = Date().addingTimeInterval(-30 * 3600)
        await u.checkIfDue()
        #expect(fetches.urls == [Update.latestURL])
        store.settings.checkForUpdates = false
        store.settings.lastUpdateCheck = nil
        await u.checkIfDue()
        #expect(fetches.urls.count == 1)
    }

    @Test func aFailedCheckOnlyShowsWhenYouAsked() async {
        struct Offline: Error {}
        let quiet = updater(answer: { _ in throw Offline() })
        await quiet.check(manual: false)
        #expect(quiet.status == .idle)
        let asked = updater(answer: { _ in throw Offline() })
        await asked.check(manual: true)
        #expect(asked.status == .failed("Couldn't reach GitHub. Try again in a bit."))
        #expect(asked.panelLine == nil)
    }

    @Test func updateDownloadsInstallsAndRelaunches() async throws {
        let root = makeTempDir("install")
        let app = root.appendingPathComponent("Applications/Dawn.app")
        try makeApp(at: app, id: Update.bundleID, version: "0.6.0", body: "old")
        let staged = root.appendingPathComponent("build/Dawn.app")
        try makeApp(at: staged, id: Update.bundleID, version: "0.6.1", body: "new")
        let zip = try zipApp(staged, to: root.appendingPathComponent("Dawn.zip"))
        let sig = Data(try key.signature(for: zip).base64EncodedString().utf8)
        var relaunched = false
        let store = Store()
        store.settings.enabled = true
        let u = updater(store: store, answer: { url in
            switch url.lastPathComponent {
            case "Dawn.zip": return zip
            case "Dawn.zip.sig": return sig
            default: return Self.release("0.6.1")
            }
        }, app: app, relaunched: { relaunched = true })
        await u.check(manual: false)
        await u.install()
        #expect(relaunched)
        #expect(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String == "0.6.1")
        #expect(store.settings.enabled)
    }

    @Test func aBadDownloadLeavesTheAppAndSaysSoInThePanel() async throws {
        let u = updater(answer: { url in
            url.lastPathComponent == "latest" ? Self.release("0.6.1") : Data("tampered".utf8)
        })
        await u.check(manual: false)
        await u.install()
        #expect(u.status == .failed("The download didn't match Dawn's signature, so I left Dawn as it is."))
        #expect(u.panelLine == "UPDATE FAILED")
    }
}
