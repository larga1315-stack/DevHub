import XCTest
@testable import DevHubCore

final class RunnerTests: XCTestCase {

    func testCleanStripsTerminalNoise() {
        XCTAssertEqual(ProjectRunner.clean("\u{1B}[31mFatal error\u{1B}[0m\r"), "Fatal error")
        XCTAssertEqual(ProjectRunner.clean("\u{1B}]0;title\u{07}hello"), "hello")
        XCTAssertEqual(ProjectRunner.clean("plain"), "plain")
    }

    func testRunEnvironmentEnablesBacktraces() {
        let env = ProjectRunner.runEnvironment(base: ["PATH": "/usr/bin"])
        XCTAssertEqual(env["SWIFT_BACKTRACE"], "enable=yes,interactive=no,color=no")
        XCTAssertEqual(env["PATH"], "/usr/bin")
    }

    func testRunEnvironmentRespectsUserBacktraceSetting() {
        let env = ProjectRunner.runEnvironment(base: ["SWIFT_BACKTRACE": "enable=no"])
        XCTAssertEqual(env["SWIFT_BACKTRACE"], "enable=no")
    }

    func testLaunchCommandWithoutPTY() {
        let (exe, args) = ProjectRunner.launchCommand(for: "swift run", usePTY: false)
        XCTAssertEqual(exe, "/bin/zsh")
        XCTAssertEqual(args, ["-lc", "swift run"])
    }

    func testLaunchCommandWithPTYKeepsCommandAsSingleArgument() {
        let (exe, args) = ProjectRunner.launchCommand(for: "swift run; echo hi", usePTY: true)
        if exe == "/usr/bin/script" {
            XCTAssertEqual(args.last, "swift run; echo hi")
            XCTAssertEqual(Array(args.prefix(2)), ["-q", "/dev/null"])
        } else {
            XCTAssertEqual(exe, "/bin/zsh")   // no `script` on this machine
        }
    }
}
