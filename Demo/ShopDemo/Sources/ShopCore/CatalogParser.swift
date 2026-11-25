/// Parses the store's CSV export: `id,name,price` with a header row.
/// Prices come in shekels, e.g. `6.90` or `19`.
public enum CatalogParser {
    public static func parse(_ csv: String) -> [Product] {
        csv.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()                                    // header
            .map { line in
                let fields = line.split(separator: ",").map(String.init)
                let id = Int(fields[0])!
                let name = fields[1]
                let shekels = Int(fields[2])!
                return Product(id: id, name: name, priceAgorot: shekels * 100)
            }
    }
}
