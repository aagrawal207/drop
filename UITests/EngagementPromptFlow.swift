import XCTest

/// The quiet tip line on the game-over screen: absent for a new player, and when
/// forced on it opens the tip jar and returns to the same game-over screen.
final class EngagementPromptFlow: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: "/tmp/drop-shots", withIntermediateDirectories: true)
    }

    func testNewPlayerSeesNoTipLine() throws {
        let app = launch(extra: [])
        playUntilGameOver(app)
        sleep(2)   // past the line's fade-in delay
        XCTAssertFalse(element(app, "Leave a tip").exists, "A first run must not ask for anything")
    }

    func testTipLineOpensTipJarAndReturns() throws {
        let app = launch(extra: ["-engagementForce", "tip"])
        playUntilGameOver(app)
        let line = element(app, "Leave a tip")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        sleep(2)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/drop-shots/engagement-tipline.png"))

        tap(app, line)
        XCTAssertTrue(app.navigationBars["Support Development"].waitForExistence(timeout: 5))
        app.buttons["tipJar.done"].tap()
        XCTAssertTrue(element(app, "Main Menu").waitForExistence(timeout: 5), "Dismissing returns to game over")
        XCTAssertTrue(element(app, "Leave a tip").exists)
    }

    private func launch(extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenTutorial", "YES"] + extra
        app.launch()
        return app
    }

    /// With no tilt input the ball rides a floor up until it is pushed off the top.
    private func playUntilGameOver(_ app: XCUIApplication) {
        let play = element(app, "Play")
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        sleep(1)
        tap(app, play)
        XCTAssertTrue(element(app, "Main Menu").waitForExistence(timeout: 90), "The run must end")
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Scene nodes are accessibility elements without native tap support.
    private func tap(_ app: XCUIApplication, _ e: XCUIElement) {
        let f = e.frame, w = app.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: (f.midX - w.minX) / w.width,
                                                      dy: (f.midY - w.minY) / w.height)).tap()
    }
}
