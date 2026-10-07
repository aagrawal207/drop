import UIKit
import SpriteKit
import SwiftUI
import StoreKit

class GameViewController: UIViewController {
    private weak var scene: GameScene?
    private let skView = SKView(frame: UIScreen.main.bounds)
    private let engagement = EngagementPolicy()
    /// At most one ask of either kind per launch, so a session never carries both.
    private var promptedThisSession = false
    private var pendingReview: Task<Void, Never>?

    override func loadView() {
        let root = UIView(frame: UIScreen.main.bounds)
        root.backgroundColor = .black
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(skView)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scene: GameScene
        if Self.isPad {
            // iPad windows rotate and resize (Stage Manager, Split View), but the physics
            // world needs fixed coordinates, so a portrait field is letterboxed instead.
            scene = GameScene(size: Self.padFieldSize)
            scene.scaleMode = .aspectFit
            installLetterboxBackdrop()
        } else {
            scene = GameScene(size: skView.bounds.size)
            scene.scaleMode = .resizeFill
        }
        scene.onOpenSettings = { [weak self] in self?.presentSettings() }
        scene.onShowLeaderboard = { [weak self] in self?.presentScores() }
        scene.onGameOver = { score in
            GameCenterManager.shared.submit(score: score)
        }
        scene.onRunFinished = { [weak self] run in self?.followUp(after: run) ?? false }
        scene.onOpenTipJar = { [weak self] in self?.presentTipJar() }
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        self.scene = scene

        GameCenterManager.shared.authenticate()
        engagement.recordLaunch()
        // Approvals and interrupted tips arrive on the App Store's schedule, not while the sheet is open.
        TipJarService.shared.observeTransactions()

        // Auto-pause only on real backgrounding (home, app switch, lock), NOT on
        // willResignActive — that also fires for transient overlays (Control
        // Center, notification banners, the Game Center welcome banner), which
        // would spuriously pause an active run right after a fresh install.
        NotificationCenter.default.addObserver(
            self, selector: #selector(autoPause),
            name: UIApplication.didEnterBackgroundNotification, object: nil)

        // The system tears down the haptic engine and audio session on
        // backgrounding; rebuild both when returning to the foreground so
        // haptics and sound don't silently die.
        NotificationCenter.default.addObserver(
            self, selector: #selector(restartAudioFeedback),
            name: UIApplication.willEnterForegroundNotification, object: nil)

        // SpriteKit auto-pauses the SKView's render loop when the app resigns
        // active, but doesn't reliably un-pause it when the interruption was a
        // system overlay (notably the Game Center "welcome back" banner). That
        // leaves the scene frozen mid-play with no overlay. Force the render loop
        // back on every time we become active. This is independent of our logical
        // pause (overlay + physicsWorld.speed = 0), which never touches isPaused.
        NotificationCenter.default.addObserver(
            self, selector: #selector(resumeRendering),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Also fires after any presented sheet (settings, scores, Game Center) is
    /// dismissed — a modal over the SKView can pause it the same way.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resumeRendering()
    }

    @objc private func autoPause() {
        scene?.pauseGame()
    }

    @objc private func restartAudioFeedback() {
        HapticsManager.shared.restartIfNeeded()
        SoundManager.shared.restartIfNeeded()
    }

    @objc private func resumeRendering() {
        skView.isPaused = false
    }

    // MARK: - Rating and tip prompts

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Screenshot and acceptance runs must never meet a review sheet or the tip line.
    private static let promptsSuppressed: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        #else
        return false
        #endif
    }()

    /// Debug `-engagementForce review|tip` skips the thresholds without touching stored progress.
    private static var forcedPrompt: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "engagementForce")
        #else
        return nil
        #endif
    }

    /// Returns true when the scene should show the tip line on this game-over screen.
    private func followUp(after run: RunSummary) -> Bool {
        pendingReview?.cancel()
        pendingReview = nil
        guard !Self.promptsSuppressed else { return false }
        if let forced = Self.forcedPrompt {
            guard !promptedThisSession else { return false }
            if forced == "review" { scheduleReview(record: false) }
            return forced == "tip" ? markPrompted() : false
        }

        engagement.recordCompletedRun()
        guard run.endedWell, !promptedThisSession else { return false }
        if engagement.canRequestReview(version: marketingVersion) {
            scheduleReview(record: true)
            return false
        }
        if engagement.canShowTipLine(hasTipped: TipJarService.shared.tipCount > 0) {
            engagement.recordTipLineShown()
            return markPrompted()
        }
        return false
    }

    private func markPrompted() -> Bool {
        promptedThisSession = true
        return true
    }

    /// Waits for the game-over screen to settle, then asks only if the player is still
    /// looking at it: replaying, opening a sheet or leaving the app forfeits the moment.
    private func scheduleReview(record: Bool) {
        pendingReview = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled, !self.promptedThisSession,
                  self.scene?.isShowingGameOver == true, self.presentedViewController == nil,
                  UIApplication.shared.applicationState == .active,
                  let windowScene = self.view.window?.windowScene,
                  windowScene.activationState == .foregroundActive else { return }
            if record { self.engagement.recordReviewRequest(version: self.marketingVersion) }
            self.promptedThisSession = true
            AppStore.requestReview(in: windowScene)
        }
    }

    private func presentTipJar() {
        guard presentedViewController == nil else { return }
        let host = UIHostingController(rootView: TipJarView())
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    private func presentSettings() {
        let settings = SettingsView { [weak self] in
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: settings)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    private func presentScores() {
        // If Game Center is waiting on sign-in, let the trophy be that entry
        // point — present it now, player-initiated, rather than on launch.
        if !GameCenterManager.shared.isAuthenticated,
           GameCenterManager.shared.presentPendingSignIn(from: self) {
            return
        }

        let scores = ScoresView(
            gameCenterAvailable: GameCenterManager.shared.isAuthenticated,
            onShowGameCenter: { [weak self] in
                self?.dismiss(animated: true) {
                    GameCenterManager.shared.showLeaderboard(from: self)
                }
            },
            onDone: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: scores)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { Self.isPad ? .all : .portrait }

    /// Darker walnut around the field, so the bars read as the same table rather than black.
    private func installLetterboxBackdrop() {
        let side = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let wood = WoodTexture.background(width: side, height: side).cgImage()
        let backdrop = UIImageView(image: UIImage(cgImage: wood))
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.contentMode = .scaleAspectFill
        let shade = UIView(frame: backdrop.bounds)
        shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shade.backgroundColor = UIColor(white: 0, alpha: 0.45)
        backdrop.addSubview(shade)
        view.insertSubview(backdrop, belowSubview: skView)
        skView.autoresizingMask = []
    }

    /// On iPad the SKView itself is the fitted portrait field, so nothing letterboxes
    /// inside SpriteKit and the backdrop shows around it.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard Self.isPad, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let field = Self.padFieldSize
        let scale = min(view.bounds.width / field.width, view.bounds.height / field.height)
        let size = CGSize(width: field.width * scale, height: field.height * scale)
        let frame = CGRect(x: view.bounds.midX - size.width / 2, y: view.bounds.midY - size.height / 2,
                           width: size.width, height: size.height).integral
        if skView.frame != frame { skView.frame = frame }
    }

    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// Close to an 11-inch iPad's portrait aspect, so portrait nearly fills the screen.
    private static let padFieldSize = CGSize(width: 600, height: 860)
}
