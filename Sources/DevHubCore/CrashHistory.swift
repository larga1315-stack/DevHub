import Foundation

public enum FixOutcome: String, Codable {
    case open, approved, rejected, failed, cancelled

    public var label: String {
        switch self {
        case .open: return "פתוח"
        case .approved: return "תוקן"
        case .rejected: return "בוטל"
        case .failed: return "נכשל"
        case .cancelled: return "הופסק"
        }
    }
}

/// A crash as stored on disk. Text is redacted before saving (CWE-532).
public struct CrashRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let triggerLine: String
    public let fileRefs: [String]
    public var outcome: FixOutcome
    public var summary: String?

    public init(id: UUID = UUID(), date: Date = Date(), triggerLine: String,
                fileRefs: [String], outcome: FixOutcome = .open, summary: String? = nil) {
        self.id = id
        self.date = date
        self.triggerLine = triggerLine
        self.fileRefs = fileRefs
        self.outcome = outcome
        self.summary = summary
    }

    public init(report: CrashReport) {
        self.init(id: report.id, date: report.date,
                  triggerLine: Redactor.redact(report.triggerLine),
                  fileRefs: report.fileRefs.map(\.display))
    }
}

/// Keeps the last `limit` crashes per project in history/<projectID>.json.
@MainActor
public final class CrashHistory: ObservableObject {
    @Published public private(set) var records: [UUID: [CrashRecord]] = [:]
    private let directory: URL
    private let limit: Int

    public init(directory: URL = AppPaths.historyDirectory, limit: Int = 50) {
        self.directory = directory
        self.limit = limit
    }

    /// Side-effect free — safe to call from a SwiftUI body. Call `preload` first.
    public func records(for projectID: UUID) -> [CrashRecord] {
        records[projectID] ?? []
    }

    /// Loads a project's history from disk once.
    public func preload(_ projectID: UUID) {
        if records[projectID] == nil { records[projectID] = load(projectID) }
    }

    private func stored(_ projectID: UUID) -> [CrashRecord] {
        records[projectID] ?? load(projectID)
    }

    public func add(_ record: CrashRecord, projectID: UUID) {
        var list = stored(projectID)
        list.insert(record, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        records[projectID] = list
        save(projectID)
    }

    public func update(_ recordID: UUID, projectID: UUID, outcome: FixOutcome, summary: String? = nil) {
        var list = stored(projectID)
        guard let i = list.firstIndex(where: { $0.id == recordID }) else { return }
        list[i].outcome = outcome
        if let summary { list[i].summary = Redactor.redact(summary) }
        records[projectID] = list
        save(projectID)
    }

    public func clear(projectID: UUID) {
        records[projectID] = []
        save(projectID)
    }

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func load(_ id: UUID) -> [CrashRecord] {
        guard let data = try? Data(contentsOf: file(id)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CrashRecord].self, from: data)) ?? []
    }

    private func save(_ id: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(records[id] ?? []) else { return }
        try? data.write(to: file(id), options: [.atomic])
    }
}
