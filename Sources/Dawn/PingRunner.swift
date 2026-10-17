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
        /// Claude's own five-hour window after this ping (reset time and share used), when it said so.
        var limit: WindowLimit? = nil
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

        // stream-json: the same answer, plus Claude Code's rate_limit_event with the real reset time.
        let args = ["-p", "ping", "--model", model, "--output-format", "stream-json", "--verbose"]
        var attempt = run(claude, args, cwd: workDir, timeout: 120)
        if attempt.status != 0 && retry {
            Thread.sleep(forTimeInterval: 20)
            attempt = run(claude, args, cwd: workDir, timeout: 120)
        }
        let parsed = parse(attempt.output ?? "")
        if attempt.status == 0 {
            return Result(ok: true, detail: parsed.answer.map { String($0.prefix(160)) } ?? "sent", limit: parsed.limit)
        }
        let text = (attempt.error?.isEmpty == false ? attempt.error : parsed.answer) ?? ""
        let short = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
        return Result(ok: false, detail: short.isEmpty ? "claude exited with \(attempt.status)" : String(short), limit: parsed.limit)
    }

    /// Reads Claude Code's stream-json output: the final answer and the five-hour window from
    /// `rate_limit_event.rate_limit_info` (`unifiedWindows.five_hour`, or the top level when it is the five-hour one).
    static func parse(_ output: String) -> (answer: String?, limit: WindowLimit?) {
        var answer: String?
        var limit: WindowLimit?
        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            switch json["type"] as? String {
            case "result":
                answer = json["result"] as? String
            case "rate_limit_event":
                guard let info = json["rate_limit_info"] as? [String: Any] else { continue }
                var window = (info["unifiedWindows"] as? [String: Any])?["five_hour"] as? [String: Any]
                if window == nil, (info["rateLimitType"] as? String) == "five_hour" { window = info }
                if let w = window, let reset = (w["resetsAt"] as? NSNumber)?.doubleValue {
                    let used = (w["utilization"] as? NSNumber).map { $0.doubleValue * 100 }
                    limit = WindowLimit(resetsAt: Date(timeIntervalSince1970: reset), usedPercent: used, updated: Date())
                }
            default:
                break
            }
        }
        return (answer, limit)
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
