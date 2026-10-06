import XCTest

/// Raw frames for the App Store screenshots, on whatever simulator runs it. The Debug
/// autopilot plays real runs (streaks, ball tiers, a game over) without accelerometer input.
final class StoreShots: XCTestCase {
    let outDir = "/tmp/drop-store"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }

    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    private func tapScene(_ label: String, in app: XCUIApplication) {
        let el = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 10), "Missing scene button: \(label)")
        let f = el.frame, w = app.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: (f.midX - w.minX) / w.width,
                                                      dy: (f.midY - w.minY) / w.height)).tap()
    }

    /// Plays to `until`, saving a frame every 0.4 s, then waits for the game-over card.
    func testCaptureRun() throws {
        let app = XCUIApplication()
        let until = Int(ProcessInfo.processInfo.environment["DROP_SHOT_UNTIL"] ?? "") ?? 180
        app.launchArguments = ["-hasSeenTutorial", "YES", "-uiTestAutopilot", "YES",
                               "-uiTestAutopilotUntil", "\(until)"]
        app.launch()
        sleep(2)
        save("menu")
        tapScene("Play", in: app)
        let mainMenu = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Main Menu")).firstMatch
        let deadline = Date().addingTimeInterval(240)
        var i = 0
        while Date() < deadline, !mainMenu.exists {
            save(String(format: "run-%03d", i)); i += 1
            usleep(400_000)
        }
        sleep(1)
        save("gameover")
        // The menu again, now showing the run's best score.
        tapScene("Main Menu", in: app)
        sleep(2)
        save("menu-best")
    }

    /// iPad only: rotates through every orientation mid-run and returns to portrait.
    func testRotationMidRun() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad rotates; iPhone is portrait-only")
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenTutorial", "YES", "-uiTestAutopilot", "YES"]
        app.launch()
        sleep(2)
        tapScene("Play", in: app)
        sleep(2)
        for (name, o) in [("landscapeLeft", UIDeviceOrientation.landscapeLeft), ("upsideDown", .portraitUpsideDown),
                          ("landscapeRight", .landscapeRight), ("portrait", .portrait)] {
            XCUIDevice.shared.orientation = o
            sleep(3)
            XCTAssertEqual(app.state, .runningForeground)
            save("rotate-\(name)")
        }
        tapScene("Pause", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        save("rotate-paused-landscape")
        tapScene("Settings", in: app)
        sleep(2)
        save("rotate-settings-landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}
