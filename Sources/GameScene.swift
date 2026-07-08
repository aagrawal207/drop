import SpriteKit
import CoreMotion

private enum GameState {
    case menu
    case playing
    case paused
    case gameOver
}

private struct Category {
    static let ball: UInt32 = 0x1 << 0
    static let floor: UInt32 = 0x1 << 1
    static let wall: UInt32 = 0x1 << 2
}

/// The world is stationary — floors are genuinely static bodies — and a camera
/// descends over time. This makes the floors *appear* to rise while keeping the
/// physics correct: the ball is the only moving dynamic body, so it bounces off
/// solid floors properly and can never fall past the world (floors always exist
/// below it). Falling fast is safe; getting pinned to the top ends the game.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    /// Called when the player taps the settings gear on the menu.
    var onOpenSettings: (() -> Void)?
    /// Called when the player taps the leaderboard button.
    var onShowLeaderboard: (() -> Void)?
    /// Called with the final score when a game ends (for leaderboard submission).
    var onGameOver: ((Int) -> Void)?

    // Tunables — the "feel" knobs.
    private let ballRadius: CGFloat = 17
    private let floorHeight: CGFloat = 18
    private let floorSpacing: CGFloat = 180      // vertical gap between floors
    private let gapWidth: CGFloat = 82           // hole width
    private let baseCamSpeed: CGFloat = 95       // points/sec the camera descends
    private let maxCamSpeed: CGFloat = 400
    /// Difficulty ramps toward max speed with a fast-early, plateauing curve
    /// (see camSpeed(for:)) rather than a slow constant climb.
    private let rampTimeConstant: TimeInterval = 38   // seconds to ~63% of range
    private let ballMaxHSpeed: CGFloat = 340
    private let sideMargin: CGFloat = 6
    /// How far above the camera centre the ball ideally sits while falling.
    private let followBias: CGFloat = 0.14
    private let milestoneEvery = 10

    private var state: GameState = .menu

    private let cam = SKCameraNode()
    private let ball = SKNode()                  // physics container
    private let ballSprite = SKSpriteNode()      // rotates to look like rolling
    private let ballShadow = SKSpriteNode()      // world-aligned, doesn't rotate
    private var floors: [SKNode] = []
    private var lastGapCenterX: CGFloat = 0
    private var lowestFloorY: CGFloat = 0
    private var camSpeed: CGFloat = 120
    private var scriptedCamY: CGFloat = 0
    private var elapsed: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var lastLandHaptic: TimeInterval = 0
    /// Ball velocity sampled at the top of update(), i.e. BEFORE the physics
    /// solver runs. didBegin fires mid-step, by which point the solver has often
    /// already reflected the velocity — so we read the true incoming impact speed
    /// from here instead. Without this, bounce haptics fire only intermittently.
    private var preStepVelocity: CGVector = .zero

    private var score = 0
    /// Consecutive holes reached in a single bounce (a "clean" pass).
    private var cleanStreak = 0
    /// Floor bounces since the last hole was cleared. 0 = reached it in one drop.
    private var bouncesSinceGap = 0
    /// Clean passes needed before the escalating bonus kicks in.
    private let streakBonusThreshold = 3
    private var nextMilestone = 10
    private var highScore = UserDefaults.standard.integer(forKey: "highScore")

    // Controls
    private let motion = CMMotionManager()
    private var tiltX: CGFloat = 0
    private var touchDirection: CGFloat = 0

    // UI (parented to the camera so it stays fixed on screen)
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var overlay: SKNode?
    private var gearNode: SKLabelNode?
    private var leaderboardNode: SKLabelNode?
    private var pauseButton: SKLabelNode?

    // Cached procedural textures.
    private lazy var plankTexture = WoodTexture.plank(width: size.width, height: floorHeight)
    private lazy var ballTexture = BallTexture.glossyRed(radius: ballRadius)
    private lazy var shadowTexture = BallTexture.softShadow(radius: ballRadius)

    // Convenience: current visible top/bottom edges in world coordinates.
    private var viewTop: CGFloat { cam.position.y + size.height / 2 }
    private var viewBottom: CGFloat { cam.position.y - size.height / 2 }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -16)
        physicsWorld.contactDelegate = self

        camera = cam
        cam.position = CGPoint(x: size.width / 2, y: 0)
        addChild(cam)

        setupBackground()
        setupWalls()
        setupBall()
        setupScoreLabel()
        startMotion()
        HapticsManager.shared.prepare()

        showMenu()
    }

    // MARK: - Setup

    private func setupBackground() {
        let bg = SKSpriteNode(texture: WoodTexture.background(width: size.width, height: size.height))
        bg.size = size
        bg.zPosition = -100
        bg.position = .zero          // centred on the camera
        cam.addChild(bg)
    }

    private func setupWalls() {
        // Side walls, parented to the camera and spanning well beyond the view
        // so the ball stays contained wherever it is vertically.
        let halfW = size.width / 2
        let span = size.height
        for x in [-halfW, halfW] {
            let wall = SKNode()
            let body = SKPhysicsBody(edgeFrom: CGPoint(x: x, y: -span),
                                     to: CGPoint(x: x, y: span))
            body.categoryBitMask = Category.wall
            body.friction = 0
            body.restitution = 0.2
            wall.physicsBody = body
            cam.addChild(wall)
        }
    }

    private func setupBall() {
        // `ball` is an invisible physics container. Its children render the ball:
        // - ballSprite rotates to fake rolling and takes squash-and-stretch,
        // - ballShadow is counter-rotated to stay world-aligned beneath it.
        ball.zPosition = 5

        ballShadow.texture = shadowTexture
        ballShadow.size = CGSize(width: ballRadius * 2.4, height: ballRadius * 1.5)
        ballShadow.position = CGPoint(x: 1, y: -ballRadius * 0.75)
        ballShadow.zPosition = -1
        ballShadow.alpha = 0.9
        ball.addChild(ballShadow)

        ballSprite.texture = ballTexture
        ballSprite.size = CGSize(width: ballRadius * 2, height: ballRadius * 2)
        ball.addChild(ballSprite)

        let body = SKPhysicsBody(circleOfRadius: ballRadius)
        body.categoryBitMask = Category.ball
        body.collisionBitMask = Category.floor | Category.wall
        body.contactTestBitMask = Category.floor | Category.wall
        body.allowsRotation = false   // we drive the visual rotation ourselves
        body.friction = 0.3
        // Bounciness is player-tunable; the ball's restitution dominates the
        // collision (it's always above the floor's 0.3), so this drives the feel.
        body.restitution = CGFloat(GameSettings.shared.bounciness)
        body.linearDamping = 0.1
        body.mass = 0.4
        ball.physicsBody = body
        addChild(ball)
    }

    private func setupScoreLabel() {
        scoreLabel.fontSize = 44
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .top   // position is the text's top edge
        scoreLabel.zPosition = 10
        scoreLabel.text = "0"
        scoreLabel.isHidden = true
        cam.addChild(scoreLabel)
        positionScoreLabel()

        comboLabel.fontSize = 18
        comboLabel.fontColor = SKColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
        comboLabel.horizontalAlignmentMode = .center
        comboLabel.verticalAlignmentMode = .top
        comboLabel.zPosition = 10
        comboLabel.isHidden = true
        cam.addChild(comboLabel)
    }

    /// Place the score just below the safe-area top inset (clears Dynamic Island).
    /// Read at show-time because insets can be zero during didMove.
    private func positionScoreLabel() {
        let topInset = view?.safeAreaInsets.top ?? 59
        let inset = topInset > 0 ? topInset : 59
        scoreLabel.position = CGPoint(x: 0, y: size.height / 2 - inset - 12)
        comboLabel.position = CGPoint(x: 0, y: size.height / 2 - inset - 62)
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 60.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            self.tiltX = CGFloat(a.x)
        }
    }

    /// Difficulty curve: fast early, plateauing toward maxCamSpeed. An
    /// exponential approach means a beginner isn't bored at the start and an
    /// expert still hits a hard ceiling, without a slow linear grind between.
    private func camSpeed(for t: TimeInterval) -> CGFloat {
        let range = maxCamSpeed - baseCamSpeed
        let progress = 1 - exp(-t / rampTimeConstant)
        return baseCamSpeed + range * CGFloat(progress)
    }

    // MARK: - Floor generation

    private func makeFloor(atY y: CGFloat, gapCenterX: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: 0, y: y)

        let gapLeft = gapCenterX - gapWidth / 2
        let gapRight = gapCenterX + gapWidth / 2

        var bodies: [SKPhysicsBody] = []
        func segment(x: CGFloat, width: CGFloat) {
            guard width > 1 else { return }
            let seg = SKSpriteNode(texture: plankTexture)
            seg.size = CGSize(width: width, height: floorHeight)
            seg.position = CGPoint(x: x, y: 0)
            node.addChild(seg)
            let b = SKPhysicsBody(rectangleOf: seg.size, center: seg.position)
            b.isDynamic = false
            b.restitution = 0.3
            bodies.append(b)
        }
        segment(x: gapLeft / 2, width: gapLeft)
        segment(x: gapRight + (size.width - gapRight) / 2, width: size.width - gapRight)

        let body = SKPhysicsBody(bodies: bodies)
        body.isDynamic = false
        body.categoryBitMask = Category.floor
        body.friction = 0.3
        body.restitution = 0.3
        node.physicsBody = body
        node.userData = ["scored": false]
        return node
    }

    private func nextGapCenterX(from previous: CGFloat) -> CGFloat {
        // Keep the next gap reachable: bound the horizontal step.
        let maxStep = size.width * 0.34
        let low = max(gapWidth / 2 + sideMargin, previous - maxStep)
        let high = min(size.width - gapWidth / 2 - sideMargin, previous + maxStep)
        return CGFloat.random(in: low...high)
    }

    /// Ensure floors exist from just above the view down to below its bottom.
    private func fillFloorsBelow() {
        while lowestFloorY > viewBottom - floorSpacing {
            let gapX = nextGapCenterX(from: lastGapCenterX)
            let y = lowestFloorY - floorSpacing
            let floor = makeFloor(atY: y, gapCenterX: gapX)
            addChild(floor)
            floors.append(floor)
            lowestFloorY = y
            lastGapCenterX = gapX
        }
    }

    // MARK: - Game flow

    private func showMenu() {
        state = .menu
        scoreLabel.isHidden = true
        ball.physicsBody?.isDynamic = false
        ball.position = CGPoint(x: size.width / 2, y: cam.position.y + size.height * 0.12)

        let node = SKNode()
        node.zPosition = 20

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "DROP"
        title.fontSize = 64
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: size.height * 0.12)
        node.addChild(title)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        hint.text = "Tap to start"
        hint.fontSize = 22
        hint.fontColor = SKColor(white: 0.85, alpha: 1)
        hint.position = CGPoint(x: 0, y: 0)
        node.addChild(hint)

        let ctl = SKLabelNode(fontNamed: "AvenirNext-Regular")
        ctl.text = "Tilt or touch left / right to steer"
        ctl.fontSize = 16
        ctl.fontColor = SKColor(white: 0.7, alpha: 1)
        ctl.position = CGPoint(x: 0, y: -size.height * 0.06)
        node.addChild(ctl)

        if highScore > 0 {
            let hs = SKLabelNode(fontNamed: "AvenirNext-Medium")
            hs.text = "Best: \(highScore)"
            hs.fontSize = 20
            hs.fontColor = SKColor(red: 1.0, green: 0.5, blue: 0.42, alpha: 1)
            hs.position = CGPoint(x: 0, y: -size.height * 0.12)
            node.addChild(hs)
        }

        addGear(to: node)
        addLeaderboardButton(to: node)
        cam.addChild(node)
        overlay = node
    }

    /// Settings gear, top-right, clear of the safe-area inset.
    private func addGear(to node: SKNode) {
        let raw = view?.safeAreaInsets.top ?? 59
        let topInset = raw > 0 ? raw : 59
        let gear = SKLabelNode(fontNamed: "AvenirNext-Regular")
        gear.text = "⚙"
        gear.fontSize = 34
        gear.fontColor = SKColor(white: 0.85, alpha: 1)
        gear.verticalAlignmentMode = .center
        gear.position = CGPoint(x: size.width / 2 - 36, y: size.height / 2 - topInset - 16)
        gear.name = "gear"
        node.addChild(gear)
        gearNode = gear
    }

    /// Leaderboard button, top-left, mirroring the gear.
    private func addLeaderboardButton(to node: SKNode) {
        let raw = view?.safeAreaInsets.top ?? 59
        let topInset = raw > 0 ? raw : 59
        let lb = SKLabelNode(fontNamed: "AvenirNext-Regular")
        lb.text = "🏆"
        lb.fontSize = 30
        lb.verticalAlignmentMode = .center
        lb.horizontalAlignmentMode = .center
        lb.position = CGPoint(x: -size.width / 2 + 36, y: size.height / 2 - topInset - 16)
        lb.name = "leaderboard"
        node.addChild(lb)
        leaderboardNode = lb
    }

    /// If the tap hit the gear or leaderboard button, handle it and return true.
    private func handleButtonTap(_ touches: Set<UITouch>) -> Bool {
        guard let t = touches.first else { return false }
        let p = t.location(in: cam)
        if let gear = gearNode, gear.frame.insetBy(dx: -18, dy: -18).contains(p) {
            HapticsManager.shared.uiTap()
            onOpenSettings?()
            return true
        }
        if let lb = leaderboardNode, lb.frame.insetBy(dx: -18, dy: -18).contains(p) {
            HapticsManager.shared.uiTap()
            onShowLeaderboard?()
            return true
        }
        return false
    }

    private func startGame() {
        overlay?.removeFromParent()
        overlay = nil
        gearNode = nil
        leaderboardNode = nil
        state = .playing

        floors.forEach { $0.removeFromParent() }
        floors.removeAll()
        camSpeed = baseCamSpeed
        elapsed = 0
        score = 0
        cleanStreak = 0
        bouncesSinceGap = 0
        nextMilestone = milestoneEvery
        scoreLabel.text = "0"
        scoreLabel.isHidden = false
        comboLabel.isHidden = true
        positionScoreLabel()
        addPauseButton()

        // Reset the camera and lay down a starting floor beneath the ball.
        cam.position = CGPoint(x: size.width / 2, y: 0)
        scriptedCamY = 0
        lastGapCenterX = size.width / 2
        lowestFloorY = 0

        let firstY = -size.height * 0.10
        let first = makeFloor(atY: firstY, gapCenterX: size.width / 2)
        addChild(first)
        floors.append(first)
        lowestFloorY = firstY

        ball.position = CGPoint(x: size.width / 2, y: size.height * 0.18)
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.restitution = CGFloat(GameSettings.shared.bounciness)
        ball.physicsBody?.isDynamic = true

        fillFloorsBelow()
    }

    /// Small pause button, top-right during play (where the gear sits on menus).
    private func addPauseButton() {
        pauseButton?.removeFromParent()
        let raw = view?.safeAreaInsets.top ?? 59
        let topInset = raw > 0 ? raw : 59
        let btn = SKLabelNode(fontNamed: "AvenirNext-Bold")
        btn.text = "❚❚"
        btn.fontSize = 26
        btn.fontColor = SKColor(white: 0.9, alpha: 1)
        btn.verticalAlignmentMode = .center
        btn.horizontalAlignmentMode = .center
        btn.position = CGPoint(x: size.width / 2 - 36, y: size.height / 2 - topInset - 16)
        btn.name = "pause"
        btn.zPosition = 15
        cam.addChild(btn)
        pauseButton = btn
    }

    // MARK: - Pause

    func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        physicsWorld.speed = 0
        pauseButton?.isHidden = true

        let node = SKNode()
        node.zPosition = 20

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55), size: size)
        dim.zPosition = -1
        node.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "PAUSED"
        title.fontSize = 44
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: size.height * 0.06)
        node.addChild(title)

        let resume = SKLabelNode(fontNamed: "AvenirNext-Medium")
        resume.text = "Tap to resume"
        resume.fontSize = 22
        resume.fontColor = SKColor(red: 1.0, green: 0.5, blue: 0.42, alpha: 1)
        resume.position = CGPoint(x: 0, y: -size.height * 0.02)
        node.addChild(resume)

        // Settings gear on the pause screen, so players can tweak controls/sound
        // mid-run without ending the game.
        addGear(to: node)
        cam.addChild(node)
        overlay = node
    }

    func resumeGame() {
        guard state == .paused else { return }
        overlay?.removeFromParent()
        overlay = nil
        physicsWorld.speed = 1
        pauseButton?.isHidden = false
        state = .playing
        lastUpdate = 0   // avoid a huge dt spike on the first frame back
    }

    private func endGame() {
        guard state == .playing else { return }
        state = .gameOver
        ball.physicsBody?.isDynamic = false
        pauseButton?.removeFromParent()
        pauseButton = nil
        comboLabel.isHidden = true
        HapticsManager.shared.gameOver()
        onGameOver?(score)

        // Juice: screen shake + white flash.
        cam.run(.sequence([
            .move(by: CGVector(dx: -14, dy: 8), duration: 0.04),
            .move(by: CGVector(dx: 22, dy: -12), duration: 0.05),
            .move(by: CGVector(dx: -16, dy: 6), duration: 0.05),
            .move(by: CGVector(dx: 8, dy: -2), duration: 0.04),
        ]))
        let flash = SKSpriteNode(color: .white, size: size)
        flash.zPosition = 30
        flash.alpha = 0.7
        cam.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))

        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "highScore")
        }

        let node = SKNode()
        node.zPosition = 20

        let over = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        over.text = "GAME OVER"
        over.fontSize = 40
        over.fontColor = .white
        over.position = CGPoint(x: 0, y: size.height * 0.08)
        node.addChild(over)

        let sc = SKLabelNode(fontNamed: "AvenirNext-Bold")
        sc.text = "Score: \(score)   Best: \(highScore)"
        sc.fontSize = 22
        sc.fontColor = SKColor(white: 0.85, alpha: 1)
        sc.position = CGPoint(x: 0, y: 0)
        node.addChild(sc)

        let again = SKLabelNode(fontNamed: "AvenirNext-Medium")
        again.text = "Tap to play again"
        again.fontSize = 22
        again.fontColor = SKColor(red: 1.0, green: 0.5, blue: 0.42, alpha: 1)
        again.position = CGPoint(x: 0, y: -size.height * 0.06)
        node.addChild(again)

        addGear(to: node)
        addLeaderboardButton(to: node)
        cam.addChild(node)
        overlay = node
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch state {
        case .menu:
            // Gear / leaderboard taps handled first; anything else starts.
            if handleButtonTap(touches) { return }
            HapticsManager.shared.uiTap()
            startGame()
        case .gameOver:
            if handleButtonTap(touches) { return }
            HapticsManager.shared.uiTap()
            overlay?.removeFromParent()
            overlay = nil
            startGame()
        case .paused:
            // Gear opens settings; any other tap resumes.
            if handleButtonTap(touches) { return }
            resumeGame()
        case .playing:
            // Pause button tap, else steer.
            if let t = touches.first, let btn = pauseButton,
               btn.frame.insetBy(dx: -20, dy: -20).contains(t.location(in: cam)) {
                HapticsManager.shared.uiTap()
                pauseGame()
                return
            }
            updateTouchDirection(touches)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if state == .playing { updateTouchDirection(touches) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDirection = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDirection = 0
    }

    private func updateTouchDirection(_ touches: Set<UITouch>) {
        guard let t = touches.first else { return }
        let x = t.location(in: self).x
        touchDirection = x < size.width / 2 ? -1 : 1
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        dt = min(dt, 1.0 / 30.0)   // clamp to avoid physics hitches
        guard state == .playing else { return }

        // Sample the ball's velocity before the solver runs this frame; didBegin
        // uses it as the true incoming impact speed (see preStepVelocity).
        preStepVelocity = ball.physicsBody?.velocity ?? .zero

        elapsed += dt
        camSpeed = camSpeed(for: elapsed)

        // The camera descends at a steady, ever-increasing rate so the floors
        // scroll up consistently regardless of what the ball is doing — the
        // ball bounces within a steady frame rather than driving the scroll.
        scriptedCamY -= camSpeed * CGFloat(dt)

        // Emergency catch-down only: if the ball outruns the scroll and nears
        // the bottom edge, drop the camera to keep it on screen. Never rises,
        // so a bounce never jerks the whole view up.
        let bottomLimit = ball.position.y + size.height * (0.5 - followBias)
        if scriptedCamY > bottomLimit { scriptedCamY = bottomLimit }
        cam.position.y = scriptedCamY
    }

    override func didFinishUpdate() {
        guard state == .playing else { return }

        // Steering: touch overrides tilt. Applied after physics so it isn't
        // fighting the solver mid-step. Sensitivity scales the response.
        let sensitivity = CGFloat(GameSettings.shared.sensitivity)
        let desiredVX = (touchDirection != 0 ? touchDirection : tiltX) * ballMaxHSpeed * sensitivity
        if let body = ball.physicsBody {
            let newDX = body.velocity.dx + (desiredVX - body.velocity.dx) * 0.35
            body.velocity = CGVector(dx: newDX, dy: body.velocity.dy)
        }

        // Score: a floor counts once the ball has dropped below it.
        for floor in floors {
            if let scored = floor.userData?["scored"] as? Bool, !scored,
               ball.position.y < floor.position.y {
                floor.userData?["scored"] = true
                registerGapCleared(floor: floor)
            }
        }

        // Recycle floors that have risen above the view; extend below.
        floors.removeAll { floor in
            if floor.position.y > viewTop + floorHeight {
                floor.removeFromParent()
                return true
            }
            return false
        }
        fillFloorsBelow()

        // Game over: the ball has been pushed to the top of the screen.
        if ball.position.y + ballRadius >= viewTop - 4 {
            endGame()
        }
    }

    // MARK: - Scoring

    /// A hole was cleared. Always worth a base point. Reaching it in a single
    /// bounce (or less) extends the "clean streak"; from the 3rd clean pass in a
    /// row, each one adds an escalating bonus (+1, +2, +3, …) on top of the base.
    /// A messy pass (2+ bounces) resets the streak.
    private func registerGapCleared(floor: SKNode) {
        let clean = bouncesSinceGap <= 1
        var gained = 1                              // base point, always

        if clean {
            cleanStreak += 1
            if cleanStreak >= streakBonusThreshold {
                let bonus = cleanStreak - (streakBonusThreshold - 1)   // 1, 2, 3, …
                gained += bonus
            }
        } else {
            cleanStreak = 0
        }

        score += gained
        scoreLabel.text = "\(score)"
        bouncesSinceGap = 0                         // reset for the next hole

        // Combo readout, shown once the escalating bonus is live.
        if cleanStreak >= streakBonusThreshold {
            let bonus = cleanStreak - (streakBonusThreshold - 1)
            comboLabel.isHidden = false
            comboLabel.text = "STREAK ×\(cleanStreak)   +\(bonus)"
            comboLabel.removeAllActions()
            comboLabel.setScale(1.15)
            comboLabel.run(.scale(to: 1.0, duration: 0.15))
        } else {
            comboLabel.isHidden = true
        }

        // No haptic here — clearing a gap is a visual/scoring event, not a
        // physical contact. Haptics fire only when the ball actually hits
        // something (floor landings and wall smacks, in didBegin). Sound does
        // mark the score, though: it plays `gained` rising blips (+1/+2/+3) or a
        // single celebratory chime for a big jump (+4 or more).
        SoundManager.shared.score(gained: gained)

        if score >= nextMilestone {
            nextMilestone += milestoneEvery
            fireMilestone()
        }
    }

    /// Every 10 floors: a brief score-label pop and a colour pulse on the ball.
    private func fireMilestone() {
        scoreLabel.removeAllActions()
        scoreLabel.setScale(1.4)
        scoreLabel.run(.scale(to: 1.0, duration: 0.25))
        ballSprite.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.6, duration: 0.08),
            .colorize(withColorBlendFactor: 0, duration: 0.25),
        ]))
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard mask & Category.ball != 0 else { return }

        // Use the velocity sampled BEFORE the solver ran this frame — by the time
        // didBegin fires, the live velocity may already be reflected, which made
        // bounce haptics fire only intermittently.
        if mask & Category.wall != 0 {
            // Touching a wall breaks the clean streak.
            cleanStreak = 0
            comboLabel.isHidden = true
            // Thump on a real sideways smack into the wall, throttled.
            let vx = preStepVelocity.dx
            if abs(vx) > 60, lastUpdate - lastLandHaptic > 0.06 {
                lastLandHaptic = lastUpdate
                HapticsManager.shared.land(velocity: vx)
                SoundManager.shared.bounce(velocity: vx)
            }
            return
        }

        guard mask & Category.floor != 0 else { return }
        // Only thump on a real landing (downward impact), throttled.
        let vy = preStepVelocity.dy
        if vy < -40, lastUpdate - lastLandHaptic > 0.06 {
            lastLandHaptic = lastUpdate
            bouncesSinceGap += 1        // a real bounce before reaching the hole
            HapticsManager.shared.land(velocity: vy)
            SoundManager.shared.bounce(velocity: vy)
        }
    }
}
