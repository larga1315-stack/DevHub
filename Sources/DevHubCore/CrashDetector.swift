import Foundation

public struct FileRef: Hashable, Codable {
    public let relativePath: String
    public let line: Int
    public var display: String { "\(relativePath):\(line)" }

    public init(relativePath: String, line: Int) {
        self.relativePath = relativePath
        self.line = line
    }
}

public struct CrashReport: Identifiable {
    public let id = UUID()
    public let triggerLine: String
    /// Log lines around the crash (raw — redact before sending or storing).
    public let excerpt: [String]
    /// Source locations inside the project mentioned in the excerpt.
    public let fileRefs: [FileRef]
    public let date = Date()

    public init(triggerLine: String, excerpt: [String], fileRefs: [FileRef]) {
        self.triggerLine = triggerLine
        self.excerpt = excerpt
        self.fileRefs = fileRefs
    }
}

public enum CrashDetector {
    public static let markers: [String] = [
        "Fatal error:",
        "Terminating app due to uncaught exception",
        "EXC_BAD_ACCESS",
        "EXC_BREAKPOINT",
        "Crashed Thread",
        "Segmentation fault",
        "Abort trap",
        "Illegal instruction",
        "Precondition failed",
        "Assertion failed",
        "panic:",
        "Traceback (most recent call last)",
        "Unhandled exception",
        "UnhandledPromiseRejection",
        "FATAL EXCEPTION",
        "Program crashed:",            // Swift runtime backtracer
        "segmentation fault",          // zsh job messages
        "illegal hardware instruction",
        "bus error",
        "Stack overflow",
    ]

    public static func isCrashLine(_ line: String) -> Bool {
        markers.contains { line.contains($0) }
    }

    private static let extensions = "swift|m|mm|h|c|cc|cpp|py|js|jsx|ts|tsx|kt|java|go|rs|rb"
    private static let refRegex = try! NSRegularExpression(
        pattern: #"((?:/|\./)?[A-Za-z0-9_\-./]+\.(?:"# + extensions + #")):(\d+)"#)
    // Older Swift runtime format: "file MyApp/Foo.swift, line 42"
    private static let swiftLegacyRegex = try! NSRegularExpression(
        pattern: #"file ([^\s,]+\.(?:"# + extensions + #")), line (\d+)"#)

    /// Extracts file:line references that resolve to real files inside the project root.
    public static func fileRefs(in lines: [String], projectRoot: String) -> [FileRef] {
        let root = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        var seen = Set<FileRef>()
        var result: [FileRef] = []

        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = refRegex.matches(in: line, range: range) + swiftLegacyRegex.matches(in: line, range: range)
            for match in matches {
                let rawPath = ns.substring(with: match.range(at: 1))
                guard let lineNo = Int(ns.substring(with: match.range(at: 2))),
                      let absolute = resolve(rawPath, root: root) else { continue }

                let ref = FileRef(relativePath: String(absolute.dropFirst(root.count + 1)), line: lineNo)
                if seen.insert(ref).inserted { result.append(ref) }
            }
        }
        return result
    }

    /// Resolves a path from a log to a file inside the project. Anything outside returns nil,
    /// so another project's code is never pulled in.
    static func resolve(_ rawPath: String, root: String) -> String? {
        let fm = FileManager.default
        let direct = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath).standardizedFileURL.path
            : URL(fileURLWithPath: root).appendingPathComponent(rawPath).standardizedFileURL.path
        if direct.hasPrefix(root + "/"), fm.fileExists(atPath: direct) { return direct }
        if rawPath.hasPrefix("/") { return nil }

        // Relative paths like "MyApp/Foo.swift" often omit "Sources/": match by path suffix.
        let suffix = "/" + rawPath.replacingOccurrences(of: "./", with: "")
        guard let walker = fm.enumerator(atPath: root) else { return nil }
        var checked = 0
        while let item = walker.nextObject() as? String, checked < 20_000 {
            checked += 1
            let name = (item as NSString).lastPathComponent
            if ProjectDetector.ignoredDirectories.contains(name) {
                walker.skipDescendants()
                continue
            }
            if ("/" + item).hasSuffix(suffix) { return root + "/" + item }
        }
        return nil
    }
}

/// Masks common secret formats before log text leaves the machine or is written to disk
/// (mitigates CWE-532 / CWE-200). Best-effort, not a guarantee.
public enum Redactor {
    private static let patterns: [NSRegularExpression] = [
        #"sk-ant-[A-Za-z0-9_\-]{10,}"#,                                   // Anthropic
        #"sk-(?:proj-)?[A-Za-z0-9_\-]{20,}"#,                             // OpenAI
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,                                   // GitHub
        #"AKIA[0-9A-Z]{16}"#,                                             // AWS access key id
        #"AIza[0-9A-Za-z_\-]{35}"#,                                       // Google API key
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#,                               // Slack
        #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, // JWT
        #"(?i)bearer\s+[A-Za-z0-9._\-]{16,}"#,
        #"(?i)(password|passwd|secret|token|api[_-]?key)\s*[=:]\s*\S+"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func redact(_ text: String) -> String {
        var output = text
        for regex in patterns {
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "<REDACTED>")
        }
        return output
    }
}
