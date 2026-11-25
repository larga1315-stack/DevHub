import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct LogLine: Identifiable {
    public let id = UUID()
    public let text: String
    public let isError: Bool
}

public enum RunStatus: Equatable {
    case stopped
    case running
    case exited(Int32)
    case crashed

    public var label: String {
        switch self {
        case .stopped: return "כבוי"
        case .running: return "רץ"
        case .exited(let code): return code == 0 ? "הסתיים בהצלחה" : "יצא עם קוד \(code)"
        case .crashed: return "קרס"
        }
    }
}

/// Runs one project's run command and watches its output for crashes.
@MainActor
public final class ProjectRunner: ObservableObject {
    @Published public private(set) var status: RunStatus = .stopped
    @Published public private(set) var logs: [LogLine] = []
    @Published public private(set) var crash: CrashReport?
    @Published public private(set) var startedAt: Date?

    /// Called once per detected crash (used for history).
    public var onCrash: ((CrashReport) -> Void)?

    public private(set) var project: Project
    /// Run under a pseudo-terminal so programs line-buffer stdout (otherwise output printed
    /// right before a crash is lost in the pipe buffer).
    public var usePTY = true
    private var process: Process?
    private var stoppedByUser = false
    private var pendingCrashLine: String?
    private var partial: [Bool: String] = [false: "", true: ""]
    private let maxLines = 5000

    public init(project: Project) { self.project = project }

    public func update(project: Project) { self.project = project }

    public var isRunning: Bool { status == .running }

    /// PID of the shell that runs the project's command (root of its process tree).
    public var pid: Int32? { process?.processIdentifier }

    public func start() {
        guard process == nil else { return }
        logs.removeAll()
        crash = nil
        pendingCrashLine = nil
        stoppedByUser = false
        partial = [false: "", true: ""]

        let p = Process()
        let (executable, arguments) = Self.launchCommand(for: project.runCommand, usePTY: usePTY)
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = URL(fileURLWithPath: project.path)
        p.environment = Self.runEnvironment()
        p.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        attach(out, isError: false)
        attach(err, isError: true)

        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            let signaled = proc.terminationReason == .uncaughtSignal
            Task { @MainActor in self?.handleTermination(code: code, signaled: signaled) }
        }

        do {
            try p.run()
            process = p
            status = .running
            startedAt = Date()
            append("▶︎ \(project.runCommand)", isError: false)
        } catch {
            append("לא הצלחתי להריץ: \(error.localizedDescription)", isError: true)
            status = .exited(-1)
        }
    }

    public func stop() {
        guard let p = process else { return }
        stoppedByUser = true
        let root = p.processIdentifier
        Task {
            // Stop the whole tree (script → zsh → swift run → app), deepest first.
            let entries = await ProcessStats.snapshot()
            let tree = ProcessStats.descendants(of: root, in: entries).subtracting([root])
            for pid in tree.sorted(by: >) { kill(pid, SIGTERM) }
            if p.isRunning { p.terminate() }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            for pid in tree where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    // MARK: - Launch configuration

    /// `script -q /dev/null zsh -lc <cmd>` gives the program a TTY (line-buffered output);
    /// `script` exits with the command's status.
    nonisolated public static func launchCommand(for command: String, usePTY: Bool) -> (String, [String]) {
        if usePTY, FileManager.default.isExecutableFile(atPath: "/usr/bin/script") {
            return ("/usr/bin/script", ["-q", "/dev/null", "/bin/zsh", "-lc", command])
        }
        return ("/bin/zsh", ["-lc", command])
    }

    /// Asks the Swift runtime for a symbolicated backtrace on crash (off by default on macOS),
    /// non-interactive so it never waits for input.
    nonisolated public static func runEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        if env["SWIFT_BACKTRACE"] == nil { env["SWIFT_BACKTRACE"] = "enable=yes,interactive=no,color=no" }
        env["NSUnbufferedIO"] = "YES"
        return env
    }

    nonisolated private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*\u{07}")

    /// Removes terminal escape codes and carriage returns added by the PTY.
    nonisolated public static func clean(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "\r", with: "")
        text = ansi.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                             withTemplate: "")
        return text.replacingOccurrences(of: "^D\u{08}\u{08}", with: "")
    }

    public func restart() {
        guard process != nil else { start(); return }
        stop()
        Task {
            for _ in 0..<50 where process != nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            start()
        }
    }

    public func clearCrash() {
        crash = nil
        if status == .crashed { status = .stopped }
    }

    public func clearLogs() { logs.removeAll() }

    // MARK: - Output

    private func attach(_ pipe: Pipe, isError: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.ingest(chunk, isError: isError) }
        }
    }

    private func ingest(_ chunk: String, isError: Bool) {
        let text = (partial[isError] ?? "") + chunk
        var lines = text.components(separatedBy: "\n")
        partial[isError] = lines.removeLast()
        for line in lines { append(Self.clean(line), isError: isError) }
    }

    private func append(_ line: String, isError: Bool) {
        logs.append(LogLine(text: line, isError: isError))
        if logs.count > maxLines { logs.removeFirst(logs.count - maxLines) }

        if pendingCrashLine == nil, CrashDetector.isCrashLine(line) {
            pendingCrashLine = line
            // Some crashes keep the process alive briefly; report once trailing lines arrive.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.crash == nil, self.pendingCrashLine != nil { self.reportCrash() }
            }
        }
    }

    private func handleTermination(code: Int32, signaled: Bool) {
        for isError in [false, true] {
            if let rest = partial[isError], !rest.isEmpty { append(Self.clean(rest), isError: isError) }
        }
        partial = [false: "", true: ""]
        process = nil

        if stoppedByUser {
            status = .stopped
            append("■ נעצר", isError: false)
            return
        }

        if pendingCrashLine != nil || signaled || code != 0 {
            if crash == nil { reportCrash(exitCode: code) }
            status = .crashed
        } else {
            status = .exited(code)
            append("✓ הסתיים (קוד 0)", isError: false)
        }
    }

    private func reportCrash(exitCode: Int32? = nil) {
        let texts = logs.map(\.text)
        let triggerIndex = pendingCrashLine.flatMap { t in texts.lastIndex(of: t) } ?? (texts.count - 1)
        let lower = max(0, triggerIndex - 40)
        let upper = min(texts.count, max(triggerIndex + 40, lower + 1))
        let excerpt = Array(texts[lower..<upper])

        let trigger = pendingCrashLine
            ?? texts.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "התהליך יצא עם קוד \(exitCode ?? -1)"

        let report = CrashReport(
            triggerLine: trigger,
            excerpt: excerpt,
            fileRefs: CrashDetector.fileRefs(in: excerpt, projectRoot: project.path))
        crash = report
        if process == nil { status = .crashed }
        onCrash?(report)
    }
}
