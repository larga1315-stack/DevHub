public enum PlanError: Error, Equatable {
    case unknownTask(String, requiredBy: String)
    /// The path of the cycle, first node repeated at the end, e.g. ["a", "b", "a"].
    case cycle([String])
}

public struct Scheduler {
    private let tasks: [String: BuildTask]

    public init(_ tasks: [BuildTask]) {
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.name, $0) })
    }

    /// Every task needed to build `target` (including itself).
    func reachable(from target: String) -> Set<String> {
        var result: Set<String> = [target]
        for dep in tasks[target]?.deps ?? [] {
            result.formUnion(reachable(from: dep))
        }
        return result
    }

    /// Execution order: a dependency always comes before its dependents; among ready tasks the
    /// highest priority goes first, ties broken by name (A→Z).
    public func plan(_ target: String) -> [String] {
        let needed = reachable(from: target)
        var remaining = needed
        var done: Set<String> = []
        var order: [String] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { name in
                (tasks[name]?.deps ?? []).allSatisfy { done.contains($0) }
            }
            guard let next = ready.max(by: { tasks[$0]!.priority < tasks[$1]!.priority }) else { break }
            order.append(next)
            done.insert(next)
            remaining.remove(next)
        }
        return order
    }

    /// Wall-clock seconds to build `target` with `workers` parallel workers.
    /// Tasks are assigned in `plan` order, each to the worker that becomes free first,
    /// starting no earlier than its last dependency finishes.
    public func makespan(_ target: String, workers: Int) -> Double {
        let order = plan(target)
        var finish: [String: Double] = [:]
        var workerFree = Array(repeating: 0.0, count: max(workers, 1))
        for name in order {
            let task = tasks[name]!
            let depsDone = task.deps.map { finish[$0] ?? 0 }.max() ?? 0
            let w = workerFree.indices.min(by: { workerFree[$0] < workerFree[$1] })!
            let start = max(depsDone, workerFree[w])
            finish[name] = start + task.duration
            workerFree[w] = start + task.duration
        }
        return finish.values.max() ?? 0
    }
}
