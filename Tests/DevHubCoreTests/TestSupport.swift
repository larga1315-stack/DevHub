import Foundation
import XCTest

/// Creates a throwaway directory tree for a test.
final class TempDir {
    let url: URL
    var path: String { url.path }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhub-tests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ relative: String, _ contents: String = "") throws -> String {
        let fileURL = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    func dir(_ relative: String) throws -> String {
        let dirURL = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL.path
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
