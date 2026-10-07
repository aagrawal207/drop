import Foundation

/// The scene's mode enum is file-private, so records key off their own.
enum RunMode: String, CaseIterable {
    case ranked
    case zen
}

/// What one finished run meant against the player's history, for game-over copy.
struct RunRecordResult {
    let score: Int
    let floors: Int
    /// Best before this run; the scene's own best capture must agree with it.
    let previousBest: Int
    /// 1-based place among the top scores after this run, nil when it missed the list.
    let rank: Int?
    let runCount: Int
    let isNewDeepest: Bool

    var message: String? {
        RunRecords.gameOverMessage(score: score, previousBest: previousBest, rank: rank, runCount: runCount)
    }
}

/// Per-mode top scores and deepest floor, so a run that misses the best still has a story.
/// Foundation-only with injected defaults, so the rules can be exercised off-device.
final class RunRecords {
    static let shared = RunRecords()
    static let topCount = 5

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ mode: RunMode, _ field: String) -> String { "runRecords.\(mode.rawValue).\(field)" }

    /// Legacy best keys; "highScore" is the ranked best and must never be renamed.
    private func legacyBestKey(_ mode: RunMode) -> String { mode == .ranked ? "highScore" : "zenBest" }

    /// Seeds from the legacy best once, before anything else writes, so existing players
    /// compare against their real record. Must run before the scene stores a new best.
    private func seedIfNeeded(_ mode: RunMode) {
        guard defaults.object(forKey: key(mode, "topScores")) == nil else { return }
        let best = defaults.integer(forKey: legacyBestKey(mode))
        defaults.set(best > 0 ? [best] : [Int](), forKey: key(mode, "topScores"))
        defaults.set(best > 0 ? 1 : 0, forKey: key(mode, "runCount"))
    }

    /// Highest run scores, descending, at most `topCount`.
    func topScores(for mode: RunMode) -> [Int] {
        seedIfNeeded(mode)
        return defaults.array(forKey: key(mode, "topScores")) as? [Int] ?? []
    }

    /// Most floors cleared in any single run of this mode; 0 until a run is recorded.
    func deepestFloor(for mode: RunMode) -> Int {
        seedIfNeeded(mode)
        return defaults.integer(forKey: key(mode, "deepestFloor"))
    }

    func runCount(for mode: RunMode) -> Int {
        seedIfNeeded(mode)
        return defaults.integer(forKey: key(mode, "runCount"))
    }

    @discardableResult
    func record(score: Int, floors: Int, mode: RunMode) -> RunRecordResult {
        var top = topScores(for: mode)
        let previousBest = top.first ?? 0
        var rank: Int?
        // Zero runs stay off the list so the Scores sheet never shows a row of zeros.
        if score > 0 {
            // Ties rank alongside the earlier run rather than below it.
            let index = top.firstIndex(where: { score >= $0 }) ?? top.count
            top.insert(score, at: index)
            if index < Self.topCount { rank = index + 1 }
            defaults.set(Array(top.prefix(Self.topCount)), forKey: key(mode, "topScores"))
        }

        let runs = runCount(for: mode) + 1
        defaults.set(runs, forKey: key(mode, "runCount"))

        let deepest = deepestFloor(for: mode)
        let isNewDeepest = floors > deepest
        if isNewDeepest { defaults.set(floors, forKey: key(mode, "deepestFloor")) }

        return RunRecordResult(score: score, floors: floors, previousBest: previousBest,
                               rank: rank, runCount: runs, isNewDeepest: isNewDeepest)
    }

    /// A new best returns nil because the score line already celebrates it. A place on the
    /// list is only worth saying once some run sits below it, or "2nd best" just means "worse".
    static func gameOverMessage(score: Int, previousBest best: Int, rank: Int?, runCount: Int) -> String? {
        guard score > 0, score <= best else { return nil }
        if score == best { return "Tied your best" }
        let gap = best - score
        if gap <= max(3, best / 10) { return "\(gap) short of your best" }
        if let rank, (2...topCount).contains(rank), runCount > rank {
            return "Your \(ordinal(rank)) best run"
        }
        return nil
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}
