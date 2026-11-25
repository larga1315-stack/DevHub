/// Cache key for a task: 64-bit FNV-1a over the UTF-8 bytes of the signature.
/// Must be identical across runs and machines — it names files in the shared build cache.
/// Spec: offset basis 0xcbf29ce484222325, prime 0x100000001b3.
public enum Fingerprint {
    static let offsetBasis = -3_750_763_034_362_895_579   // 0xcbf29ce484222325 as a signed Int
    static let prime = 1_099_511_628_211                  // 0x100000001b3

    public static func of(_ text: String) -> UInt64 {
        var hash = offsetBasis
        for byte in text.utf8 {
            hash ^= Int(byte)
            hash *= prime
        }
        return UInt64(bitPattern: Int64(hash))
    }

    public static func hex(_ text: String) -> String {
        let digits = String(of(text), radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
