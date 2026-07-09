import Foundation

/// Tiny UserDefaults-backed store shared between the SwiftUI settings sheet and
/// the SpriteKit scene. The scene reads these each frame / on demand, so changes
/// take effect immediately.
final class GameSettings {
    static let shared = GameSettings()

    private enum Key {
        static let sensitivity = "steerSensitivity"
        static let haptics = "hapticsEnabled"
        static let bounciness = "ballBounciness"
        static let scoreSound = "scoreSoundEnabled"
        static let bounceSound = "bounceSoundEnabled"
        static let ballColor = "ballColorEnabled"
        static let zenSpeed = "zenSpeed"
        // Stats (kept separate from the legacy "highScore" key, which stays the
        // ranked best for continuity with existing installs).
        static let rankedBest = "highScore"
        static let rankedBestDuration = "rankedBestDuration"
        static let zenBest = "zenBest"
        static let zenBestDuration = "zenBestDuration"
        static let totalTimePlayed = "totalTimePlayed"
        static let totalCleanPasses = "totalCleanPasses"
    }

    /// 0.5 (calm) … 2.0 (twitchy). New players default to the top of the range —
    /// the ball feels responsive out of the box; they can dial it back if it's
    /// too twitchy.
    var sensitivity: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Key.sensitivity)
            return v == 0 ? Self.defaultSensitivity : v   // 0 means "never set"
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.sensitivity) }
    }

    /// Ball restitution: 0.35 (soft, dead) … 0.80 (springy). 0.55 is the default,
    /// tuned "lively but believable" feel.
    var bounciness: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Key.bounciness)
            return v == 0 ? Self.defaultBounciness : v   // 0 means "never set"
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.bounciness) }
    }

    /// Defaults to ON. `object(forKey:) == nil` distinguishes "never set" from
    /// an explicit false.
    var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.haptics) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.haptics) }
    }

    /// Sound when the score goes up. Defaults ON.
    var scoreSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.scoreSound) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.scoreSound) }
    }

    /// Sound when the ball bounces off a floor or wall. Defaults ON.
    var bounceSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.bounceSound) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.bounceSound) }
    }

    /// Whether the ball changes colour as the score climbs. Defaults ON. When
    /// off, the ball stays the classic red for the whole run.
    var ballColorEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.ballColor) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.ballColor) }
    }

    /// Zen-mode descent speed the player picks, in points/sec. Constant for the
    /// whole run (no ramp). Defaults to a calm value.
    var zenSpeed: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Key.zenSpeed)
            return v == 0 ? Self.defaultZenSpeed : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.zenSpeed) }
    }

    // MARK: - Stats (separate ranked vs. zen bests, plus lifetime totals)

    /// Best score in ranked (Normal) mode — the only score that feeds Game Center.
    var rankedBest: Int {
        get { UserDefaults.standard.integer(forKey: Key.rankedBest) }
        set { UserDefaults.standard.set(newValue, forKey: Key.rankedBest) }
    }
    /// How long the ranked-best run lasted, in seconds.
    var rankedBestDuration: Double {
        get { UserDefaults.standard.double(forKey: Key.rankedBestDuration) }
        set { UserDefaults.standard.set(newValue, forKey: Key.rankedBestDuration) }
    }
    /// Best score in Zen mode — never submitted to Game Center (self-set speed).
    var zenBest: Int {
        get { UserDefaults.standard.integer(forKey: Key.zenBest) }
        set { UserDefaults.standard.set(newValue, forKey: Key.zenBest) }
    }
    var zenBestDuration: Double {
        get { UserDefaults.standard.double(forKey: Key.zenBestDuration) }
        set { UserDefaults.standard.set(newValue, forKey: Key.zenBestDuration) }
    }
    /// Lifetime seconds spent in a live game (both modes).
    var totalTimePlayed: Double {
        get { UserDefaults.standard.double(forKey: Key.totalTimePlayed) }
        set { UserDefaults.standard.set(newValue, forKey: Key.totalTimePlayed) }
    }
    /// Lifetime count of clean passes (ranked mode), for the achievement.
    var totalCleanPasses: Int {
        get { UserDefaults.standard.integer(forKey: Key.totalCleanPasses) }
        set { UserDefaults.standard.set(newValue, forKey: Key.totalCleanPasses) }
    }

    static let minSensitivity = 0.5
    static let maxSensitivity = 2.0
    static let defaultSensitivity = 2.0

    static let minBounciness = 0.35
    static let maxBounciness = 0.80
    static let defaultBounciness = 0.55

    static let minZenSpeed = 60.0
    static let maxZenSpeed = 260.0
    static let defaultZenSpeed = 110.0
}
