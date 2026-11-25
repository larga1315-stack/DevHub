import Foundation

public struct ShellResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
    public var combined: String { stdout + (stderr.isEmpty ? "" : "\n" + stderr) }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Lets a caller cancel a running `Shell.run` process.
public final class Cancellation {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }

    fileprivate func attach(_ p: Process) {
        lock.lock()
        process = p
        let already = cancelled
        lock.unlock()
        if already, p.isRunning { p.terminate() }
    }
}

/// Runs processes with an arguments array — never through a shell — unless `loginShell`
/// is used explicitly for commands the user typed. Untrusted text (prompts, logs) only travels
/// as an argument, which prevents OS command injection (CWE-78).
public enum Shell {
    private final class Box { var data = Data() }

    public static func run(_ executable: String,
                           _ arguments: [String],
                           cwd: String? = nil,
                           environment: [String: String]? = nil,
                           cancellation: Cancellation? = nil) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                if let environment { process.environment = environment }
                process.standardInput = FileHandle.nullDevice

                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                cancellation?.attach(process)

                // Drain both pipes concurrently so a full buffer can't deadlock the child.
                let out = Box(), err = Box()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async { out.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                DispatchQueue.global().async { err.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: out.data, as: UTF8.self),
                    stderr: String(decoding: err.data, as: UTF8.self)))
            }
        }
    }

    /// Runs a user-configured command through the login shell so PATH matches Terminal.
    /// Only for commands the user typed into DevHub themselves.
    public static func loginShell(_ command: String, cwd: String? = nil,
                                  cancellation: Cancellation? = nil) async -> ShellResult {
        await run("/bin/zsh", ["-lc", command], cwd: cwd, cancellation: cancellation)
    }

    /// Environment with the user's login-shell PATH (GUI apps start with a minimal PATH).
    public static func loginEnvironment() async -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = await loginShell("printf %s \"$PATH\"")
        if path.ok, !path.stdout.isEmpty { env["PATH"] = path.stdout }
        return env
    }

    /// Finds the `claude` CLI.
    public static func findClaude() async -> String? {
        let which = await loginShell("command -v claude")
        let found = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if which.ok, !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) { return found }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
