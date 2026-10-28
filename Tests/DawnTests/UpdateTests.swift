import CryptoKit
import Foundation
import Testing
@testable import Dawn

@Suite struct UpdateTests {
    @Test func asksGitHubForDawnsLatestRelease() {
        #expect(Update.latestURL.absoluteString == "https://api.github.com/repos/Kungie/dawn/releases/latest")
        #expect(Update.bundleID == "io.github.kungie.dawn")
    }

    @Test func versionsCompareByNumberNotText() {
        #expect(Update.isNewer("v0.6.1", than: "0.6.0"))
        #expect(Update.isNewer("0.5.10", than: "0.5.9"))
        #expect(Update.isNewer("0.6", than: "0.5.9"))
        #expect(Update.isNewer("1.0.0", than: "0.9.9"))
        #expect(!Update.isNewer("v0.6.0", than: "0.6.0"))
        #expect(!Update.isNewer("0.5.3", than: "0.6.0"))
        #expect(!Update.isNewer("nightly", than: "0.6.0"))
        #expect(!Update.isNewer("0.6.1", than: "0.6.1-dev"))
    }

    static let releaseJSON = """
    {"tag_name": "v0.6.1", "name": "Dawn 0.6.1", "body": "- **Faster.** It's faster.",
     "assets": [
       {"name": "Dawn.dmg", "browser_download_url": "https://github.com/Kungie/dawn/releases/download/v0.6.1/Dawn.dmg"},
       {"name": "Dawn.zip", "browser_download_url": "https://github.com/Kungie/dawn/releases/download/v0.6.1/Dawn.zip"},
       {"name": "Dawn.zip.sig", "browser_download_url": "https://github.com/Kungie/dawn/releases/download/v0.6.1/Dawn.zip.sig"}
     ]}
    """

    @Test func readsTheLatestReleaseFromGitHub() throws {
        let release = try #require(Update.Release.parse(Data(Self.releaseJSON.utf8)))
        #expect(release.version == "0.6.1")
        #expect(release.zip.absoluteString.hasSuffix("/v0.6.1/Dawn.zip"))
        #expect(release.signature?.absoluteString.hasSuffix("/v0.6.1/Dawn.zip.sig") == true)
        #expect(release.notes == "- **Faster.** It's faster.")
    }

    @Test func aReleaseWithoutASignatureCantBeInstalled() throws {
        let unsigned = Self.releaseJSON.replacingOccurrences(of: "Dawn.zip.sig", with: "Dawn.zip.txt")
        let release = try #require(Update.Release.parse(Data(unsigned.utf8)))
        #expect(release.version == "0.6.1")
        #expect(release.signature == nil)
        #expect(Update.Release.parse(Data("not json".utf8)) == nil)
        let noZip = Self.releaseJSON.replacingOccurrences(of: "\"Dawn.zip\"", with: "\"Other.zip\"")
        #expect(Update.Release.parse(Data(noZip.utf8)) == nil)
    }

    @Test func onlyFilesSignedWithTheKeyPass() throws {
        let key = Curve25519.Signing.PrivateKey()
        let zip = Data("the new Dawn".utf8)
        let signature = Data(try key.signature(for: zip).base64EncodedString().utf8)
        #expect(Update.verify(zip, signature: signature, publicKey: key.publicKey.rawRepresentation))
        #expect(!Update.verify(Data("something else".utf8), signature: signature, publicKey: key.publicKey.rawRepresentation))
        #expect(!Update.verify(zip, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
        #expect(!Update.verify(zip, signature: Data("garbage".utf8), publicKey: key.publicKey.rawRepresentation))
    }

    @Test func theShippedPublicKeyIsDawnsOwnEd25519Key() throws {
        let raw = try #require(Data(base64Encoded: Update.publicKey))
        #expect(raw.count == 32)
        #expect(throws: Never.self) { try Curve25519.Signing.PublicKey(rawRepresentation: raw) }
        // Not Binder's key: each app has its own.
        #expect(Update.publicKey != "sHF+CM0c0seYOV9J3KOi53dqAresgujr5DpFXCTzK4g=")
    }

    @Test func checksOnceADayWhenOn() {
        let now = Date()
        #expect(Update.isDue(lastCheck: nil, enabled: true, now: now))
        #expect(!Update.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), enabled: true, now: now))
        #expect(Update.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), enabled: true, now: now))
        #expect(!Update.isDue(lastCheck: nil, enabled: false, now: now))
        // A clock that went backwards doesn't block checks forever.
        #expect(Update.isDue(lastCheck: now.addingTimeInterval(3 * 86400), enabled: true, now: now))
    }
}
