// Signs an update zip with Dawn's release key from the login Keychain and writes <zip>.sig next to it:
// the base64 Ed25519 signature that the app checks before it installs anything.
// Usage: swift scripts/sign-update.swift build/Dawn.zip
import CryptoKit
import Foundation

let service = "io.github.kungie.dawn.update-signing"
let shipped = "kFL5Yg/UUG6t5M8DgwICv6l1cbJPi6oJjX8rdWmxPAo="

guard CommandLine.arguments.count == 2 else { print("usage: swift scripts/sign-update.swift <zip>"); exit(2) }
let zip = URL(fileURLWithPath: CommandLine.arguments[1])
guard FileManager.default.fileExists(atPath: zip.path) else { print("No such file: \(zip.path). Run make app first."); exit(1) }

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
p.arguments = ["find-generic-password", "-s", service, "-a", "release", "-w"]
let pipe = Pipe()
p.standardOutput = pipe
p.standardError = FileHandle.nullDevice
try p.run()
let secret = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
p.waitUntilExit()
guard p.terminationStatus == 0, let raw = Data(base64Encoded: secret), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    print("No release key in the Keychain. Run swift scripts/update-key.swift first.")
    exit(1)
}
guard key.publicKey.rawRepresentation.base64EncodedString() == shipped else {
    print("The Keychain key doesn't match the public key the app ships with. Not signing.")
    exit(1)
}
let data = try Data(contentsOf: zip)
let signature = try key.signature(for: data)
guard key.publicKey.isValidSignature(signature, for: data) else { print("Signature didn't verify."); exit(1) }
let out = zip.appendingPathExtension("sig")
try Data(signature.base64EncodedString().utf8).write(to: out)
print("Signed \(zip.lastPathComponent) -> \(out.lastPathComponent)")
