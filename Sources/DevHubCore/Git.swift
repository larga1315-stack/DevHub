import Foundation

/// A restore point taken before Claude touches anything.
public struct GitSnapshot {
    public let commit: String
    public let untrackedBefore: Set<String>
}

public enum GitState: Equatable {
    case notRepo, noCommits, ready
}

public enum GitError: LocalizedError, Equatable {
    case notARepo
    case noCommits
    case failed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .notARepo: return "התיקייה היא לא git repository."
        case .noCommits: return "ל-repository אין עדיין commit."
        case .failed(let command, _): return "הפקודה git \(command) נכשלה."
        }
    }

    /// Raw git output for the "details" view.
    public var details: String? {
        if case .failed(_, let output) = self { return output }
        return nil
    }
}

public enum Git {
    public static var executable = "/usr/bin/git"

    @discardableResult
    static func git(_ args: [String], in dir: String) async -> ShellResult {
        await Shell.run(executable, args, cwd: dir)
    }

    public static func state(in dir: String) async -> GitState {
        guard (await git(["rev-parse", "--is-inside-work-tree"], in: dir)).ok else { return .notRepo }
        guard (await git(["rev-parse", "--verify", "HEAD"], in: dir)).ok else { return .noCommits }
        return .ready
    }

    public static let defaultGitignore = """
    # Added by DevHub
    .DS_Store
    .build/
    .swiftpm/
    build/
    DerivedData/
    .devhub-build/
    xcuserdata/
    *.xcuserstate
    node_modules/
    # Secrets — never commit these
    .env
    .env.*
    *.pem
    *.p12
    *.key

    """

    /// Turns a folder into a repository with a first commit, so DevHub can take snapshots.
    /// Writes a .gitignore first (if none exists) so build output and secret files aren't committed.
    /// Returns a note for the user when a fallback identity had to be used.
    @discardableResult
    public static func initialize(in dir: String) async throws -> String? {
        let current = await state(in: dir)
        if current == .ready { return nil }

        if current == .notRepo {
            let r = await git(["init"], in: dir)
            if !r.ok { throw GitError.failed(command: "init", output: r.combined) }
        }

        let ignoreURL = URL(fileURLWithPath: dir).appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignoreURL.path) {
            try? defaultGitignore.write(to: ignoreURL, atomically: true, encoding: .utf8)
        }

        let add = await git(["add", "-A"], in: dir)
        if !add.ok { throw GitError.failed(command: "add", output: add.combined) }

        let message = "Initial commit (DevHub)"
        var commit = await git(["commit", "-m", message], in: dir)
        var note: String?
        if !commit.ok, commit.combined.contains("user.email") || commit.combined.contains("who you are") {
            // No git identity configured: commit once with a local placeholder identity.
            commit = await git(["-c", "user.name=DevHub", "-c", "user.email=devhub@localhost",
                                "commit", "-m", message], in: dir)
            note = "לא הוגדרו ב-git שם ואימייל, אז ה-commit הראשון נרשם בשם DevHub. "
                + "כדאי להריץ: git config --global user.name \"השם שלך\""
        }
        if !commit.ok { throw GitError.failed(command: "commit", output: commit.combined) }
        return note
    }

    /// Captures the current working tree (tracked files, including uncommitted edits)
    /// without modifying it, using `git stash create`.
    public static func snapshot(in dir: String) async throws -> GitSnapshot {
        switch await state(in: dir) {
        case .notRepo: throw GitError.notARepo
        case .noCommits: throw GitError.noCommits
        case .ready: break
        }

        let head = await git(["rev-parse", "HEAD"], in: dir)
        let stash = await git(["stash", "create", "devhub-snapshot"], in: dir)
        if !stash.ok { throw GitError.failed(command: "stash create", output: stash.combined) }

        let stashHash = stash.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = stashHash.isEmpty ? head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : stashHash

        // Keep the stash object reachable so `git gc` can't drop it.
        if !stashHash.isEmpty {
            await git(["stash", "store", "-m", "devhub-snapshot", stashHash], in: dir)
        }
        return GitSnapshot(commit: commit, untrackedBefore: await untracked(in: dir))
    }

    public static func untracked(in dir: String) async -> Set<String> {
        let r = await git(["ls-files", "--others", "--exclude-standard"], in: dir)
        return Set(r.stdout.split(separator: "\n").map(String.init))
    }

    /// Diff between the snapshot and the working tree, plus newly created files.
    public static func diff(since snap: GitSnapshot, in dir: String) async -> (diff: String, newFiles: [String]) {
        let d = await git(["diff", "--no-color", snap.commit, "--"], in: dir)
        let newFiles = (await untracked(in: dir)).subtracting(snap.untrackedBefore).sorted()
        var text = d.stdout
        for file in newFiles {
            // --no-index exits 1 when files differ; output is still valid.
            let nd = await git(["diff", "--no-color", "--no-index", "/dev/null", file], in: dir)
            text += nd.stdout
        }
        return (text, newFiles)
    }

    /// Puts tracked files back exactly as they were in the snapshot.
    /// New files are reported, not deleted — user files are never removed silently.
    public static func restore(_ snap: GitSnapshot, in dir: String) async throws {
        let r = await git(["restore", "--source=\(snap.commit)", "--worktree", "--", "."], in: dir)
        if !r.ok { throw GitError.failed(command: "restore", output: r.combined) }
    }
}
