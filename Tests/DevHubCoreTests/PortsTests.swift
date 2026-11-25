import XCTest
@testable import DevHubCore

final class PortScannerTests: XCTestCase {

    // Real-world shaped `lsof -nP -iTCP -sTCP:LISTEN -FpcLn` output.
    let sample = """
    p812
    cControlCenter
    Lhezy
    f9
    n*:7000
    f10
    n*:5000
    p4321
    cnode
    Lhezy
    f23
    n127.0.0.1:3000
    f24
    n[::1]:3000
    p90
    cpostgres
    L_postgres
    f7
    n127.0.0.1:5432
    """

    func testParsesAndSortsByPort() {
        let ports = PortScanner.parse(sample)
        XCTAssertEqual(ports.map(\.port), [3000, 5000, 5432, 7000])
    }

    func testMergesIPv4AndIPv6OfSameProcess() {
        let node = PortScanner.parse(sample).first { $0.port == 3000 }
        XCTAssertEqual(node?.pid, 4321)
        XCTAssertEqual(node?.command, "node")
        XCTAssertEqual(node?.addresses, ["127.0.0.1", "[::1]"])
        XCTAssertEqual(node?.isLocalOnly, true)
    }

    func testWildcardIsNotLocalOnly() {
        let cc = PortScanner.parse(sample).first { $0.port == 7000 }
        XCTAssertEqual(cc?.isLocalOnly, false)
        XCTAssertEqual(cc?.user, "hezy")
    }

    func testKeepsOwnerPerProcess() {
        XCTAssertEqual(PortScanner.parse(sample).first { $0.port == 5432 }?.user, "_postgres")
    }

    func testIgnoresGarbage() {
        XCTAssertTrue(PortScanner.parse("").isEmpty)
        XCTAssertTrue(PortScanner.parse("nno-pid:80\nxjunk").isEmpty)
    }
}

final class ProcessControlTests: XCTestCase {

    func testRefusesSystemAndOwnProcess() {
        XCTAssertThrowsError(try ProcessControl.terminate(pid: 1, owner: nil)) {
            XCTAssertEqual($0 as? ProcessControl.KillError, .protectedProcess)
        }
        XCTAssertThrowsError(try ProcessControl.terminate(pid: getpid(), owner: nil)) {
            XCTAssertEqual($0 as? ProcessControl.KillError, .protectedProcess)
        }
    }

    func testRefusesOtherUsersProcess() {
        XCTAssertThrowsError(try ProcessControl.terminate(pid: 99_999, owner: "root", currentUser: "hezy")) {
            XCTAssertEqual($0 as? ProcessControl.KillError, .notOwned)
        }
    }

    func testTerminatesOwnChild() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        try ProcessControl.terminate(pid: p.processIdentifier, owner: NSUserName())
        p.waitUntilExit()
        XCTAssertEqual(p.terminationReason, .uncaughtSignal)
    }
}

final class ProcessStatsTests: XCTestCase {

    let ps = """
        1     0   0.0   1000
      500     1   2.5  20000
      501   500  10.0  50000
      502   501   1,5  10000
      600     1  99.0 900000
    """

    func testParsesIncludingCommaDecimals() {
        let entries = ProcessStats.parse(ps)
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.first { $0.pid == 502 }?.cpu, 1.5)
    }

    func testSumsWholeTreeOnly() {
        let usage = ProcessStats.usage(ofTree: 500, in: ProcessStats.parse(ps))
        XCTAssertEqual(usage.processCount, 3)
        XCTAssertEqual(usage.cpuPercent, 14.0, accuracy: 0.001)
        XCTAssertEqual(usage.residentBytes, 80_000 * 1024)
    }

    func testDescendants() {
        XCTAssertEqual(ProcessStats.descendants(of: 500, in: ProcessStats.parse(ps)), [500, 501, 502])
    }

    func testSurvivesCycles() {
        let cyclic = [ProcessStats.Entry(pid: 10, ppid: 11, cpu: 1, rssKB: 1),
                      ProcessStats.Entry(pid: 11, ppid: 10, cpu: 1, rssKB: 1)]
        XCTAssertEqual(ProcessStats.usage(ofTree: 10, in: cyclic).processCount, 2)
    }
}

final class SettingsTests: XCTestCase {

    func testSanitizeClampsAndRejectsBadModel() {
        var s = AppSettings()
        s.maxAttempts = 99
        s.maxTurns = 0
        s.model = "opus; rm -rf ~"
        let clean = s.sanitized()
        XCTAssertEqual(clean.maxAttempts, 5)
        XCTAssertEqual(clean.maxTurns, 5)
        XCTAssertEqual(clean.model, "")
    }

    func testKeepsValidModel() {
        var s = AppSettings()
        s.model = "claude-opus-5-5"
        XCTAssertEqual(s.sanitized().model, "claude-opus-5-5")
    }

    func testDecodesPartialFile() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"maxAttempts":2}"#.utf8))
        XCTAssertEqual(s.maxAttempts, 2)
        XCTAssertEqual(s.maxTurns, 30)
        XCTAssertTrue(s.notifyOnFixReady)
    }

    @MainActor
    func testStorePersists() async throws {
        let tmp = try TempDir()
        let file = tmp.url.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: file)
        store.settings.maxAttempts = 4
        XCTAssertEqual(SettingsStore(fileURL: file).settings.maxAttempts, 4)
    }

    func testModelAndTurnsReachClaudeArguments() {
        let args = FixSession.claudeArguments(prompt: "x", resume: nil, maxTurns: 12, model: "sonnet")
        XCTAssertEqual(args[args.firstIndex(of: "--max-turns")! + 1], "12")
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "sonnet")
        XCTAssertFalse(FixSession.claudeArguments(prompt: "x", resume: nil).contains("--model"))
    }
}
