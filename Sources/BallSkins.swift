import Foundation

/// Which ball the player wants: the in-run evolution through every tier, or one
/// unlocked tier held for the whole run.
enum BallSkinChoice: Equatable {
    case evolving
    case fixed(tier: Int)

    /// Ball shown on the menu and at the start of a run.
    var startTier: Int {
        switch self {
        case .evolving: return 0
        case .fixed(let tier): return tier
        }
    }

    /// Ball for a given score mid-run. Fixed skins never evolve.
    func tier(forScore score: Int) -> Int {
        switch self {
        case .evolving: return BallPalette.tierIndex(for: score)
        case .fixed(let tier): return tier
        }
    }

    var name: String {
        switch self {
        case .evolving: return "Evolving"
        case .fixed(let tier): return BallSkins.name(forTier: tier)
        }
    }
}

/// Ball skins unlocked by playing: a tier unlocks once any run in either mode
/// reaches its score, and stays unlocked. Tiers unlock in order, so the highest
/// tier reached is the whole state.
final class BallSkins {
    static let shared = BallSkins()

    private enum Key {
        static let highestTier = "ballSkinHighestTier"
        // -1 is Evolving; any other value is a fixed tier index.
        static let selection = "ballSkinSelection"
        // Legacy toggle owned by GameSettings, read only for migration.
        static let legacyColorEnabled = "ballColorEnabled"
        static let rankedBest = "highScore"
        static let zenBest = "zenBest"
    }

    private static let evolvingRaw = -1

    private static let names = [
        "Classic", "Basketball", "Gold", "Baseball", "Violet",
        "Soccer Ball", "Emerald", "Bowling Ball", "Magenta", "Black Hole",
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Seeded once at launch, before any run can raise the bests, so players
        // keep what they earned before skins existed and recordRun still diffs.
        if defaults.object(forKey: Key.highestTier) == nil {
            let best = max(defaults.integer(forKey: Key.rankedBest),
                           defaults.integer(forKey: Key.zenBest))
            defaults.set(BallPalette.tierIndex(for: best), forKey: Key.highestTier)
        }
    }

    static func name(forTier tier: Int) -> String {
        names.indices.contains(tier) ? names[tier] : "Ball"
    }

    static func unlockScore(forTier tier: Int) -> Int {
        BallPalette.tiers[tier].minScore
    }

    var highestTier: Int {
        let stored = defaults.integer(forKey: Key.highestTier)
        return min(max(0, stored), BallPalette.tiers.count - 1)
    }

    var unlockedTiers: [Int] { Array(0...highestTier) }

    func isUnlocked(_ tier: Int) -> Bool { tier >= 0 && tier <= highestTier }

    /// Records a finished run and returns the tiers it unlocked, lowest first.
    @discardableResult
    func recordRun(score: Int) -> [Int] {
        let previous = highestTier
        let reached = BallPalette.tierIndex(for: score)
        guard reached > previous else { return [] }
        defaults.set(reached, forKey: Key.highestTier)
        return Array((previous + 1)...reached)
    }

    /// A player who turned the old color toggle off and never picked a skin
    /// keeps the plain red ball they chose.
    var selection: BallSkinChoice {
        get {
            guard let raw = defaults.object(forKey: Key.selection) as? Int else {
                let legacyOff = (defaults.object(forKey: Key.legacyColorEnabled) as? Bool) == false
                return legacyOff ? .fixed(tier: 0) : .evolving
            }
            // A selection past the unlocked range can only come from tampered or
            // restored defaults; fall back rather than hand out a locked ball.
            if raw == Self.evolvingRaw || !isUnlocked(raw) { return .evolving }
            return .fixed(tier: raw)
        }
        set {
            switch newValue {
            case .evolving: defaults.set(Self.evolvingRaw, forKey: Key.selection)
            case .fixed(let tier): defaults.set(tier, forKey: Key.selection)
            }
        }
    }

    /// Evolving first, then every unlocked skin in tier order.
    var choices: [BallSkinChoice] {
        [.evolving] + unlockedTiers.map { .fixed(tier: $0) }
    }

    /// Advances and persists the selection, or returns nil when there is
    /// nothing to cycle to.
    func cycleSelection() -> BallSkinChoice? {
        let all = choices
        guard all.count > 1 else { return nil }
        let index = all.firstIndex(of: selection) ?? 0
        let next = all[(index + 1) % all.count]
        selection = next
        return next
    }
}
