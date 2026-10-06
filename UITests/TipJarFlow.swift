import StoreKitTest
import XCTest

/// Opens the real tip jar against the local StoreKit catalog, saves a capture for the
/// IAP review screenshots, then completes one test purchase end to end.
final class TipJarFlow: XCTestCase {
    private var session: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: "/tmp/drop-shots", withIntermediateDirectories: true)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TipJar", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        session = nil
    }

    func testTipJarLoadsAndPurchases() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenTutorial", "YES"]
        app.launch()
        sleep(2)
        let gear = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        let f = gear.frame, w = app.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: (f.midX - w.minX) / w.width,
                                                      dy: (f.midY - w.minY) / w.height)).tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // The Form is lazy: the row only exists once scrolled into view.
        let support = app.buttons["settings.tipJar"]
        for _ in 0..<8 where !(support.exists && support.isHittable) { app.swipeUp() }
        XCTAssertTrue(support.isHittable)
        support.tap()

        let ids = ["small", "medium", "large", "grand", "patron"].map { "com.agraabhi.drop.tip.\($0)" }
        for id in ids {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 20), "\(id) must load from StoreKit")
        }
        XCTAssertTrue(app.buttons[ids[0]].label.contains("$3.00"))
        XCTAssertTrue(app.buttons[ids[4]].label.contains("$50.00"))
        sleep(1)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/drop-shots/06-tipjar.png"))

        app.buttons[ids[0]].tap()
        XCTAssertTrue(app.alerts["Thank you"].waitForExistence(timeout: 20), "A completed tip must thank the player")
        app.alerts["Thank you"].buttons["OK"].tap()
        // The footer sits below the last tip; in the iPad sheet it starts off-screen.
        let footer = app.staticTexts["One tip recorded on this device. Thank you."]
        for _ in 0..<4 where !footer.exists { app.swipeUp() }
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertEqual(session?.allTransactions().count, 1)
    }
}
