import XCTest
@testable import ShopCore

/// The spec. A correct fix makes all of these pass without editing this file.
final class CatalogParserTests: XCTestCase {
    func testParsesDecimalShekelsToAgorot() {
        let products = CatalogParser.parse("id,name,price\n2,לחם,7.50\n")
        XCTAssertEqual(products, [Product(id: 2, name: "לחם", priceAgorot: 750)])
    }

    func testParsesWholeShekels() {
        XCTAssertEqual(CatalogParser.parse("id,name,price\n4,קפה,19").first?.priceAgorot, 1900)
    }

    func testKeepsCommasInsideQuotedNames() {
        let p = CatalogParser.parse("id,name,price\n1,\"חלב, 3%\",6.90").first
        XCTAssertEqual(p?.name, "חלב, 3%")
        XCTAssertEqual(p?.priceAgorot, 690)
    }

    func testSkipsBlankLinesAndHandlesWindowsLineEndings() {
        let csv = "id,name,price\r\n1,א,1.00\r\n\r\n2,ב,2.50\r\n"
        XCTAssertEqual(CatalogParser.parse(csv).map(\.priceAgorot), [100, 250])
    }

    func testPriceWithOneDecimalDigit() {
        XCTAssertEqual(CatalogParser.parse("id,name,price\n9,x,4.5").first?.priceAgorot, 450)
    }
}

final class DiscountTests: XCTestCase {
    func testTiers() {
        XCTAssertEqual(Discount.percent(forQuantity: 0), 0)
        XCTAssertEqual(Discount.percent(forQuantity: 4), 0)
        XCTAssertEqual(Discount.percent(forQuantity: 5), 5)
        XCTAssertEqual(Discount.percent(forQuantity: 12), 10)
        XCTAssertEqual(Discount.percent(forQuantity: 20), 15)
    }

    func testLargeQuantitiesKeepTopTier() {
        XCTAssertEqual(Discount.percent(forQuantity: 25), 15)
        XCTAssertEqual(Discount.percent(forQuantity: 400), 15)
    }
}

final class CartTests: XCTestCase {
    func testEndToEndReceiptTotal() {
        let csv = """
        id,name,price
        1,"חלב, 3%",6.90
        2,לחם אחיד,7.50
        3,ביצים L (12),14.90
        4,קפה טורקי,19
        5,במבה,4.50

        """
        let catalog = Catalog(CatalogParser.parse(csv))
        var cart = Cart(catalog: catalog)
        cart.add(1, quantity: 2)
        cart.add(2)
        cart.add(3)
        cart.add(4)
        cart.add(5, quantity: 40)

        XCTAssertEqual(cart.subtotal, 20_820)   // 13.80 + 7.50 + 14.90 + 19.00 + 153.00
        XCTAssertEqual(cart.vat, 3_748)
        XCTAssertEqual(cart.total, 24_568)
        XCTAssertEqual(ReceiptPrinter.format(cart.total), "₪245.68")
    }

    func testPriceLookupStillReturnsAgorot() {
        let catalog = Catalog([Product(id: 1, name: "x", priceAgorot: 690)])
        let price: Int = catalog.price(for: 1)
        XCTAssertEqual(price, 690)
    }
}
