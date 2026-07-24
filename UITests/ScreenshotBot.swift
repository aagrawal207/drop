import XCTest

/// Screenshot driver, not a real test suite. Plays the game with a tiny
/// pixel-reading bot and dumps device-resolution frames to /tmp/drop-shots
/// (simulator processes share the Mac filesystem). Frames are picked over
/// manually for the App Store listing afterwards.
final class ScreenshotBot: XCTestCase {

    let outDir = "/tmp/drop-shots"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(
            atPath: outDir, withIntermediateDirectories: true)
    }

    // MARK: - Frame analysis

    struct Frame {
        let width: Int
        let height: Int
        let pixels: [UInt8]   // RGBA8888

        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }

        /// The glossy ball reads as saturated red: strong R, weak G/B.
        func isBall(_ x: Int, _ y: Int) -> Bool {
            let p = rgb(x, y)
            return p.r > 150 && p.g < 90 && p.b < 90
        }

        /// Planks are light tan; background is dark brown. Brightness splits them.
        func isPlank(_ x: Int, _ y: Int) -> Bool {
            let p = rgb(x, y)
            return p.r > 130 && p.g > 90 && p.b > 55 && !isBall(x, y)
        }
    }

    func grab(_ app: XCUIApplication) -> Frame? {
        let shot = XCUIScreen.main.screenshot()
        guard let cg = shot.image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(width: w, height: h, pixels: data)
    }

    func save(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    /// Ball centroid, scanning a subsampled grid. Returns pixel coordinates.
    func findBall(_ f: Frame) -> (x: Int, y: Int)? {
        var sx = 0, sy = 0, n = 0
        stride(from: 0, to: f.height, by: 6).forEach { y in
            stride(from: 0, to: f.width, by: 6).forEach { x in
                if f.isBall(x, y) { sx += x; sy += y; n += 1 }
            }
        }
        return n >= 4 ? (sx / n, sy / n) : nil
    }

    /// Center X of the gap in the first floor row below `belowY`, or nil.
    func findGap(_ f: Frame, belowY: Int) -> Int? {
        var y = belowY + 30
        while y < f.height - 10 {
            // A floor row has plank pixels; find one.
            var plankCount = 0
            stride(from: 0, to: f.width, by: 8).forEach { x in
                if f.isPlank(x, y) { plankCount += 1 }
            }
            if plankCount > 20 {
                // Scan this row for the widest run of non-plank (the gap).
                var bestStart = -1, bestLen = 0, runStart = -1, x = 0
                while x < f.width {
                    let plank = f.isPlank(x, y)
                    if !plank && runStart < 0 { runStart = x }
                    if (plank || x == f.width - 1), runStart >= 0 {
                        let len = x - runStart
                        if len > bestLen { bestLen = len; bestStart = runStart }
                        runStart = -1
                    }
                    x += 4
                }
                // The gap is ~82pt wide (~250px). Edge-of-screen runs from the
                // wall side also match; require a plausible width.
                if bestLen > 120 && bestLen < 700 {
                    return bestStart + bestLen / 2
                }
                y += 60   // past this floor, keep looking (row may be occluded)
            }
            y += 8
        }
        return nil
    }

    // MARK: - The bot

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)

        // 1. Menu.
        save("01-menu")

        // 2. Start a ranked run: tap the PLAY pill (center, 8pt above middle).
        let play = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
        play.tap()
        sleep(1)

        // 3. Play with the pixel bot, dumping frames as we go. Steering: hold
        //    a finger on the half of the screen toward the gap for a beat.
        let deadline = Date().addingTimeInterval(75)
        var frameIdx = 0
        while Date() < deadline {
            guard let f = grab(app) else { break }
            guard let ball = findBall(f) else {
                // No ball found: likely game over (flash/overlay). Stop.
                break
            }
            save(String(format: "frame-%03d", frameIdx))
            frameIdx += 1

            if let gapX = findGap(f, belowY: ball.y) {
                let dx = gapX - ball.x
                if abs(dx) > 40 {
                    let sideX: CGFloat = dx < 0 ? 0.15 : 0.85
                    // Short press so we re-evaluate frequently; sensitivity is
                    // high by default and long holds slam the ball into walls.
                    app.coordinate(withNormalizedOffset: CGVector(dx: sideX, dy: 0.75))
                        .press(forDuration: 0.12)
                }
            }
            usleep(120_000)
        }

        // 4. Whatever screen we're on now (often game over) is worth keeping.
        sleep(1)
        save("99-final")
    }

    /// Separate capture for the settings sheet, reachable from the menu gear.
    func testCaptureSettings() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        // Gear sits top-right (36pt from the right edge, below the safe area).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.078)).tap()
        sleep(2)
        save("04-settings")
    }

    /// Captures the menu -> play transition frames, to verify the run starts
    /// with the title's own ball (the O of DROP) dropping in place.
    func testCaptureStartTransition() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        save("t0-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49)).tap()
        for i in 1...5 {
            save(String(format: "t%d-start", i))
            usleep(150_000)
        }
    }
}
