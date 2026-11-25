// Lets DevHubCore compile and run its tests on Linux CI, where Combine is unavailable.
// On macOS the real Combine types are used.
#if canImport(Combine)
@_exported import Combine
#else
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
