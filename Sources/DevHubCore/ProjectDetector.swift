import Foundation

public struct DetectedProject: Equatable {
    public let root: String
    public let name: String
    public let kind: ProjectKind
    public let runCommand: String
    public let buildCommand: String
}

/// Finds a project's root folder and suggests run/build commands.
public enum ProjectDetector {
    public static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", ".devhub-build", "node_modules", "DerivedData", "Pods", "build",
    ]

    /// Walks up from `path` to the nearest folder that looks like a project root
    /// (.git, Package.swift, *.xcodeproj, *.xcworkspace, package.json).
    /// Never returns the home folder or `/`. Returns nil when nothing is found.
    public static func findRoot(from path: String,
                                home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        let stop = URL(fileURLWithPath: home).standardizedFileURL.path
        while url.path != "/" && url.path != stop {
            if isProjectRoot(url.path) { return url.path }
            url.deleteLastPathComponent()
        }
        return nil
    }

    public static func isProjectRoot(_ path: String) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return items.contains { item in
            item == ".git" || item == "Package.swift" || item == "package.json"
                || item.hasSuffix(".xcodeproj") || item.hasSuffix(".xcworkspace")
        }
    }

    /// Suggests commands for the project at `root`.
    public static func detect(at root: String, scheme: String? = nil) -> DetectedProject {
        let items = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).sorted()
        let name = URL(fileURLWithPath: root).lastPathComponent

        let workspace = items.first { $0.hasSuffix(".xcworkspace") }
        let xcodeproj = items.first { $0.hasSuffix(".xcodeproj") }

        if let container = workspace ?? xcodeproj {
            let scheme = scheme ?? (container as NSString).deletingPathExtension
            let flag = workspace != nil ? "-workspace" : "-project"
            let build = "xcodebuild \(flag) \(quote(container)) -scheme \(quote(scheme)) "
                + "-configuration Debug -derivedDataPath .devhub-build -quiet build"
            let binary = "./.devhub-build/Build/Products/Debug/\(scheme).app/Contents/MacOS/\(scheme)"
            return DetectedProject(root: root, name: name, kind: .xcode,
                                   runCommand: "\(build) && \(quote(binary))", buildCommand: build)
        }
        if items.contains("Package.swift") {
            // `swift test` builds everything and runs the tests — a stronger check for fixes.
            let verify = items.contains("Tests") ? "swift test" : "swift build"
            return DetectedProject(root: root, name: name, kind: .swiftPackage,
                                   runCommand: "swift run", buildCommand: verify)
        }
        if items.contains("package.json") {
            return DetectedProject(root: root, name: name, kind: .node,
                                   runCommand: "npm run dev", buildCommand: "npm run build")
        }
        return DetectedProject(root: root, name: name, kind: .other, runCommand: "", buildCommand: "")
    }

    /// Lists Xcode schemes via `xcodebuild -list -json`.
    public static func xcodeSchemes(at root: String) async -> [String] {
        let result = await Shell.run("/usr/bin/xcrun", ["xcodebuild", "-list", "-json"], cwd: root)
        guard result.ok,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let container = (json["project"] as? [String: Any]) ?? (json["workspace"] as? [String: Any])
        return (container?["schemes"] as? [String]) ?? []
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
