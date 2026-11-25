public enum ManifestError: Error, Equatable {
    case badLine(Int)
}

/// Format, one task per line:   name  duration  priority  dep1, dep2   (use "-" for no deps)
/// Lines starting with "#" are comments.
public enum ManifestParser {
    public static func parse(_ text: String) throws -> [BuildTask] {
        var tasks: [BuildTask] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 4, let priority = Int(parts[2]) else { throw ManifestError.badLine(index + 1) }
            let deps = parts[3] == "-" ? [] : parts[3].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            tasks.append(BuildTask(name: parts[0], duration: Duration.seconds(parts[1]),
                                   priority: priority, deps: deps))
        }
        return tasks
    }
}

private extension StringProtocol {
    func trimmingCharacters(in set: Set<Character>) -> String {
        var s = Substring(self)
        while let f = s.first, set.contains(f) { s.removeFirst() }
        while let l = s.last, set.contains(l) { s.removeLast() }
        return String(s)
    }
}

private extension Set where Element == Character {
    static let whitespaces: Set<Character> = [" ", "\t", "\r"]
}
