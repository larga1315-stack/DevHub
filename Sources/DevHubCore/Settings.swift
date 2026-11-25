import Foundation

public struct AppSettings: Codable, Equatable {
    /// Empty = find `claude` automatically.
    public var claudePath: String = ""
    /// Empty = Claude Code's default model. Passed as `--model`.
    public var model: String = ""
    public var maxAttempts: Int = 3
    public var maxTurns: Int = 30
    public var notifyOnCrash: Bool = true
    public var notifyOnFixReady: Bool = true
    public var portRefreshSeconds: Int = 3
    /// Run projects under a pseudo-terminal (keeps output printed right before a crash).
    public var usePTY: Bool = true

    public init() {}

    public static let attemptsRange = 1...5
    public static let turnsRange = 5...100

    /// Clamps values loaded from disk or typed by the user.
    public func sanitized() -> AppSettings {
        var s = self
        s.maxAttempts = min(max(s.maxAttempts, Self.attemptsRange.lowerBound), Self.attemptsRange.upperBound)
        s.maxTurns = min(max(s.maxTurns, Self.turnsRange.lowerBound), Self.turnsRange.upperBound)
        s.portRefreshSeconds = min(max(s.portRefreshSeconds, 1), 60)
        s.claudePath = s.claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        // Model names are simple identifiers; anything else is dropped rather than passed to the CLI.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        s.model = s.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.model.unicodeScalars.contains(where: { !allowed.contains($0) }) { s.model = "" }
        return s
    }

    // Tolerant decoding: new settings added later get their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? d.claudePath
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        maxAttempts = try c.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? d.maxAttempts
        maxTurns = try c.decodeIfPresent(Int.self, forKey: .maxTurns) ?? d.maxTurns
        notifyOnCrash = try c.decodeIfPresent(Bool.self, forKey: .notifyOnCrash) ?? d.notifyOnCrash
        notifyOnFixReady = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFixReady) ?? d.notifyOnFixReady
        portRefreshSeconds = try c.decodeIfPresent(Int.self, forKey: .portRefreshSeconds) ?? d.portRefreshSeconds
        usePTY = try c.decodeIfPresent(Bool.self, forKey: .usePTY) ?? d.usePTY
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            let clean = settings.sanitized()
            if clean != settings { settings = clean; return }
            save()
        }
    }
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("settings.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded.sanitized()
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
