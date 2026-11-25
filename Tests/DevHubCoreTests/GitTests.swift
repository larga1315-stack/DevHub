import XCTest
@testable import DevHubCore

/// Integration tests against a real git binary in a temp folder.
final class GitTests: XCTestCase {

    override func setUp() async throws {
        if !FileManager.default.isExecutableFile(atPath: Git.executable) {
            throw XCTSkip("git not installed")
        }
    }

    func testStateOfPlainFolder() async throws {
        let tmp = try TempDir()
        let state = await Git.state(in: tmp.path)
        XCTAssertEqual(state, .notRepo)
    }

    func testInitializeCreatesCommitAndGitignore() async throws {
        let tmp = try TempDir()
        try tmp.file("main.swift", "print(1)")
        try tmp.file(".env", "SECRET=1")

        try await Git.initialize(in: tmp.path)

        let state = await Git.state(in: tmp.path)
        XCTAssertEqual(state, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path + "/.gitignore"))

        let tracked = await Shell.run(Git.executable, ["ls-files"], cwd: tmp.path).stdout
        XCTAssertTrue(tracked.contains("main.swift"))
        XCTAssertFalse(tracked.contains(".env"), ".env must never be committed")
    }

    func testInitializeKeepsExistingGitignore() async throws {
        let tmp = try TempDir()
        try tmp.file(".gitignore", "custom\n")
        try await Git.initialize(in: tmp.path)
        let contents = try String(contentsOfFile: tmp.path + "/.gitignore", encoding: .utf8)
        XCTAssertEqual(contents, "custom\n")
    }

    func testSnapshotDiffRestoreRoundTrip() async throws {
        let tmp = try TempDir()
        try tmp.file("a.swift", "let x = 1\n")
        try await Git.initialize(in: tmp.path)

        // Uncommitted user edit — must survive the round trip.
        try tmp.file("a.swift", "let x = 2\n")
        let snap = try await Git.snapshot(in: tmp.path)

        // "Claude" edits the file and adds a new one.
        try tmp.file("a.swift", "let x = 3\n")
        try tmp.file("b.swift", "let y = 1\n")

        let diff = await Git.diff(since: snap, in: tmp.path)
        XCTAssertTrue(diff.diff.contains("-let x = 2"))
        XCTAssertTrue(diff.diff.contains("+let x = 3"))
        XCTAssertEqual(diff.newFiles, ["b.swift"])

        try await Git.restore(snap, in: tmp.path)
        let restored = try String(contentsOfFile: tmp.path + "/a.swift", encoding: .utf8)
        XCTAssertEqual(restored, "let x = 2\n", "Restore must return the user's uncommitted state")
    }

    func testSnapshotFailsWithoutRepo() async throws {
        let tmp = try TempDir()
        do {
            _ = try await Git.snapshot(in: tmp.path)
            XCTFail("Expected notARepo")
        } catch let error as GitError {
            XCTAssertEqual(error, .notARepo)
        }
    }
}
