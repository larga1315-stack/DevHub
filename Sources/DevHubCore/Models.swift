import Foundation

public enum ProjectKind: String, Codable, CaseIterable {
    case swiftPackage, xcode, node, other

    public var label: String {
        switch self {
        case .swiftPackage: return "Swift Package"
        case .xcode: return "Xcode"
        case .node: return "Node"
        case .other: return "אחר"
        }
    }
}

/// A development project that DevHub can run and repair.
public struct Project: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    /// Absolute path of the project root.
    public var path: String
    /// Command that runs the app in the foreground so stdout/stderr are captured.
    public var runCommand: String
    /// Command used to verify a fix compiles. Empty = skip.
    public var buildCommand: String
    public var kind: ProjectKind
    /// Claude Code session for this project only — never shared across projects.
    public var claudeSessionID: String?

    public init(id: UUID = UUID(), name: String = "", path: String = "",
                runCommand: String = "", buildCommand: String = "",
                kind: ProjectKind = .other, claudeSessionID: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.runCommand = runCommand
        self.buildCommand = buildCommand
        self.kind = kind
        self.claudeSessionID = claudeSessionID
    }

    // Tolerant decoding so older projects.json files (without `kind`) still load.
    enum CodingKeys: String, CodingKey { case id, name, path, runCommand, buildCommand, kind, claudeSessionID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        runCommand = try c.decode(String.self, forKey: .runCommand)
        buildCommand = try c.decodeIfPresent(String.self, forKey: .buildCommand) ?? ""
        kind = try c.decodeIfPresent(ProjectKind.self, forKey: .kind) ?? .other
        claudeSessionID = try c.decodeIfPresent(String.self, forKey: .claudeSessionID)
    }
}

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("DevHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public static var projectsFile: URL { supportDirectory.appendingPathComponent("projects.json") }
    public static var historyDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Persists projects as JSON.
@MainActor
public final class ProjectStore: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.projectsFile) {
        self.fileURL = fileURL
        load()
    }

    public func upsert(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        save()
    }

    public func remove(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    public func project(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
