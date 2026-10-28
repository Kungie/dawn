import Foundation

/// A fresh, empty folder under the temporary directory.
func makeTempDir(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dawn-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `text` to `url`, making the folders on the way.
func write(_ text: String, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
}

/// A minimal app bundle with this id, version and executable text.
func makeApp(at url: URL, id: String, version: String, body: String) throws {
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleExecutable": "Dawn"]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    write(String(decoding: data, as: UTF8.self), to: url.appendingPathComponent("Contents/Info.plist"))
    write(body, to: url.appendingPathComponent("Contents/MacOS/Dawn"))
}

/// `app` zipped the way scripts/build-app.sh does it.
func zipApp(_ app: URL, to out: URL) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--keepParent", app.path, out.path]
    try p.run()
    p.waitUntilExit()
    return try Data(contentsOf: out)
}
