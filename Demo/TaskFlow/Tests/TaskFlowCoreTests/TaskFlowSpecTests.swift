import XCTest
@testable import TaskFlowCore

/// The specification. A correct fix makes every test pass — without editing this file.

final class DurationTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(Duration.seconds("45s"), 45)
        XCTAssertEqual(Duration.seconds("2m"), 120)
        XCTAssertEqual(Duration.seconds("2h"), 7200)
        XCTAssertEqual(Duration.seconds("0s"), 0)
    }

    func testCompoundAndFractions() {
        XCTAssertEqual(Duration.seconds("1m30s"), 90)
        XCTAssertEqual(Duration.seconds("1.5s"), 1.5)
        XCTAssertEqual(Duration.seconds("1h2m3s"), 3723)
    }

    func testMilliseconds() {
        XCTAssertEqual(Duration.seconds("500ms"), 0.5)
        XCTAssertEqual(Duration.seconds("1s250ms"), 1.25)
    }
}

final class FingerprintTests: XCTestCase {
    // Reference values of 64-bit FNV-1a.
    func testKnownVectors() {
        XCTAssertEqual(Fingerprint.of(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(Fingerprint.of("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(Fingerprint.of("hello"), 0xa430_d846_80aa_bd0b)
    }

    func testHexIsZeroPadded() {
        XCTAssertEqual(Fingerprint.hex("hello"), "a430d84680aabd0b")
        XCTAssertEqual(Fingerprint.hex("hello").count, 16)
    }

    func testLongInputsAndUnicode() {
        let long = String(repeating: "build-cache-", count: 2_000)
        XCTAssertEqual(Fingerprint.of(long), Fingerprint.of(long))
        XCTAssertNotEqual(Fingerprint.of("קומפילציה"), Fingerprint.of("compile"))
    }
}

final class SchedulerTests: XCTestCase {
    let manifest = """
    # name      duration  priority  deps
    fetch       12s       5         -
    assets      500ms     1         fetch
    compile     2m        9         fetch
    test        1m30s     7         compile
    sign        3s        3         compile
    package     45s       5         compile, assets, sign
    release     0s        0         package, test
    lint        20s       2         -
    codegen     30s       4         checks
    typecheck   1m        6         codegen
    checks      0s        0         lint, typecheck
    all         0s        0         release, checks
    """

    func scheduler() throws -> Scheduler { Scheduler(try ManifestParser.parse(manifest)) }

    func testReleasePlanOrder() throws {
        XCTAssertEqual(try scheduler().plan("release"),
                       ["fetch", "compile", "test", "sign", "assets", "package", "release"])
    }

    func testPlanIsDeterministic() throws {
        let s = try scheduler()
        let first = try s.plan("release")
        for _ in 0..<50 { XCTAssertEqual(try s.plan("release"), first) }
    }

    func testTiesBrokenByName() throws {
        let s = Scheduler([
            BuildTask(name: "zeta", duration: 1, priority: 1, deps: []),
            BuildTask(name: "alpha", duration: 1, priority: 1, deps: []),
            BuildTask(name: "mid", duration: 1, priority: 1, deps: []),
            BuildTask(name: "root", duration: 0, priority: 0, deps: ["zeta", "alpha", "mid"]),
        ])
        XCTAssertEqual(try s.plan("root"), ["alpha", "mid", "zeta", "root"])
    }

    func testMakespanWithTwoWorkers() throws {
        XCTAssertEqual(try scheduler().makespan("release", workers: 2), 222)
    }

    func testCycleIsReportedNotCrashed() throws {
        XCTAssertThrowsError(try scheduler().plan("all")) { error in
            XCTAssertEqual(error as? PlanError, .cycle(["checks", "typecheck", "codegen", "checks"]))
        }
    }

    func testSelfCycle() {
        let s = Scheduler([BuildTask(name: "x", duration: 1, priority: 1, deps: ["x"])])
        XCTAssertThrowsError(try s.plan("x")) { error in
            XCTAssertEqual(error as? PlanError, .cycle(["x", "x"]))
        }
    }

    func testUnknownDependency() {
        let s = Scheduler([BuildTask(name: "app", duration: 1, priority: 1, deps: ["ghost"])])
        XCTAssertThrowsError(try s.plan("app")) { error in
            XCTAssertEqual(error as? PlanError, .unknownTask("ghost", requiredBy: "app"))
        }
    }

    func testDeepChainDoesNotOverflowTheStack() throws {
        let n = 20_000
        var tasks = [BuildTask(name: "t0", duration: 1, priority: 0, deps: [])]
        for i in 1..<n { tasks.append(BuildTask(name: "t\(i)", duration: 1, priority: 0, deps: ["t\(i - 1)"])) }
        let order = try Scheduler(tasks).plan("t\(n - 1)")
        XCTAssertEqual(order.count, n)
        XCTAssertEqual(order.first, "t0")
    }

    func testDiamondHasNoDuplicates() throws {
        let s = Scheduler([
            BuildTask(name: "base", duration: 1, priority: 0, deps: []),
            BuildTask(name: "left", duration: 1, priority: 0, deps: ["base"]),
            BuildTask(name: "right", duration: 1, priority: 0, deps: ["base"]),
            BuildTask(name: "top", duration: 1, priority: 0, deps: ["left", "right"]),
        ])
        XCTAssertEqual(try s.plan("top"), ["base", "left", "right", "top"])
    }
}
