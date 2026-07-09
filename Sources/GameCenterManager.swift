import GameKit

/// Wraps Game Center authentication and leaderboard submission. Everything here
/// is best-effort: if the player isn't signed in, or the app hasn't been set up
/// in App Store Connect yet, calls simply no-op and `isAuthenticated` stays
/// false so the UI can hide its leaderboard entry points.
final class GameCenterManager {
    static let shared = GameCenterManager()

    /// Must match the leaderboard ID created in App Store Connect.
    static let leaderboardID = "com.agraabhi.drop.highscore"

    /// Achievements. Each `id` must match an achievement created in App Store
    /// Connect (Features → Game Center) before it will actually record on device.
    /// Only ranked (Normal) play triggers these — Zen is self-adjusted difficulty.
    enum Achievement: String, CaseIterable {
        case score25    = "com.agraabhi.drop.ach.score25"
        case score50    = "com.agraabhi.drop.ach.score50"
        case score100   = "com.agraabhi.drop.ach.score100"
        case streak5    = "com.agraabhi.drop.ach.streak5"
        case streak10   = "com.agraabhi.drop.ach.streak10"
        case cleanTotal100 = "com.agraabhi.drop.ach.clean100"

        var id: String { rawValue }
    }

    private(set) var isAuthenticated = false

    /// Best score that couldn't be submitted yet (authentication still resolving
    /// or absent). Flushed the moment authentication lands, so the first game
    /// over after launch isn't silently dropped when auth races the run.
    private var pendingScore = 0

    /// Achievements already reported this install. GameCenter's server ignores
    /// re-reports, but without this local dedup every scoring event past a
    /// threshold re-fires the XPC/network call (3 per gap once past 100) — a
    /// battery/rate-limit problem, not a correctness one. Persisted so it
    /// survives relaunch.
    private static let reportedKey = "reportedAchievementIDs"
    private var reported: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: GameCenterManager.reportedKey) ?? [])

    /// A sign-in view controller GameKit asked us to show, deferred until the
    /// player opens the leaderboard. We never present it automatically on launch
    /// (see authenticate).
    private var pendingSignInVC: UIViewController?

    /// True when GameKit wants the player to sign in / finish setup.
    var hasPendingSignIn: Bool { pendingSignInVC != nil }

    /// Called once at launch. Authenticates silently. Crucially it does NOT
    /// present the sign-in sheet here: doing so drops a modal over the game on
    /// every launch, and an unconfigured or blocked sheet (e.g. before the app is
    /// set up in App Store Connect) leaves the player staring at a blank, frozen
    /// screen. We stash any sign-in VC and surface it only on demand, when the
    /// player taps the leaderboard — Game Center is a bonus, never a gate.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // GameKit does not guarantee this handler runs on the main thread.
            // Touching UIKit or state off-main is a device-only crash source
            // (GameKit is XPC-backed), so hop to main for all of it.
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.pendingSignInVC = self.isAuthenticated ? nil : viewController
                // Auth can land after a game over (it resolves async at launch);
                // submit the best score that was waiting on it.
                if self.isAuthenticated, self.pendingScore > 0 {
                    let score = self.pendingScore
                    self.pendingScore = 0
                    self.submit(score: score)
                }
            }
        }
    }

    /// If GameKit is waiting on a sign-in, present it now (player-initiated) and
    /// return true. Lets the trophy button double as a "sign in to Game Center"
    /// entry point without ever blocking launch. The VC reference is kept until
    /// authentication actually succeeds — GameKit won't necessarily hand us a
    /// fresh one, so consuming it on a cancelled sign-in would permanently kill
    /// the entry point for the rest of the session.
    @discardableResult
    func presentPendingSignIn(from presenter: UIViewController?) -> Bool {
        guard let presenter, let vc = pendingSignInVC else { return false }
        guard vc.presentingViewController == nil else { return true }   // already up
        presenter.present(vc, animated: true)
        return true
    }

    /// Submit a score. Stashed and retried on auth if not authenticated yet.
    func submit(score: Int) {
        guard score > 0 else { return }
        guard isAuthenticated else {
            pendingScore = max(pendingScore, score)
            return
        }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [Self.leaderboardID]) { _ in }
    }

    /// Report an achievement as fully earned (100%). Best-effort — deduped
    /// locally (see `reported`) so repeat calls from the score loop are free.
    /// On a network failure the ID is un-marked so a later event retries it.
    /// No-ops when not signed in (and does NOT mark reported, so it still fires
    /// once the player eventually signs in).
    func report(_ achievement: Achievement) {
        guard isAuthenticated, !reported.contains(achievement.id) else { return }
        reported.insert(achievement.id)
        UserDefaults.standard.set(Array(reported), forKey: Self.reportedKey)
        let a = GKAchievement(identifier: achievement.id)
        a.percentComplete = 100
        a.showsCompletionBanner = true
        GKAchievement.report([a]) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.reported.remove(achievement.id)
                UserDefaults.standard.set(Array(self.reported), forKey: Self.reportedKey)
            }
        }
    }

    /// Present the standard Game Center leaderboard UI, if signed in.
    func showLeaderboard(from presenter: UIViewController?) {
        guard isAuthenticated, let presenter else { return }
        let vc = GKGameCenterViewController(leaderboardID: Self.leaderboardID,
                                            playerScope: .global,
                                            timeScope: .allTime)
        vc.gameCenterDelegate = LeaderboardDismisser.shared
        presenter.present(vc, animated: true)
    }
}

/// Tiny delegate that just dismisses the Game Center sheet on Done.
private final class LeaderboardDismisser: NSObject, GKGameCenterControllerDelegate {
    static let shared = LeaderboardDismisser()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
