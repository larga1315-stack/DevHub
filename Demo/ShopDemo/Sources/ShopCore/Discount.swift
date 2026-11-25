/// Bulk discount by quantity of the same product:
/// 0–4 → 0%, 5–9 → 5%, 10–19 → 10%, 20 or more → 15%.
public enum Discount {
    static let tiers = [0, 5, 10, 10, 15]

    public static func percent(forQuantity quantity: Int) -> Int {
        tiers[quantity / 5]
    }
}
