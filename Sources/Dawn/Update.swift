import CryptoKit
import Foundation

/// Updates from GitHub Releases. Dawn asks GitHub for the latest release once a day (and when you ask),
/// downloads `Dawn.zip`, and only installs it if `Dawn.zip.sig` proves it was signed with Dawn's
/// release key, whose private half never leaves the maintainer's Keychain (`scripts/update-key.swift`).
enum Update {
    static let latestURL = URL(string: "https://api.github.com/repos/Kungie/dawn/releases/latest")!
    /// Ed25519, raw 32 bytes. Signs every `Dawn.zip` (`scripts/sign-update.swift`). Dawn's own key, not Binder's.
    static let publicKey = "kFL5Yg/UUG6t5M8DgwICv6l1cbJPi6oJjX8rdWmxPAo="
    static let bundleID = "io.github.kungie.dawn"
    static let interval: TimeInterval = 24 * 3600

    struct Release: Equatable, Sendable {
        var version: String
        var notes: String
        var zip: URL
        /// Releases from before updates were signed have none; those can't be installed from inside the app.
        var signature: URL?

        /// GitHub's `releases/latest` answer, or nil when it isn't one or has no `Dawn.zip`.
        static func parse(_ data: Data) -> Release? {
            struct Asset: Decodable { var name: String; var browser_download_url: URL }
            struct Payload: Decodable { var tag_name: String; var body: String?; var assets: [Asset] }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let zip = payload.assets.first(where: { $0.name == "Dawn.zip" })?.browser_download_url
            else { return nil }
            let sig = payload.assets.first(where: { $0.name == "Dawn.zip.sig" })?.browser_download_url
            let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
            return Release(version: version, notes: payload.body ?? "", zip: zip, signature: sig)
        }
    }

    /// Whether `candidate` is a later version than `current`, comparing each dotted number.
    /// Anything that isn't a version (a nightly tag, say) is never newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = numbers(candidate), let b = numbers(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func numbers(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".").map { part in Int(part.prefix { $0.isNumber }) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// `signature` is the `.sig` file: the base64 Ed25519 signature of the zip's bytes.
    static func verify(_ data: Data, signature: Data, publicKey: Data) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(raw, for: data)
    }

    /// Once a day while it's on. A last check in the future (a clock set back) counts as due.
    static func isDue(lastCheck: Date?, enabled: Bool, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
