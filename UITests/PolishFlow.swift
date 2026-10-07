import XCTest

/// Acceptance for the 1.3 polish: a deep autopilot run (floor variety, milestones, ball
/// unlocks), the game-over notes, the best-drop marker on the next run, and skin selection.
final class PolishFlow: XCTestCase {
    private let outDir = "/tmp/drop-polish"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }

    func testDeepRunUnlocksBallAndMarksBestDrop() throws {
        let deep = Int(ProcessInfo.processInfo.environment["DROP_POLISH_UNTIL"] ?? "") ?? 260
        var app = launch(until: deep)
        save("01-menu")
        tap(app, element(app, "Play"))
        let shots = runUntilGameOver(app, prefix: "deep", every: 1.0)
        XCTAssertGreaterThan(shots, 5)
        sleep(1)
        save("02-gameover-deep")
        XCTAssertTrue(element(app, "New ball unlocked: Gold").exists
                      || element(app, "New ball unlocked: Basketball").exists,
                      "A 250+ run must announce its newest ball")

        // A short second run: the marker is in the world from the start and the notes compare.
        app.terminate()
        app = launch(until: 250)
        tap(app, element(app, "Play"))
        sleep(2)
        save("03-short-run-start")
        _ = runUntilGameOver(app, prefix: "short", every: 2.0)
        sleep(1)
        save("04-gameover-short")

        tap(app, element(app, "Main Menu"))
        sleep(1)
        let titleBall = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Ball: ")).firstMatch
        XCTAssertTrue(titleBall.waitForExistence(timeout: 5))
        let before = titleBall.label
        tap(app, titleBall)
        sleep(1)
        save("05-menu-ball-cycled")
        XCTAssertNotEqual(titleBall.label, before, "Tapping the title ball picks the next unlocked ball")
        XCTAssertTrue(element(app, "Play").exists, "Cycling the ball must not start a run")

        tap(app, element(app, "Settings"))
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let ball = app.staticTexts["Ball"]
        for _ in 0..<6 where !(ball.exists && ball.isHittable) { app.swipeUp() }
        app.swipeUp()
        sleep(1)
        save("06-settings-ball")
    }

    /// Autopilot never lets go, so the run reaches the deep floor types; frames are captured host-side.
    func testDeepVarietyRun() throws {
        let app = launch(until: 0)
        tap(app, element(app, "Play"))
        sleep(150)
        XCTAssertFalse(element(app, "Main Menu").exists, "Autopilot should survive the deep floor types")
        tap(app, element(app, "Pause"))
        XCTAssertTrue(element(app, "Main Menu").waitForExistence(timeout: 5))
        save("07-paused-deep")
    }

    private func launch(until: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenTutorial", "YES", "-uiTestAutopilot", "YES"]
            + (until > 0 ? ["-uiTestAutopilotUntil", "\(until)"] : [])
        app.launch()
        XCTAssertTrue(element(app, "Play").waitForExistence(timeout: 10))
        sleep(1)
        return app
    }

    private func runUntilGameOver(_ app: XCUIApplication, prefix: String, every: TimeInterval) -> Int {
        let menu = element(app, "Main Menu")
        let deadline = Date().addingTimeInterval(420)
        var i = 0
        while Date() < deadline, !menu.exists {
            save(String(format: "\(prefix)-%03d", i)); i += 1
            usleep(UInt32(every * 1_000_000))
        }
        XCTAssertTrue(menu.exists, "The run must end")
        return i
    }

    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ e: XCUIElement) {
        XCTAssertTrue(e.waitForExistence(timeout: 10), "Missing \(e)")
        let f = e.frame, w = app.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: (f.midX - w.minX) / w.width,
                                                      dy: (f.midY - w.minY) / w.height)).tap()
    }
}
