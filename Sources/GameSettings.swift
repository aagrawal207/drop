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

    static let minSensitivity = 0.5
    static let maxSensitivity = 2.0
    static let defaultSensitivity = 2.0

    static let minBounciness = 0.35
    static let maxBounciness = 0.80
    static let defaultBounciness = 0.55
}
