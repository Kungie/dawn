import Foundation
import IOKit.pwr_mgt

/// Sends the morning ping through the official Claude Code CLI, signed in with the user's own account.
/// Dawn never reads, copies or stores Claude credentials and never uses an API key.
enum PingRunner {
    /// The ping runs inside its own folder, so its log lands in a project Dawn can tell apart from real work.
    static let projectSuffix = "Dawn-ping"

    static var workDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dawn/\(projectSuffix)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct Result {
        let ok: Bool
        let detail: String
    }

    /// Finds `claude`: the usual install locations first, then the user's login shell PATH.
    static func locateClaude() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let out = run(shell, ["-lc", "command -v claude"], timeout: 8).output?
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces),
            out.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: out) else { return nil }
        return out
    }

    /// One short message with the smallest model. Keeps the Mac awake while it runs and retries once,
    /// because right after a scheduled wake the network can take a few seconds to come back.
    static func ping(claude: String, model: String = "haiku", retry: Bool = true) -> Result {
        var assertion: IOPMAssertionID = 0
        let held = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Dawn is sending the morning ping" as CFString,
                                               &assertion) == kIOReturnSuccess
        defer { if held { IOPMAssertionRelease(assertion) } }

        var attempt = run(claude, ["-p", "ping", "--model", model], cwd: workDir, timeout: 120)
        if attempt.status != 0 && retry {
            Thread.sleep(forTimeInterval: 20)
            attempt = run(claude, ["-p", "ping", "--model", model], cwd: workDir, timeout: 120)
        }
        let text = (attempt.status == 0 ? attempt.output : attempt.error ?? attempt.output) ?? ""
        let short = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
        if attempt.status == 0 { return Result(ok: true, detail: short.isEmpty ? "sent" : String(short)) }
        return Result(ok: false, detail: short.isEmpty ? "claude exited with \(attempt.status)" : String(short))
    }

    struct Output {
        var status: Int32
        var output: String?
        var error: String?
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval) -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        let dir = (path as NSString).deletingLastPathComponent
        env["PATH"] = [dir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", env["PATH"] ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ":")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Output(status: -1, output: nil, error: error.localizedDescription) }

        let deadline = Date().addingTimeInterval(timeout)
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning {
            p.terminate()
            _ = group.wait(timeout: .now() + 2)
            return Output(status: -2, output: nil, error: "timed out after \(Int(timeout)) s")
        }
        group.wait()
        return Output(status: p.terminationStatus,
                      output: String(data: outData, encoding: .utf8),
                      error: String(data: errData, encoding: .utf8))
    }
}
