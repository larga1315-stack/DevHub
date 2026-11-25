public struct Catalog {
    private let products: [Int: Product]

    public init(_ products: [Product]) {
        self.products = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    public func product(_ id: Int) -> Product {
        products[id]!
    }

    /// Unit price in agorot. Used by Cart, ReceiptPrinter and the app's price check.
    public func price(for id: Int) -> Int {
        product(id).priceAgorot
    }
}
