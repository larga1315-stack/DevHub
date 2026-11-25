/// A unit of work in the build graph.
public struct BuildTask: Equatable {
    public let name: String
    /// Estimated duration in seconds.
    public let duration: Double
    /// Higher runs first when several tasks are ready.
    public let priority: Int
    public let deps: [String]

    public init(name: String, duration: Double, priority: Int, deps: [String]) {
        self.name = name
        self.duration = duration
        self.priority = priority
        self.deps = deps
    }

    /// Stable text used for the cache key.
    public var signature: String {
        "\(name)|\(duration)|\(priority)|\(deps.joined(separator: ","))"
    }
}
