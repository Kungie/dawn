import CryptoKit
import Foundation
import Testing
@testable import Dawn

@Suite struct UpdateInstallerTests {
    let root = makeTempDir("update")
    let key = Curve25519.Signing.PrivateKey()

    func signature(_ data: Data, with key: Curve25519.Signing.PrivateKey) throws -> Data {
        Data(try key.signature(for: data).base64EncodedString().utf8)
    }

    func installed(_ app: URL) -> (version: String?, body: String?) {
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return (plist?["CFBundleShortVersionString"] as? String,
                try? String(contentsOf: app.appendingPathComponent("Contents/MacOS/Dawn"), encoding: .utf8))
    }

    /// The current app in a fake Applications folder, the new one zipped and signed.
    func setUp(newID: String = Update.bundleID, newVersion: String = "0.6.1") throws -> (app: URL, zip: Data) {
        let app = root.appendingPathComponent("Applications/Dawn.app")
        try makeApp(at: app, id: Update.bundleID, version: "0.6.0", body: "old")
        let staged = root.appendingPathComponent("build/Dawn.app")
        try makeApp(at: staged, id: newID, version: newVersion, body: "new")
        return (app, try zipApp(staged, to: root.appendingPathComponent("Dawn.zip")))
    }

    @Test func installsASignedUpdateInPlace() throws {
        let (app, zip) = try setUp()
        try UpdateInstaller.install(zip: zip, signature: signature(zip, with: key), expectedVersion: "0.6.1",
                                    over: app, publicKey: key.publicKey.rawRepresentation)
        #expect(installed(app) == ("0.6.1", "new"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: app.deletingLastPathComponent().path)
        #expect(leftovers == ["Dawn.app"])
    }

    /// Only the app bundle changes: preferences, Dawn's support files and Claude Code's settings
    /// (whose hook and status line point at the same /Applications path) stay byte for byte.
    @Test func leavesYourSettingsHooksAndDataAlone() throws {
        let (app, zip) = try setUp()
        let home = root.appendingPathComponent("home")
        let dawn = app.appendingPathComponent("Contents/MacOS/Dawn").path
        let files = [
            "Library/Preferences/io.github.kungie.dawn.plist": "settings, history, manual starts",
            "Library/Application Support/Dawn/window-limit.json": "{\"resetsAt\": 814158000, \"usedPercent\": 4}",
            "Library/Application Support/Dawn/original-statusline.txt": "~/bin/my-status",
            ".claude/settings.json": """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\\"\(dawn)\\" hook stop"}]}]},
             "statusLine": {"type": "command", "command": "\\"\(dawn)\\" statusline"}}
            """
        ]
        for (path, text) in files { write(text, to: home.appendingPathComponent(path)) }
        try UpdateInstaller.install(zip: zip, signature: signature(zip, with: key), expectedVersion: "0.6.1",
                                    over: app, publicKey: key.publicKey.rawRepresentation)
        for (path, text) in files {
            #expect(try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) == text, "\(path)")
        }
        // The hook's path still leads to an executable Dawn.
        #expect(FileManager.default.fileExists(atPath: dawn))
    }

    @Test func keepsUserDefaults() throws {
        let suite = "io.github.kungie.dawn.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = Settings(enabled: true, hour: 5, minute: 10, weekdays: [2, 6], doneSound: false, menuBar: .time)
        settings.checkForUpdates = false
        defaults.set(try JSONEncoder().encode(settings), forKey: "settings")
        defaults.set([Date(timeIntervalSince1970: 1_793_000_000)], forKey: "manualStarts")
        let (app, zip) = try setUp()
        try UpdateInstaller.install(zip: zip, signature: signature(zip, with: key), expectedVersion: "0.6.1",
                                    over: app, publicKey: key.publicKey.rawRepresentation)
        let data = try #require(defaults.data(forKey: "settings"))
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
        #expect(defaults.array(forKey: "manualStarts") as? [Date] == [Date(timeIntervalSince1970: 1_793_000_000)])
    }

    @Test func refusesAZipSignedWithAnotherKey() throws {
        let (app, zip) = try setUp()
        #expect(throws: UpdateInstaller.Failure.badSignature) {
            try UpdateInstaller.install(zip: zip, signature: signature(zip, with: Curve25519.Signing.PrivateKey()),
                                        expectedVersion: "0.6.1", over: app, publicKey: key.publicKey.rawRepresentation)
        }
        #expect(installed(app) == ("0.6.0", "old"))
    }

    @Test func refusesAnotherApp() throws {
        let (app, zip) = try setUp(newID: "io.github.kungie.binder")
        #expect(throws: UpdateInstaller.Failure.notDawn) {
            try UpdateInstaller.install(zip: zip, signature: signature(zip, with: key), expectedVersion: "0.6.1",
                                        over: app, publicKey: key.publicKey.rawRepresentation)
        }
        #expect(installed(app) == ("0.6.0", "old"))
    }

    @Test func refusesAVersionOtherThanTheReleaseSaid() throws {
        let (app, zip) = try setUp(newVersion: "0.5.3")
        #expect(throws: UpdateInstaller.Failure.wrongVersion("0.5.3")) {
            try UpdateInstaller.install(zip: zip, signature: signature(zip, with: key), expectedVersion: "0.6.1",
                                        over: app, publicKey: key.publicKey.rawRepresentation)
        }
        #expect(installed(app) == ("0.6.0", "old"))
    }

    @Test func refusesSomethingThatIsntAZip() throws {
        let (app, _) = try setUp()
        let junk = Data("not a zip".utf8)
        #expect(throws: UpdateInstaller.Failure.notDawn) {
            try UpdateInstaller.install(zip: junk, signature: signature(junk, with: key), expectedVersion: "0.6.1",
                                        over: app, publicKey: key.publicKey.rawRepresentation)
        }
        #expect(installed(app) == ("0.6.0", "old"))
    }
}
