import UIKit
import SpriteKit
import SwiftUI

class GameViewController: UIViewController {
    private weak var scene: GameScene?
    private let skView = SKView(frame: UIScreen.main.bounds)

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
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        self.scene = scene

        GameCenterManager.shared.authenticate()
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
