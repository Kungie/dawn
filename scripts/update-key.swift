// Makes Dawn's update signing key once, keeps the private half in the login Keychain,
// and prints the public half for Sources/Dawn/Update.swift. Never prints the private key.
// Usage: swift scripts/update-key.swift
import CryptoKit
import Foundation

let service = "io.github.kungie.dawn.update-signing"
let account = "release"

func security(_ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try! p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

let existing = security(["find-generic-password", "-s", service, "-a", account, "-w"])
let key: Curve25519.Signing.PrivateKey
if existing.status == 0, let raw = Data(base64Encoded: existing.out), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
    key = k
    print("Using the key already in the Keychain.")
} else {
    key = Curve25519.Signing.PrivateKey()
    let added = security(["add-generic-password", "-s", service, "-a", account, "-l", "Dawn update signing key",
                          "-w", key.rawRepresentation.base64EncodedString()])
    guard added.status == 0 else { print("Couldn't save the key to the Keychain."); exit(1) }
    print("Made a new key and saved it to the Keychain (\(service)).")
}
print("Public key: \(key.publicKey.rawRepresentation.base64EncodedString())")
