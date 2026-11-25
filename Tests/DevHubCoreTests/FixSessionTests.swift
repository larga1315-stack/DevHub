import XCTest
@testable import DevHubCore

final class FixSessionTests: XCTestCase {

    private func crash(_ lines: [String]) -> CrashReport {
        CrashReport(triggerLine: lines.last ?? "", excerpt: lines, fileRefs: [])
    }

    func testPromptWrapsLogAsUntrustedData() {
        let project = Project(name: "Demo", path: "/tmp/demo", runCommand: "swift run")
        let prompt = FixSession.crashPrompt(project: project, crash: crash(["Fatal error: boom"]))
        XCTAssertTrue(prompt.contains("<runtime_log>"))
        XCTAssertTrue(prompt.contains("</runtime_log>"))
    }

    func testPromptRedactsSecrets() {
        let project = Project(name: "Demo", path: "/tmp/demo", runCommand: "swift run")
        let prompt = FixSession.crashPrompt(
            project: project,
            crash: crash(["token=" + "sk-" + "ant-api03-" + "supersecretvalue123", "Fatal error: boom"]))
        XCTAssertFalse(prompt.contains("supersecretvalue"))
    }

    func testClaudeGetsNoShellOrNetwork() {
        let args = FixSession.claudeArguments(prompt: "x", resume: nil)
        let allowed = args[args.firstIndex(of: "--allowedTools")! + 1]
        let denied = args[args.firstIndex(of: "--disallowedTools")! + 1]
        XCTAssertFalse(allowed.contains("Bash"))
        XCTAssertTrue(denied.contains("Bash"))
        XCTAssertTrue(denied.contains("WebFetch"))
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
    }

    func testGuardForbidsEditingTests() {
        XCTAssertTrue(FixSession.systemGuard.contains("Never modify, skip or delete tests"))
    }

    func testResumeFlagOnlyWhenSessionExists() {
        XCTAssertFalse(FixSession.claudeArguments(prompt: "x", resume: nil).contains("--resume"))
        let args = FixSession.claudeArguments(prompt: "x", resume: "abc")
        XCTAssertEqual(args[args.firstIndex(of: "--resume")! + 1], "abc")
    }

    func testParsesClaudeJSON() {
        let json = #"{"type":"result","is_error":false,"result":"תוקן","session_id":"s-1"}"#
        let reply = FixSession.parseReply(ShellResult(status: 0, stdout: json, stderr: ""))
        XCTAssertNil(reply.error)
        XCTAssertEqual(reply.text, "תוקן")
        XCTAssertEqual(reply.sessionID, "s-1")
    }

    func testParsesClaudeErrorAndGarbage() {
        let err = FixSession.parseReply(ShellResult(
            status: 1, stdout: #"{"is_error":true,"result":"Max turns"}"#, stderr: ""))
        XCTAssertEqual(err.error, "Max turns")

        let garbage = FixSession.parseReply(ShellResult(status: 127, stdout: "", stderr: "command not found"))
        XCTAssertEqual(garbage.error, "command not found")
    }

    func testBuildFailurePromptKeepsTailOnly() {
        let output = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let prompt = FixSession.buildFailurePrompt(output: output)
        XCTAssertTrue(prompt.contains("line 200"))
        XCTAssertFalse(prompt.contains("line 100\n"))
        XCTAssertTrue(prompt.contains("<build_output>"))
    }
}

final class StoreTests: XCTestCase {

    @MainActor
    func testProjectStoreRoundTrip() async throws {
        let tmp = try TempDir()
        let file = tmp.url.appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: file)
        let p = Project(name: "A", path: "/a", runCommand: "run", kind: .swiftPackage)
        store.upsert(p)
        XCTAssertEqual(ProjectStore(fileURL: file).projects, [p])
    }

    func testDecodesLegacyProjectWithoutKind() throws {
        let json = #"[{"id":"5E1D7E9C-0D3B-4B8A-9F5E-1A2B3C4D5E6F","name":"Old","path":"/x","runCommand":"swift run","buildCommand":"swift build"}]"#
        let projects = try JSONDecoder().decode([Project].self, from: Data(json.utf8))
        XCTAssertEqual(projects.first?.kind, .other)
    }

    @MainActor
    func testHistoryRedactsAndCaps() async throws {
        let tmp = try TempDir()
        let history = CrashHistory(directory: tmp.url, limit: 3)
        let id = UUID()
        for i in 0..<5 {
            let report = CrashReport(triggerLine: "Fatal \(i) password=hunter2", excerpt: [], fileRefs: [])
            history.add(CrashRecord(report: report), projectID: id)
        }
        let reloaded = CrashHistory(directory: tmp.url, limit: 3)
        reloaded.preload(id)
        let records = reloaded.records(for: id)
        XCTAssertEqual(records.count, 3)
        XCTAssertTrue(records[0].triggerLine.hasPrefix("Fatal 4"))
        XCTAssertFalse(records.contains { $0.triggerLine.contains("hunter2") })
    }

    @MainActor
    func testHistoryUpdatesOutcome() async throws {
        let tmp = try TempDir()
        let history = CrashHistory(directory: tmp.url)
        let id = UUID()
        let record = CrashRecord(triggerLine: "x", fileRefs: [])
        history.add(record, projectID: id)
        history.update(record.id, projectID: id, outcome: .approved, summary: "fixed")
        XCTAssertEqual(history.records(for: id).first?.outcome, .approved)
    }
}
