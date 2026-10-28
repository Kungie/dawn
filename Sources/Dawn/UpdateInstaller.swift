import Foundation

/// Swaps the running app for a downloaded update. Only the app bundle is touched: your settings
/// (UserDefaults), Dawn's files in Application Support, the scheduled wake and Claude Code's hook and
/// status line all live outside it, and the hook and status line point at the same path afterwards.
enum UpdateInstaller {
    enum Failure: Error, Equatable {
        case badSignature
        /// The zip didn't hold a Dawn app.
        case notDawn
        case wrongVersion(String)
        /// The app's folder can't be written (it's running from the disk image, say).
        case cannotWrite
    }

    /// Checks the signature, unpacks next to `app`, checks it's Dawn at `expectedVersion`, then replaces `app`
    /// in one step. On any failure the current app is left exactly as it was.
    static func install(zip: Data, signature: Data, expectedVersion: String, over app: URL,
                        publicKey: Data = Data(base64Encoded: Update.publicKey)!) throws {
        guard Update.verify(zip, signature: signature, publicKey: publicKey) else { throw Failure.badSignature }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else { throw Failure.cannotWrite }
        // A scratch folder on the same volume, so the final swap is a rename.
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? fm.removeItem(at: scratch) }
        let archive = scratch.appendingPathComponent("Dawn.zip")
        try zip.write(to: archive)
        let unpacked = scratch.appendingPathComponent("unpacked")
        guard ditto(["-x", "-k", "--noqtn", archive.path, unpacked.path]) else { throw Failure.notDawn }
        let candidates = (try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = candidates.first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Update.bundleID
        else { throw Failure.notDawn }
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard version == expectedVersion else { throw Failure.wrongVersion(version) }
        _ = try fm.replaceItemAt(app, withItemAt: newApp)
    }

    static func ditto(_ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
