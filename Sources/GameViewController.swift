import UIKit
import SpriteKit
import SwiftUI

class GameViewController: UIViewController {
    private weak var scene: GameScene?

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let skView = view as? SKView else { return }
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onOpenSettings = { [weak self] in self?.presentSettings() }
        scene.onShowLeaderboard = { [weak self] in self?.presentScores() }
        scene.onGameOver = { score in
            GameCenterManager.shared.submit(score: score)
        }
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        self.scene = scene

        GameCenterManager.shared.authenticate(presenter: self)

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
        (view as? SKView)?.isPaused = false
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
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
