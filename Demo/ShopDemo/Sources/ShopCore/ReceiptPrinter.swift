public enum ReceiptPrinter {
    public static func format(_ agorot: Int) -> String {
        let shekels = agorot / 100
        let rest = agorot % 100
        return "₪\(shekels).\(rest < 10 ? "0" : "")\(rest)"
    }

    public static func receipt(for cart: Cart, catalog: Catalog) -> String {
        var out = ["===== קבלה ====="]
        for line in cart.lines {
            let product = catalog.product(line.productID)
            let unit = format(catalog.price(for: line.productID))
            out.append("\(product.name)  x\(line.quantity)  @\(unit)  =  \(format(cart.total(for: line)))")
        }
        out.append("סכום ביניים: \(format(cart.subtotal))")
        out.append("מע״מ \(Cart.vatPercent)%: \(format(cart.vat))")
        out.append("לתשלום: \(format(cart.total))")
        return out.joined(separator: "\n")
    }
}
