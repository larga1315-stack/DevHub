import XCTest
@testable import DevHubCore

final class ProjectDetectorTests: XCTestCase {

    func testFindsRootFromNestedFolder() throws {
        let tmp = try TempDir()
        try tmp.file("CrashDemo/Package.swift")
        let nested = try tmp.dir("CrashDemo/Sources/CrashDemo")
        XCTAssertEqual(ProjectDetector.findRoot(from: nested, home: tmp.path), tmp.path + "/CrashDemo")
    }

    func testRootIsItselfWhenAlreadyRoot() throws {
        let tmp = try TempDir()
        try tmp.file("App/.git/HEAD")
        let root = tmp.path + "/App"
        XCTAssertEqual(ProjectDetector.findRoot(from: root, home: tmp.path), root)
    }

    func testNeverReturnsHome() throws {
        let tmp = try TempDir()
        try tmp.file("Package.swift")             // marker directly in "home"
        let nested = try tmp.dir("Documents/notes")
        XCTAssertNil(ProjectDetector.findRoot(from: nested, home: tmp.path))
    }

    func testPicksNearestRoot() throws {
        let tmp = try TempDir()
        try tmp.file("DevHub/Package.swift")
        try tmp.file("DevHub/Demo/CrashDemo/Package.swift")
        let nested = try tmp.dir("DevHub/Demo/CrashDemo/Sources/CrashDemo")
        XCTAssertEqual(ProjectDetector.findRoot(from: nested, home: tmp.path),
                       tmp.path + "/DevHub/Demo/CrashDemo")
    }

    func testDetectsSwiftPackage() throws {
        let tmp = try TempDir()
        try tmp.file("Package.swift")
        let d = ProjectDetector.detect(at: tmp.path)
        XCTAssertEqual(d.kind, .swiftPackage)
        XCTAssertEqual(d.runCommand, "swift run")
        XCTAssertEqual(d.buildCommand, "swift build")
    }

    func testSwiftPackageWithTestsVerifiesWithSwiftTest() throws {
        let tmp = try TempDir()
        try tmp.file("Package.swift")
        try tmp.file("Tests/FooTests/FooTests.swift")
        XCTAssertEqual(ProjectDetector.detect(at: tmp.path).buildCommand, "swift test")
    }

    func testDetectsXcodeProjectWithQuotedNames() throws {
        let tmp = try TempDir()
        _ = try tmp.dir("My App.xcodeproj")
        let d = ProjectDetector.detect(at: tmp.path)
        XCTAssertEqual(d.kind, .xcode)
        XCTAssertTrue(d.buildCommand.contains("-project 'My App.xcodeproj'"))
        XCTAssertTrue(d.buildCommand.contains("-scheme 'My App'"))
        XCTAssertTrue(d.runCommand.hasPrefix(d.buildCommand + " && "))
    }

    func testPrefersWorkspaceOverProject() throws {
        let tmp = try TempDir()
        _ = try tmp.dir("App.xcodeproj")
        _ = try tmp.dir("App.xcworkspace")
        XCTAssertTrue(ProjectDetector.detect(at: tmp.path).buildCommand.contains("-workspace 'App.xcworkspace'"))
    }

    func testQuoteEscapesSingleQuotes() {
        XCTAssertEqual(ProjectDetector.quote("it's"), "'it'\\''s'")
    }
}
