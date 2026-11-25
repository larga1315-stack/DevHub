/// A product in the catalog. Prices are stored in agorot (1 ₪ = 100 agorot) to avoid floating-point errors.
public struct Product: Equatable {
    public let id: Int
    public let name: String
    public let priceAgorot: Int

    public init(id: Int, name: String, priceAgorot: Int) {
        self.id = id
        self.name = name
        self.priceAgorot = priceAgorot
    }
}
