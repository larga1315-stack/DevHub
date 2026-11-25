public struct Cart {
    public static let vatPercent = 18

    public struct Line: Equatable {
        public let productID: Int
        public let quantity: Int
    }

    private let catalog: Catalog
    public private(set) var lines: [Line] = []

    public init(catalog: Catalog) { self.catalog = catalog }

    public mutating func add(_ productID: Int, quantity: Int = 1) {
        lines.append(Line(productID: productID, quantity: quantity))
    }

    /// Line total in agorot after the bulk discount.
    public func total(for line: Line) -> Int {
        let gross = catalog.price(for: line.productID) * line.quantity
        let off = gross * Discount.percent(forQuantity: line.quantity) / 100
        return gross - off
    }

    public var subtotal: Int { lines.reduce(0) { $0 + total(for: $1) } }

    /// VAT rounded to the nearest agora.
    public var vat: Int { (subtotal * Cart.vatPercent + 50) / 100 }

    public var total: Int { subtotal + vat }
}
