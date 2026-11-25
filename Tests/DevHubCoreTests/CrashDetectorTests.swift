import XCTest
@testable import DevHubCore

final class CrashDetectorTests: XCTestCase {

    func testDetectsCommonCrashMarkers() {
        XCTAssertTrue(CrashDetector.isCrashLine("MyApp/main.swift:12: Fatal error: Unexpectedly found nil"))
        XCTAssertTrue(CrashDetector.isCrashLine("*** Terminating app due to uncaught exception 'NSInvalidArgumentException'"))
        XCTAssertTrue(CrashDetector.isCrashLine("Traceback (most recent call last):"))
        XCTAssertTrue(CrashDetector.isCrashLine("panic: runtime error: index out of range"))
        XCTAssertTrue(CrashDetector.isCrashLine("*** Program crashed: Illegal instruction at 0x0000000100003f2c ***"))
        XCTAssertTrue(CrashDetector.isCrashLine("zsh: segmentation fault  swift run"))
        XCTAssertTrue(CrashDetector.isCrashLine("zsh: illegal hardware instruction  ./TaskFlow"))
    }

    func testIgnoresNormalOutput() {
        XCTAssertFalse(CrashDetector.isCrashLine("Server listening on port 3000"))
        XCTAssertFalse(CrashDetector.isCrashLine("Loaded 12 users"))
    }

    func testResolvesAbsolutePathInsideProject() throws {
        let tmp = try TempDir()
        let file = try tmp.file("Sources/App/main.swift", "print(1)")
        let refs = CrashDetector.fileRefs(in: ["\(file):42: Fatal error: boom"], projectRoot: tmp.path)
        XCTAssertEqual(refs, [FileRef(relativePath: "Sources/App/main.swift", line: 42)])
    }

    func testResolvesRelativePathBySuffix() throws {
        let tmp = try TempDir()
        try tmp.file("Sources/CrashDemo/main.swift")
        let refs = CrashDetector.fileRefs(in: ["CrashDemo/main.swift:18: Fatal error: x"], projectRoot: tmp.path)
        XCTAssertEqual(refs.first?.relativePath, "Sources/CrashDemo/main.swift")
        XCTAssertEqual(refs.first?.line, 18)
    }

    func testResolvesLegacySwiftFormat() throws {
        let tmp = try TempDir()
        try tmp.file("Sources/App/Foo.swift")
        let refs = CrashDetector.fileRefs(
            in: ["Fatal error: Unexpectedly found nil: file App/Foo.swift, line 7"], projectRoot: tmp.path)
        XCTAssertEqual(refs.first, FileRef(relativePath: "Sources/App/Foo.swift", line: 7))
    }

    func testRejectsFilesOutsideTheProject() throws {
        let project = try TempDir()
        let other = try TempDir()
        let outside = try other.file("Secret.swift")
        let refs = CrashDetector.fileRefs(in: ["\(outside):3: Fatal error"], projectRoot: project.path)
        XCTAssertTrue(refs.isEmpty, "Must never pull in another project's files")
    }

    func testRejectsPathTraversal() throws {
        let tmp = try TempDir()
        let project = try tmp.dir("project")
        try tmp.file("other/Leak.swift")
        let refs = CrashDetector.fileRefs(in: ["../other/Leak.swift:1: Fatal error"], projectRoot: project)
        XCTAssertTrue(refs.isEmpty)
    }

    func testDeduplicatesRefs() throws {
        let tmp = try TempDir()
        let file = try tmp.file("a.swift")
        let refs = CrashDetector.fileRefs(in: ["\(file):1", "\(file):1", "\(file):2"], projectRoot: tmp.path)
        XCTAssertEqual(refs.count, 2)
    }
}

final class RedactorTests: XCTestCase {

    func testRedactsKnownKeyFormats() {
        // Assembled at runtime so no secret-shaped literal exists in the repo.
        let filler = String(repeating: "x7", count: 16)
        let samples = [
            "key=" + "sk-" + "ant-api03-" + filler,
            "OPENAI " + "sk-" + "proj-" + filler,
            "token " + "gh" + "p_" + filler,
            "aws " + "AK" + "IA" + "ABCDEFGHIJKLMNOP",
            "jwt " + "ey" + "J" + filler + "." + "ey" + "J" + filler + "." + filler,
            "Authorization: " + "Bearer " + filler,
            "password=" + "hunter2",
        ]
        for sample in samples {
            XCTAssertTrue(Redactor.redact(sample).contains("<REDACTED>"), "Not redacted: \(sample)")
        }
    }

    func testKeepsOrdinaryText() {
        let line = "Fatal error: Unexpectedly found nil at ProfileView.swift:87"
        XCTAssertEqual(Redactor.redact(line), line)
    }

    func testRedactsPrivateKeyBlock() {
        let marker = "PRIVATE " + "KEY-----"
        let pem = "-----BEGIN RSA " + marker + "\nMIIabc\n-----END RSA " + marker
        XCTAssertFalse(Redactor.redact(pem).contains("MIIabc"))
    }
}
