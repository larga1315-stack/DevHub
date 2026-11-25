import ShopCore

// Export from the store's back office. Note: names may contain commas (quoted), prices are in shekels.
let csv = """
id,name,price
1,"חלב, 3%",6.90
2,לחם אחיד,7.50
3,ביצים L (12),14.90
4,קפה טורקי,19
5,במבה,4.50

"""

print("ShopDemo: טוען קטלוג…")
let catalog = Catalog(CatalogParser.parse(csv))

var cart = Cart(catalog: catalog)
cart.add(1, quantity: 2)    // חלב
cart.add(2)                 // לחם
cart.add(3)                 // ביצים
cart.add(4)                 // קפה
cart.add(5, quantity: 40)   // במבה למסיבה

print("בדיקת מחיר חלב: \(ReceiptPrinter.format(catalog.price(for: 1)))")
print(ReceiptPrinter.receipt(for: cart, catalog: catalog))
print("✓ done")
