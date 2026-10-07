import SpriteKit
import CoreMotion

private enum GameState {
    case menu
    case tutorial
    case playing
    case paused
    case gameOver
}

private enum GameMode {
    case ranked   // Normal: ramping speed, feeds the Game Center leaderboard.
    case zen      // Relaxed: player-chosen speed with a glacial ramp, own local best.
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
    /// Called once per finished run, before its overlay is built. Returning true
    /// adds the quiet tip line to that game-over screen.
    var onRunFinished: ((RunSummary) -> Bool)?
    /// Called when the player taps the tip line.
    var onOpenTipJar: (() -> Void)?

    /// The review sheet only appears over a settled game-over screen, never mid-run.
    var isShowingGameOver: Bool { state == .gameOver }

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
    /// Tuned for iPhone widths (up to 440pt). The wider iPad field scales it so a
    /// gap-to-gap traverse takes the same time.
    private var ballMaxHSpeed: CGFloat { 340 * max(1, size.width / 440) }
    private let sideMargin: CGFloat = 6
    /// How far above the camera centre the ball ideally sits while falling.
    private let followBias: CGFloat = 0.14
    private let milestoneEvery = 10

    private var state: GameState = .menu {
        didSet {
            // Keep the screen awake only while actively playing. Steering is
            // tilt-only, so nobody touches the screen mid-run; without this the idle timer
            // dims and locks the device mid-run. Re-enabled on menu/pause/gameOver
            // so the phone still sleeps normally when not in a live game.
            UIApplication.shared.isIdleTimerDisabled = (state == .playing)
        }
    }

    private let cam = SKCameraNode()
    private let ball = SKNode()                  // physics container
    private let ballSprite = SKSpriteNode()      // glossy sphere (never rotates)
    private let ballShadow = SKSpriteNode()      // soft blob beneath for grounding
    private var floors: [SKNode] = []
    /// Rebuilt each run in startGame; the placeholder never generates a floor.
    private var floorPattern = FloorPatternGenerator(fieldWidth: 0, schedule: .ranked, firstGapX: 0)
    private var floorRandom = SystemRandomNumberGenerator()
    private var lowestFloorY: CGFloat = 0
    private var camSpeed: CGFloat = 120
    private var scriptedCamY: CGFloat = 0
    /// X of the title's O-slot (where the menu ball sits), relative to screen
    /// center. Runs start the ball here so it drops straight out of the word.
    private var titleBallOffsetX: CGFloat = 0
    private var elapsed: TimeInterval = 0
    /// Seconds of this run already flushed into totalTimePlayed. Banking happens
    /// at pause and at game over (delta-based, so it never double-counts).
    /// Banking at pause matters: quitting via pause -> Main Menu, or the OS
    /// killing a backgrounded (auto-paused) app, used to drop the whole run's
    /// time because it was only ever added in endGame. We can't just zero
    /// `elapsed` when banking — it also drives the ranked difficulty ramp.
    private var bankedPlaytime: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var lastLandHaptic: TimeInterval = 0
    /// Ball velocity sampled at the top of update(), i.e. BEFORE the physics
    /// solver runs. didBegin fires mid-step, by which point the solver has often
    /// already reflected the velocity — so we read the true incoming impact speed
    /// from here instead. Without this, bounce haptics fire only intermittently.
    private var preStepVelocity: CGVector = .zero

    private var mode: GameMode = .ranked
    private var score = 0
    /// Consecutive holes reached in a single bounce (a "clean" pass).
    private var cleanStreak = 0
    /// Longest clean streak reached this run (for the streak achievements).
    private var bestStreakThisRun = 0
    /// Floor bounces since the last hole was cleared. 0 = reached it in one drop.
    private var bouncesSinceGap = 0
    /// Clean passes needed before the escalating bonus kicks in.
    private let streakBonusThreshold = 3
    private var nextMilestone = 10
    /// Ball colour tier currently shown (see BallPalette); reset each run.
    private var ballTier = 0

    /// The high score for the active mode (ranked feeds Game Center; zen is local).
    private var highScore: Int {
        get { mode == .zen ? GameSettings.shared.zenBest : GameSettings.shared.rankedBest }
        set {
            if mode == .zen { GameSettings.shared.zenBest = newValue }
            else { GameSettings.shared.rankedBest = newValue }
        }
    }

    // Controls
    private let motion = CMMotionManager()
    private var tiltX: CGFloat = 0
    #if DEBUG
    /// The simulator has no accelerometer, so the screenshot bot steers by holding
    /// a screen half. Debug builds only, and only with this launch argument.
    private let debugTouchSteering = UserDefaults.standard.bool(forKey: "uiTestTouchSteering")
    private var debugTouchDirection: CGFloat = 0
    /// Screenshot capture on any device: steers toward the next real gap. Debug builds only.
    private let debugAutopilot = UserDefaults.standard.bool(forKey: "uiTestAutopilot")
    /// Score at which the autopilot lets go, so a run ends in a real game over.
    private let debugAutopilotUntil = UserDefaults.standard.integer(forKey: "uiTestAutopilotUntil")
    #endif

    // First-run tutorial: the mode the player picked, started once they dismiss it.
    private var tutorialMode: GameMode = .ranked
    private var tutorialButton: SKNode?

    // UI (parented to the camera so it stays fixed on screen)
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var overlay: SKNode?
    private var gearNode: SKShapeNode?
    private var leaderboardNode: SKShapeNode?
    private var playButton: SKNode?
    private var zenButton: SKNode?
    private var menuButton: SKLabelNode?
    private var pauseButton: SKShapeNode?
    private var tipLine: SKShapeNode?
    /// Small "ZEN" badge under the score during zen runs, so the player always
    /// knows whether the run counts for the leaderboard. Ranked is the default
    /// and gets no badge — labeling the exception is enough.
    private let modeBadge = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

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
        warmUp()
    }

    /// Pre-warm the expensive-on-first-use subsystems while the menu is up, so the
    /// first play doesn't hitch. The audio session/engine activation and the first
    /// haptic pattern are the main offenders; the ball colour textures are cached
    /// here too so a mid-run tier change never renders on the game thread.
    private func warmUp() {
        SoundManager.shared.warmUp()
        HapticsManager.shared.restartIfNeeded()
        // Cache the colour-tier textures now (tiny, main-thread; the cache isn't
        // thread-safe) so a mid-run tier change never renders during play.
        for tier in BallPalette.tiers.indices {
            _ = BallPalette.texture(tier: tier, radius: ballRadius)
        }
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
        // - ballSprite draws the glossy sphere (kept unrotated so the baked-in
        //   specular highlight stays aligned with the light source),
        // - ballShadow sits beneath it for grounding.
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
        body.allowsRotation = false   // rotation would spin the baked-in highlight
        // The ball is the only dynamic body and can free-fall through several
        // gaps in a row; past ~floorHeight per frame of travel it can tunnel
        // straight through a static floor without this.
        body.usesPreciseCollisionDetection = true
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

        modeBadge.text = "ZEN"
        modeBadge.fontSize = 13
        modeBadge.fontColor = SKColor(red: 0.55, green: 0.8, blue: 0.95, alpha: 0.7)
        modeBadge.horizontalAlignmentMode = .center
        modeBadge.verticalAlignmentMode = .top
        modeBadge.zPosition = 10
        modeBadge.isHidden = true
        cam.addChild(modeBadge)
    }

    /// Top safe-area inset in scene units. On iPad the field is letterboxed and scaled,
    /// so the view inset is reduced by the bar above the field and converted to scene points.
    private var topInset: CGFloat {
        guard let view, view.bounds.height > 0 else { return 59 }
        let raw = view.safeAreaInsets.top
        guard scaleMode == .aspectFit else { return raw > 0 ? raw : 59 }
        let scale = min(view.bounds.width / size.width, view.bounds.height / size.height)
        let barAbove = (view.bounds.height - size.height * scale) / 2
        return max(24, (raw - barAbove) / scale + 12)
    }

    /// Place the score just below the safe-area top inset (clears Dynamic Island).
    /// Read at show-time because insets can be zero during didMove.
    private func positionScoreLabel() {
        let inset = topInset
        scoreLabel.position = CGPoint(x: 0, y: size.height / 2 - inset - 12)
        modeBadge.position = CGPoint(x: 0, y: size.height / 2 - inset - 64)
        comboLabel.position = CGPoint(x: 0, y: size.height / 2 - inset - 84)
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 60.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            // Accelerometer axes are fixed to the device, so pick the axis that runs
            // left-to-right on screen in the current interface orientation (iPad rotates).
            switch self.view?.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            case .landscapeLeft: self.tiltX = CGFloat(a.y)
            case .landscapeRight: self.tiltX = CGFloat(-a.y)
            case .portraitUpsideDown: self.tiltX = CGFloat(-a.x)
            default: self.tiltX = CGFloat(a.x)
            }
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

    /// Zen's ramp: same curve shape, glacial pace. It drifts from the player's
    /// chosen speed toward 1.5x of it with a 7-minute time constant — after a
    /// minute it's barely 13% of the way there. Zen stays relaxing, it just no
    /// longer feels frozen on very long runs.
    private func zenCamSpeed(for t: TimeInterval) -> CGFloat {
        let base = CGFloat(GameSettings.shared.zenSpeed)
        let progress = 1 - exp(-t / 420)
        return base + base * 0.5 * CGFloat(progress)
    }

    // MARK: - Floor generation

    /// Floor userData: "gaps" are hole centres relative to the node (add its live x),
    /// "gapX" is the first one at rest, "depth" is the floor index this run.
    private func makeFloor(atY y: CGFloat, spec: FloorSpec, depth: Int) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: spec.slideOffset(at: elapsed), y: y)

        // Sliding floors carry plank past both walls so their travel never opens an edge.
        let overhang = spec.slideAmplitude > 0 ? spec.slideAmplitude + 40 : 0
        let gaps = spec.gapCenters.sorted()
        var edges: [CGFloat] = [-overhang]
        for x in gaps {
            edges.append(x - spec.gapWidth / 2)
            edges.append(x + spec.gapWidth / 2)
        }
        edges.append(size.width + overhang)

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
        for i in stride(from: 0, to: edges.count - 1, by: 2) {
            segment(x: (edges[i] + edges[i + 1]) / 2, width: edges[i + 1] - edges[i])
        }

        let body = SKPhysicsBody(bodies: bodies)
        body.isDynamic = false
        body.categoryBitMask = Category.floor
        body.friction = 0.3
        body.restitution = 0.3
        node.physicsBody = body
        var data: [String: Any] = ["scored": false, "gapX": gaps[0], "gaps": gaps, "depth": depth]
        if spec.slideAmplitude > 0 {
            data["slideAmp"] = spec.slideAmplitude
            data["slidePeriod"] = spec.slidePeriod
            data["slidePhase"] = spec.slidePhase
        }
        node.userData = NSMutableDictionary(dictionary: data)
        return node
    }

    /// Ensure floors exist from just above the view down to below its bottom.
    private func fillFloorsBelow() {
        while lowestFloorY > viewBottom - floorSpacing {
            let depth = floorPattern.depth
            let spec = floorPattern.next(using: &floorRandom)
            let y = lowestFloorY - floorSpacing
            let floor = makeFloor(atY: y, spec: spec, depth: depth)
            addChild(floor)
            floors.append(floor)
            lowestFloorY = y
        }
    }

    /// Glide sliding floors before the physics step. A scored floor freezes so its
    /// hole edge never sweeps into a ball that is still passing through.
    private func slideFloors() {
        for floor in floors {
            guard let data = floor.userData,
                  let amp = data["slideAmp"] as? CGFloat,
                  let period = data["slidePeriod"] as? Double,
                  let phase = data["slidePhase"] as? Double,
                  data["scored"] as? Bool == false else { continue }
            let spec = FloorSpec(kind: .sliding, gapCenters: [], gapWidth: 0,
                                 slideAmplitude: amp, slidePeriod: period, slidePhase: phase)
            floor.position.x = spec.slideOffset(at: elapsed)
        }
    }

    // MARK: - Game flow

    private func showMenu() {
        state = .menu
        scoreLabel.isHidden = true
        modeBadge.isHidden = true
        ball.physicsBody?.isDynamic = false
        // The ball IS the "O" of DROP — parked in the title's letter gap below,
        // once the O-slot position is computed. startGame keeps this screen
        // position, so the run visibly begins with the title's own ball
        // dropping out of the word.

        let node = SKNode()
        node.zPosition = 20

        // "DR ● P" — two labels leave a ball-sized hole where the O belongs.
        // 50pt Avenir Next Heavy has a cap height of ~35pt, a close match for
        // the 34pt ball, so the ball genuinely reads as the missing letter.
        // The WORD is centered on screen, which puts the O slot slightly right
        // of center ("DR" is wider than "P"); the ball parks there and the run
        // starts from that same spot (see startGame / titleBallOffsetX).
        let titleY = size.height * 0.12
        // Tight slot: just 2pt of air around the ball, so the letter spacing
        // reads as DROP, not "DR O P".
        let slotHalf = ballRadius + 2
        let left = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        left.text = "DR"
        left.fontSize = 50
        left.fontColor = .white
        left.horizontalAlignmentMode = .right
        left.verticalAlignmentMode = .center
        let right = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        right.text = "P"
        right.fontSize = 50
        right.fontColor = .white
        right.horizontalAlignmentMode = .left
        right.verticalAlignmentMode = .center
        // Word width = DR + ball slot + P; O-slot center relative to word center.
        let wordWidth = left.frame.width + slotHalf * 2 + right.frame.width
        titleBallOffsetX = -wordWidth / 2 + left.frame.width + slotHalf
        left.position = CGPoint(x: titleBallOffsetX - slotHalf, y: titleY)
        right.position = CGPoint(x: titleBallOffsetX + slotHalf, y: titleY)
        node.addChild(left)
        node.addChild(right)
        ball.position = CGPoint(x: size.width / 2 + titleBallOffsetX,
                                y: cam.position.y + titleY)

        // Explicit mode buttons. The old menu started a ranked run on ANY tap
        // (with zen as a bare text line) — easy to mis-tap into a scored run,
        // and easy to never notice zen existed. Two visible pills fix both:
        // filled red = primary (ranked), outlined blue = secondary (zen).
        let play = makePill(text: "PLAY", name: "play",
                            fill: SKColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1),
                            stroke: .clear,
                            textColor: .white)
        play.position = CGPoint(x: 0, y: 8)
        node.addChild(play)
        playButton = play

        let zenBlue = SKColor(red: 0.55, green: 0.8, blue: 0.95, alpha: 1)
        let zen = makePill(text: "ZEN", name: "zen", symbol: "leaf.fill",
                           fill: SKColor(white: 0, alpha: 0.3),
                           stroke: zenBlue,
                           textColor: zenBlue)
        zen.position = CGPoint(x: 0, y: -64)
        node.addChild(zen)
        zenButton = zen

        let ctl = SKLabelNode(fontNamed: "AvenirNext-Regular")
        ctl.text = "Tilt your \(GameSettings.deviceNoun) to steer"
        ctl.fontSize = 16
        ctl.fontColor = SKColor(white: 0.7, alpha: 1)
        // Anchored to the ZEN pill rather than screen height so it never crowds the pill.
        ctl.position = CGPoint(x: 0, y: zen.position.y - 72)
        node.addChild(ctl)

        let rankedBest = GameSettings.shared.rankedBest
        let zenBest = GameSettings.shared.zenBest
        if rankedBest > 0 || zenBest > 0 {
            let hs = SKLabelNode(fontNamed: "AvenirNext-Medium")
            // Only show the components that exist — a zen-only player used to
            // see a bogus "Best 0" in front of their zen best.
            var parts: [String] = []
            if rankedBest > 0 { parts.append("Best \(rankedBest)") }
            if zenBest > 0 { parts.append("Zen \(zenBest)") }
            hs.text = parts.joined(separator: "   •   ")
            hs.fontSize = 18
            hs.fontColor = SKColor(red: 1.0, green: 0.5, blue: 0.42, alpha: 1)
            hs.position = CGPoint(x: 0, y: zen.position.y - 106)
            node.addChild(hs)
        }

        addGear(to: node)
        addLeaderboardButton(to: node)
        cam.addChild(node)
        overlay = node
    }

    /// Settings gear, top-right, clear of the safe-area inset.
    private func addGear(to node: SKNode) {
        let gear = SceneIcons.cornerButton("gearshape.fill", color: cornerIconWhite, name: "gear")
        gear.position = CGPoint(x: size.width / 2 - 36, y: cornerButtonY)
        markButton(gear, label: "Settings")
        node.addChild(gear)
        gearNode = gear
    }

    /// Leaderboard button, top-left, mirroring the gear.
    private func addLeaderboardButton(to node: SKNode) {
        // Muted gold keeps the trophy's identity without outshining the white set.
        let gold = SKColor(red: 1.0, green: 0.82, blue: 0.42, alpha: 0.92)
        let lb = SceneIcons.cornerButton("trophy.fill", color: gold, name: "leaderboard")
        lb.position = CGPoint(x: -size.width / 2 + 36, y: cornerButtonY)
        markButton(lb, label: "Scores")
        node.addChild(lb)
        leaderboardNode = lb
    }

    private var cornerIconWhite: SKColor { SKColor(white: 1, alpha: 0.85) }

    /// Corner discs sit just under the safe-area inset so their top edge clears it.
    private var cornerButtonY: CGFloat { size.height / 2 - topInset - 22 }

    /// A pill-shaped button: rounded SKShapeNode with a centered label. 56pt
    /// tall (clears the 44pt minimum tap target) and the visible shape IS the
    /// hit area, so affordance and tap target finally coincide.
    private func makePill(text: String, name: String, symbol: String? = nil,
                          fill: SKColor, stroke: SKColor, textColor: SKColor) -> SKNode {
        let pill = SKShapeNode(rectOf: CGSize(width: 220, height: 56), cornerRadius: 28)
        pill.fillColor = fill
        pill.strokeColor = stroke
        pill.lineWidth = stroke == .clear ? 0 : 2
        pill.name = name

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 24
        label.fontColor = textColor
        label.verticalAlignmentMode = .center
        label.name = name           // taps on the label count as the button
        label.isAccessibilityElement = false
        pill.addChild(label)
        if let symbol {
            let icon = SceneIcons.sprite(symbol, pointSize: 18, weight: .bold, color: textColor)
            icon.name = name
            icon.isAccessibilityElement = false
            let gap: CGFloat = 8
            let groupWidth = icon.size.width + gap + label.frame.width
            icon.position = CGPoint(x: -groupWidth / 2 + icon.size.width / 2, y: 0)
            label.horizontalAlignmentMode = .left
            label.position = CGPoint(x: -groupWidth / 2 + icon.size.width + gap, y: 0)
            pill.addChild(icon)
        }
        markButton(pill, label: text.filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces).capitalized)
        return pill
    }

    /// Exposes a scene button to VoiceOver and UI tests; SpriteKit derives its frame.
    private func markButton(_ node: SKNode, label: String) {
        node.isAccessibilityElement = true
        node.accessibilityLabel = label
        node.accessibilityTraits = .button
    }

    /// If the tap hit the gear or leaderboard button, handle it and return true.
    private func handleButtonTap(_ touches: Set<UITouch>) -> Bool {
        guard let t = touches.first else { return false }
        let p = t.location(in: cam)
        if let gear = gearNode, gear.frame.insetBy(dx: -18, dy: -18).contains(p) {
            HapticsManager.shared.uiTap()
            SceneIcons.pressDip(gear)
            onOpenSettings?()
            return true
        }
        if let lb = leaderboardNode, lb.frame.insetBy(dx: -18, dy: -18).contains(p) {
            HapticsManager.shared.uiTap()
            SceneIcons.pressDip(lb)
            onShowLeaderboard?()
            return true
        }
        return false
    }

    /// If the tap hit the "Main Menu" button, return to the menu and return true.
    private func handleMenuButtonTap(_ touches: Set<UITouch>) -> Bool {
        guard let t = touches.first, let btn = menuButton,
              btn.frame.insetBy(dx: -24, dy: -18).contains(t.location(in: cam)) else { return false }
        HapticsManager.shared.uiTap()
        returnToMenu()
        return true
    }

    /// Press feedback on a mode pill (quick scale dip), then start the run, via
    /// the tutorial if the player hasn't seen it yet.
    private func pressAndStart(_ button: SKNode, mode: GameMode) {
        HapticsManager.shared.uiTap()
        button.run(.sequence([
            .scale(to: 0.93, duration: 0.06),
            .scale(to: 1.0, duration: 0.06),
            .run { [weak self] in
                guard let self else { return }
                if GameSettings.shared.hasSeenTutorial {
                    self.startGame(mode: mode)
                } else {
                    self.showTutorial(mode: mode)
                }
            },
        ]))
    }

    // MARK: - Tutorial

    /// One card shown before the first run: a phone rocking side to side with
    /// the ball rolling downhill on its screen, so the gesture is shown, not described.
    private func showTutorial(mode: GameMode) {
        guard state == .menu else { return }
        state = .tutorial
        tutorialMode = mode
        overlay?.removeFromParent()
        gearNode = nil
        leaderboardNode = nil
        playButton = nil
        zenButton = nil
        // The parked title ball would sit on top of the illustration.
        ball.isHidden = true

        let node = SKNode()
        node.zPosition = 20

        let phone = SKShapeNode(rectOf: CGSize(width: 76, height: 136), cornerRadius: 16)
        phone.fillColor = SKColor(white: 0, alpha: 0.35)
        phone.strokeColor = SKColor(white: 0.9, alpha: 1)
        phone.lineWidth = 3
        phone.position = CGPoint(x: 0, y: size.height * 0.15)
        node.addChild(phone)

        // A floor with a gap on the phone's screen, and the ball above it.
        let plankY: CGFloat = -30
        let plankH: CGFloat = 7
        for x in [CGFloat(-20), 20] {
            let seg = SKSpriteNode(texture: plankTexture)
            seg.size = CGSize(width: 20, height: plankH)
            seg.position = CGPoint(x: x, y: plankY)
            phone.addChild(seg)
        }
        let mini = SKSpriteNode(texture: ballTexture)
        mini.size = CGSize(width: 16, height: 16)
        mini.position = CGPoint(x: 0, y: plankY + plankH / 2 + 8)
        phone.addChild(mini)

        // Positive zRotation drops the left edge, so the ball rolls left: the
        // same direction tilting the real phone steers.
        let angle: CGFloat = 0.3
        let swing: TimeInterval = 0.9
        func rock(_ a: CGFloat) -> SKAction {
            let r = SKAction.rotate(toAngle: a, duration: swing)
            r.timingMode = .easeInEaseOut
            return r
        }
        func roll(_ x: CGFloat) -> SKAction {
            let m = SKAction.moveTo(x: x, duration: swing)
            m.timingMode = .easeInEaseOut
            return m
        }
        phone.run(.sequence([rock(angle), .repeatForever(.sequence([rock(-angle), rock(angle)]))]))
        mini.run(.sequence([roll(-22), .repeatForever(.sequence([roll(22), roll(-22)]))]))

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "Tilt to steer"
        title.fontSize = 32
        title.fontColor = .white
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: -size.height * 0.02)
        node.addChild(title)

        for (i, line) in ["Drop through the gaps.", "Don't get pushed off the top."].enumerated() {
            let l = SKLabelNode(fontNamed: "AvenirNext-Medium")
            l.text = line
            l.fontSize = 18
            l.fontColor = SKColor(white: 0.75, alpha: 1)
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: 0, y: -size.height * 0.075 - CGFloat(i) * 28)
            node.addChild(l)
        }

        let start = makePill(text: "START", name: "start",
                             fill: SKColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1),
                             stroke: .clear,
                             textColor: .white)
        start.position = CGPoint(x: 0, y: -size.height * 0.2)
        node.addChild(start)
        tutorialButton = start

        node.alpha = 0
        node.run(.fadeIn(withDuration: 0.2))
        cam.addChild(node)
        overlay = node
    }

    private func startGame(mode: GameMode) {
        self.mode = mode
        overlay?.removeFromParent()
        overlay = nil
        gearNode = nil
        leaderboardNode = nil
        playButton = nil
        zenButton = nil
        menuButton = nil
        tutorialButton = nil
        tipLine = nil
        ball.isHidden = false
        state = .playing

        floors.forEach { $0.removeFromParent() }
        floors.removeAll()
        camSpeed = mode == .zen ? CGFloat(GameSettings.shared.zenSpeed) : baseCamSpeed
        elapsed = 0
        bankedPlaytime = 0
        score = 0
        cleanStreak = 0
        bestStreakThisRun = 0
        bouncesSinceGap = 0
        nextMilestone = milestoneEvery
        setBallTier(0, animated: false)   // back to the classic red each run
        scoreLabel.text = "0"
        scoreLabel.isHidden = false
        comboLabel.isHidden = true
        modeBadge.isHidden = mode != .zen   // badge the exception, not the default
        positionScoreLabel()
        addPauseButton()

        // Reset the camera and lay down a starting floor beneath the ball.
        // The ball begins exactly where the menu title's O sits (slightly right
        // of center; the camera reset keeps the screen position identical), so
        // play starts with that exact ball simply beginning to fall. The first
        // gap is centered under it.
        let startX = size.width / 2 + titleBallOffsetX
        cam.position = CGPoint(x: size.width / 2, y: 0)
        scriptedCamY = 0
        lowestFloorY = 0
        floorPattern = FloorPatternGenerator(fieldWidth: size.width,
                                             schedule: mode == .zen ? .zen : .ranked,
                                             firstGapX: startX, standardGapWidth: gapWidth,
                                             sideMargin: sideMargin)

        let firstY = -size.height * 0.10
        let first = makeFloor(atY: firstY, spec: .standard(at: startX, gapWidth: gapWidth), depth: 0)
        addChild(first)
        floors.append(first)
        lowestFloorY = firstY

        ball.position = CGPoint(x: startX, y: size.height * 0.12)
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.restitution = CGFloat(GameSettings.shared.bounciness)
        ball.physicsBody?.isDynamic = true

        fillFloorsBelow()
    }

    /// Small pause button, top-right during play (where the gear sits on menus).
    private func addPauseButton() {
        pauseButton?.removeFromParent()
        let btn = SceneIcons.cornerButton("pause.fill", color: cornerIconWhite, name: "pause",
                                          pointSize: 20)
        btn.position = CGPoint(x: size.width / 2 - 36, y: cornerButtonY)
        markButton(btn, label: "Pause")
        btn.zPosition = 15
        cam.addChild(btn)
        pauseButton = btn
    }

    // MARK: - Pause

    /// Flush any not-yet-banked run time into the lifetime total.
    private func bankPlaytime() {
        let delta = elapsed - bankedPlaytime
        guard delta > 0 else { return }
        GameSettings.shared.totalTimePlayed += delta
        bankedPlaytime = elapsed
    }

    func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        physicsWorld.speed = 0
        pauseButton?.isHidden = true
        bankPlaytime()   // covers quit-via-menu and app kill while backgrounded

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

        // Main Menu button — lets the player quit the run and switch modes without
        // restarting the app.
        addMenuButton(to: node, y: -size.height * 0.12)

        // Settings gear and leaderboard on the pause screen, so players can tweak
        // settings or check scores mid-run without ending the game.
        addGear(to: node)
        addLeaderboardButton(to: node)
        cam.addChild(node)
        overlay = node
    }

    /// A "Main Menu" text button used on the pause and game-over overlays.
    private func addMenuButton(to node: SKNode, y: CGFloat) {
        let btn = SKLabelNode(fontNamed: "AvenirNext-Medium")
        btn.text = "Main Menu"
        btn.fontSize = 20
        btn.fontColor = SKColor(white: 0.7, alpha: 1)
        btn.verticalAlignmentMode = .center
        btn.position = CGPoint(x: 0, y: y)
        btn.name = "mainmenu"
        markButton(btn, label: "Main Menu")
        node.addChild(btn)
        menuButton = btn
    }

    /// Tear down the current overlay and return to the main menu (from pause or
    /// game over), so the player can pick the other mode.
    private func returnToMenu() {
        overlay?.removeFromParent()
        overlay = nil
        gearNode = nil
        leaderboardNode = nil
        menuButton = nil
        tipLine = nil
        pauseButton?.removeFromParent()
        pauseButton = nil
        physicsWorld.speed = 1        // in case we came from pause
        ball.physicsBody?.isDynamic = false
        scoreLabel.isHidden = true
        comboLabel.isHidden = true
        setBallTier(0, animated: false)
        floors.forEach { $0.removeFromParent() }
        floors.removeAll()
        cam.position = CGPoint(x: size.width / 2, y: 0)
        showMenu()
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
        modeBadge.isHidden = true   // the overlay's "ZEN OVER" title carries the mode
        HapticsManager.shared.gameOver()

        // Lifetime time played (both modes) — the part not already banked at pause.
        bankPlaytime()

        // Ranked scores feed Game Center; Zen never does (self-set speed).
        if mode == .ranked { onGameOver?(score) }

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

        // Capture BEFORE updating the best — otherwise "Score: 42  Best: 42"
        // gives no hint the run just set a record.
        let isNewBest = score > highScore
        if isNewBest {
            highScore = score                       // routes to ranked or zen best
            if mode == .zen { GameSettings.shared.zenBestDuration = elapsed }
            else { GameSettings.shared.rankedBestDuration = elapsed }
        }
        let offerTip = onRunFinished?(RunSummary(score: score, duration: elapsed, isNewBest: isNewBest)) ?? false

        let node = SKNode()
        node.zPosition = 20

        // Same dim as pause, faded in after the flash so the text never sits on bare planks.
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.5), size: size)
        dim.zPosition = -1
        dim.alpha = 0
        dim.run(.fadeIn(withDuration: 0.3))
        node.addChild(dim)

        let over = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        over.text = mode == .zen ? "ZEN OVER" : "GAME OVER"
        over.fontSize = 40
        over.fontColor = .white
        over.position = CGPoint(x: 0, y: size.height * 0.08)
        node.addChild(over)

        let sc = SKLabelNode(fontNamed: "AvenirNext-Bold")
        sc.text = isNewBest ? "NEW BEST: \(score)!"
                            : "Score: \(score)   Best: \(highScore)"
        sc.fontSize = 22
        sc.fontColor = isNewBest ? SKColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
                                 : SKColor(white: 0.85, alpha: 1)
        sc.position = CGPoint(x: 0, y: 0)
        node.addChild(sc)
        if isNewBest {
            // A little pop so the record run registers as a moment.
            sc.setScale(0.1)
            sc.run(.sequence([
                .scale(to: 1.25, duration: 0.22),
                .scale(to: 1.0, duration: 0.12),
            ]))
        }

        let again = SKLabelNode(fontNamed: "AvenirNext-Medium")
        again.text = "Tap to play again"
        again.fontSize = 22
        again.fontColor = SKColor(red: 1.0, green: 0.5, blue: 0.42, alpha: 1)
        again.position = CGPoint(x: 0, y: -size.height * 0.06)
        node.addChild(again)

        // Main Menu button, so the player can switch modes instead of replaying.
        addMenuButton(to: node, y: -size.height * 0.12)
        if offerTip { addTipLine(to: node) }

        addGear(to: node)
        addLeaderboardButton(to: node)
        cam.addChild(node)
        overlay = node
    }

    /// A footnote-sized line near the bottom, faded in after the death moment has passed,
    /// so it reads as an aside rather than part of the game-over message.
    private func addTipLine(to node: SKNode) {
        let pink = SKColor(red: 1.0, green: 0.68, blue: 0.76, alpha: 1)
        let text = SKLabelNode(fontNamed: "AvenirNext-Medium")
        text.text = "Enjoying Drop? Leave a tip"
        text.fontSize = 16
        text.fontColor = pink
        text.verticalAlignmentMode = .center
        text.horizontalAlignmentMode = .left
        text.isAccessibilityElement = false
        let cup = SceneIcons.sprite("cup.and.saucer.fill", pointSize: 14, color: pink)
        cup.isAccessibilityElement = false
        let gap: CGFloat = 6
        let width = text.frame.width + gap + cup.size.width
        text.position = CGPoint(x: -width / 2, y: 0)
        cup.position = CGPoint(x: width / 2 - cup.size.width / 2, y: 1)

        // An invisible rect is the accessible, tappable node so its frame spans text and cup.
        let line = SKShapeNode(rectOf: CGSize(width: width, height: 24))
        line.fillColor = .clear
        line.strokeColor = .clear
        line.lineWidth = 0
        line.addChild(text)
        line.addChild(cup)
        line.position = CGPoint(x: 0, y: -size.height / 2 + 72)
        line.name = "tipline"
        markButton(line, label: "Leave a tip")
        line.alpha = 0
        line.run(.sequence([.wait(forDuration: 0.9), .fadeAlpha(to: 0.85, duration: 0.4)]))
        node.addChild(line)
        tipLine = line
    }

    private func handleTipLineTap(_ touches: Set<UITouch>) -> Bool {
        // Before it has faded in, a tap there is meant as "play again".
        guard let t = touches.first, let line = tipLine, line.alpha > 0.5,
              line.frame.insetBy(dx: -16, dy: -14).contains(t.location(in: cam)) else { return false }
        HapticsManager.shared.uiTap()
        onOpenTipJar?()
        return true
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch state {
        case .menu:
            // Gear / leaderboard taps handled first.
            if handleButtonTap(touches) { return }
            // Explicit mode buttons only — no implicit start. A stray tap must
            // not launch a ranked (leaderboard-scored) run by accident.
            guard let t = touches.first else { return }
            let p = t.location(in: cam)
            if let play = playButton, play.frame.insetBy(dx: -10, dy: -10).contains(p) {
                pressAndStart(play, mode: .ranked)
            } else if let zen = zenButton, zen.frame.insetBy(dx: -10, dy: -10).contains(p) {
                pressAndStart(zen, mode: .zen)
            }
        case .tutorial:
            // Only the START pill dismisses it, so a stray tap can't skip the card.
            guard let t = touches.first, let btn = tutorialButton,
                  btn.frame.insetBy(dx: -10, dy: -10).contains(t.location(in: cam)) else { return }
            tutorialButton = nil
            GameSettings.shared.hasSeenTutorial = true
            pressAndStart(btn, mode: tutorialMode)
        case .gameOver:
            if handleButtonTap(touches) { return }
            if handleMenuButtonTap(touches) { return }
            if handleTipLineTap(touches) { return }
            HapticsManager.shared.uiTap()
            overlay?.removeFromParent()
            overlay = nil
            startGame(mode: mode)   // replay the same mode
        case .paused:
            // Gear / leaderboard / Main Menu handled first; any other tap resumes.
            if handleButtonTap(touches) { return }
            if handleMenuButtonTap(touches) { return }
            resumeGame()
        case .playing:
            // The pause button is the only touch target mid-run; steering is tilt.
            if let t = touches.first, let btn = pauseButton,
               btn.frame.insetBy(dx: -20, dy: -20).contains(t.location(in: cam)) {
                HapticsManager.shared.uiTap()
                pauseGame()
                return
            }
            #if DEBUG
            updateDebugTouchDirection(touches)
            #endif
        }
    }

    #if DEBUG
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if state == .playing { updateDebugTouchDirection(touches) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        debugTouchDirection = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        debugTouchDirection = 0
    }

    private func updateDebugTouchDirection(_ touches: Set<UITouch>) {
        guard debugTouchSteering, let t = touches.first else { return }
        debugTouchDirection = t.location(in: self).x < size.width / 2 ? -1 : 1
    }
    #endif

    /// Horizontal steering input, -1 (left) … 1 (right).
    private var steerInput: CGFloat {
        #if DEBUG
        if debugTouchDirection != 0 { return debugTouchDirection }
        if debugAutopilot { return autopilotInput }
        #endif
        return tiltX
    }

    #if DEBUG
    private var autopilotInput: CGFloat {
        if debugAutopilotUntil > 0, score >= debugAutopilotUntil { return 0 }
        let below = floors.filter { $0.position.y < ball.position.y - ballRadius }
        guard let next = below.max(by: { $0.position.y < $1.position.y }),
              let gaps = next.userData?["gaps"] as? [CGFloat],
              let target = gaps.map({ $0 + next.position.x })
                .min(by: { abs($0 - ball.position.x) < abs($1 - ball.position.x) })
        else { return 0 }
        return max(-1, min(1, (target - ball.position.x) / 50))
    }
    #endif

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        // Raw frame delta for timekeeping; a tighter clamp for camera motion.
        // Clamping before accumulating `elapsed` made the difficulty ramp and
        // lifetime playtime undercount whenever frames hitched. The 0.5s cap
        // only guards against pathological gaps the lastUpdate reset misses.
        let rawDt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.5)
        lastUpdate = currentTime
        let dt = min(rawDt, 1.0 / 30.0)   // clamp to avoid physics hitches
        guard state == .playing else { return }

        // Sample the ball's velocity before the solver runs this frame; didBegin
        // uses it as the true incoming impact speed (see preStepVelocity).
        preStepVelocity = ball.physicsBody?.velocity ?? .zero

        elapsed += rawDt
        // Ranked ramps up fast; Zen ramps too, but glacially (see zenCamSpeed).
        camSpeed = mode == .zen ? zenCamSpeed(for: elapsed)
                                : camSpeed(for: elapsed)
        slideFloors()

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

        // Steering, applied after physics so it isn't fighting the solver
        // mid-step. Sensitivity scales the response.
        let sensitivity = CGFloat(GameSettings.shared.sensitivity)
        let desiredVX = steerInput * ballMaxHSpeed * sensitivity
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
            bestStreakThisRun = max(bestStreakThisRun, cleanStreak)
            if mode == .ranked {
                GameSettings.shared.totalCleanPasses += 1   // lifetime stat (Scores sheet)
            }
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
        updateBallTier()                            // colour warms/cools with score

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

    // MARK: - Ball colour (live progress)

    /// Swap the ball to the colour tier its score has reached, if it changed.
    /// No-op when the player has turned colour changes off.
    private func updateBallTier() {
        guard GameSettings.shared.ballColorEnabled else { return }
        let t = BallPalette.tierIndex(for: score)
        guard t != ballTier else { return }
        setBallTier(t, animated: true)
    }

    /// Apply a colour tier. Animated swaps do a quick scale pop so the change
    /// reads as a reward rather than a flicker.
    private func setBallTier(_ tier: Int, animated: Bool) {
        ballTier = tier
        ballSprite.texture = BallPalette.texture(tier: tier, radius: ballRadius)
        if animated {
            ballSprite.removeAllActions()
            ballSprite.setScale(1.28)
            ballSprite.run(.scale(to: 1.0, duration: 0.18))
        }
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
        let vy = preStepVelocity.dy
        guard vy < -40 else { return }   // ignore grazes and settling contacts
        // Count the bounce unconditionally. This used to sit inside the haptic
        // throttle below, so a second bounce within 60ms was never counted and
        // a messy pass could still be scored as "clean".
        bouncesSinceGap += 1
        // Feedback only, throttled so rapid bounces don't stack haptics/sound.
        if lastUpdate - lastLandHaptic > 0.06 {
            lastLandHaptic = lastUpdate
            HapticsManager.shared.land(velocity: vy)
            SoundManager.shared.bounce(velocity: vy)
        }
    }
}
