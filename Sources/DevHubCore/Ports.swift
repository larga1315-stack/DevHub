import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A TCP port some process is listening on.
public struct ListeningPort: Identifiable, Hashable {
    public var id: String { "\(pid)-\(port)" }
    public let pid: Int32
    public let command: String
    public let port: Int
    /// e.g. ["*", "127.0.0.1", "[::1]"]
    public let addresses: [String]
    public let user: String?

    /// Reachable only from this Mac.
    public var isLocalOnly: Bool {
        addresses.allSatisfy { $0 == "127.0.0.1" || $0 == "[::1]" || $0 == "localhost" }
    }

    public init(pid: Int32, command: String, port: Int, addresses: [String], user: String?) {
        self.pid = pid
        self.command = command
        self.port = port
        self.addresses = addresses
        self.user = user
    }
}

public enum PortScanner {
    public static var lsof = "/usr/sbin/lsof"

    /// Lists listening TCP ports of processes visible to the current user.
    public static func scan() async -> [ListeningPort] {
        // -F machine-readable output: p=pid c=command L=login n=name. -n/-P: no DNS/service lookups.
        let r = await Shell.run(lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLn"])
        return parse(r.stdout)
    }

    /// Parses `lsof -F pcLn` output. Merges IPv4/IPv6 entries of the same pid+port.
    public static func parse(_ output: String) -> [ListeningPort] {
        var pid: Int32?
        var command = ""
        var user: String?
        var merged: [String: (pid: Int32, command: String, port: Int, addresses: [String], user: String?)] = [:]
        var order: [String] = []

        for raw in output.split(separator: "\n") {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
                user = nil
            case "c":
                command = value
            case "L":
                user = value
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                let key = "\(pid)-\(port)"
                if var existing = merged[key] {
                    if !existing.addresses.contains(address) { existing.addresses.append(address) }
                    merged[key] = existing
                } else {
                    merged[key] = (pid, command, port, [address], user)
                    order.append(key)
                }
            default:
                continue
            }
        }
        return order.compactMap { merged[$0] }
            .map { ListeningPort(pid: $0.pid, command: $0.command, port: $0.port, addresses: $0.addresses, user: $0.user) }
            .sorted { $0.port < $1.port }
    }

    /// The working directory of a process (to match it to a project).
    public static func workingDirectory(of pid: Int32) async -> String? {
        let r = await Shell.run(lsof, ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        return r.stdout.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }
}

public enum ProcessControl {
    public enum KillError: LocalizedError, Equatable {
        case protectedProcess, notOwned, failed(Int32)
        public var errorDescription: String? {
            switch self {
            case .protectedProcess: return "זה תהליך מערכת. DevHub לא עוצר תהליכים כאלה."
            case .notOwned: return "התהליך שייך למשתמש אחר."
            case .failed(let code): return "העצירה נכשלה (errno \(code))."
            }
        }
    }

    /// Sends SIGTERM (or SIGKILL when `force`). Refuses low PIDs, DevHub itself, and other users' processes.
    public static func terminate(pid: Int32, owner: String?, force: Bool = false,
                                 currentUser: String = NSUserName()) throws {
        guard pid > 100, pid != getpid() else { throw KillError.protectedProcess }
        if let owner, owner != currentUser { throw KillError.notOwned }
        if kill(pid, force ? SIGKILL : SIGTERM) != 0 { throw KillError.failed(errno) }
    }
}

/// CPU / memory for a process tree.
public struct ProcessUsage: Equatable {
    public var cpuPercent: Double
    public var residentBytes: Int64
    public var processCount: Int

    public init(cpuPercent: Double = 0, residentBytes: Int64 = 0, processCount: Int = 0) {
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.processCount = processCount
    }
}

public enum ProcessStats {
    public struct Entry: Equatable {
        public let pid: Int32
        public let ppid: Int32
        public let cpu: Double
        public let rssKB: Int64
    }

    /// One `ps` call for all processes.
    public static func snapshot() async -> [Entry] {
        let r = await Shell.run("/bin/ps", ["-axo", "pid=,ppid=,%cpu=,rss="])
        return parse(r.stdout)
    }

    public static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 4, let pid = Int32(f[0]), let ppid = Int32(f[1]),
                  let cpu = Double(f[2].replacingOccurrences(of: ",", with: ".")), let rss = Int64(f[3]) else { return nil }
            return Entry(pid: pid, ppid: ppid, cpu: cpu, rssKB: rss)
        }
    }

    /// Sums usage of `root` and all its descendants.
    public static func usage(ofTree root: Int32, in entries: [Entry]) -> ProcessUsage {
        var children: [Int32: [Entry]] = [:]
        var byPID: [Int32: Entry] = [:]
        for e in entries {
            children[e.ppid, default: []].append(e)
            byPID[e.pid] = e
        }
        var total = ProcessUsage()
        var stack = [root]
        var seen = Set<Int32>()
        while let pid = stack.popLast(), seen.insert(pid).inserted {
            if let e = byPID[pid] {
                total.cpuPercent += e.cpu
                total.residentBytes += e.rssKB * 1024
                total.processCount += 1
            }
            stack.append(contentsOf: (children[pid] ?? []).map(\.pid))
        }
        return total
    }

    /// All PIDs in a process tree (to tell which listening ports belong to a running project).
    public static func descendants(of root: Int32, in entries: [Entry]) -> Set<Int32> {
        var children: [Int32: [Int32]] = [:]
        for e in entries { children[e.ppid, default: []].append(e.pid) }
        var result = Set<Int32>()
        var stack = [root]
        while let pid = stack.popLast(), result.insert(pid).inserted {
            stack.append(contentsOf: children[pid] ?? [])
        }
        return result
    }
}
