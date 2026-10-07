import Foundation

/// How a finished run went, as far as the rating and tip prompts care.
struct RunSummary {
    let score: Int
    let duration: TimeInterval
    let isNewBest: Bool

    /// Asking after a quick death would catch the player frustrated.
    var endedWell: Bool { (isNewBest && score > 0) || duration >= EngagementPolicy.goodRunDuration }
}

/// Decides when Drop may ask for an App Store rating or show the quiet tip line.
/// Pure Foundation with injected defaults and clock, so the rules can be exercised off-device.
final class EngagementPolicy {
    // Rating: either plenty of play, or a long-kept install that is still being played.
    static let engagedRuns = 20
    static let engagedDays = 3
    static let loyalInstallAge: TimeInterval = 30 * 86_400
    static let loyalDays = 2
    static let minimumRunsToAsk = 3
    static let reviewInterval: TimeInterval = 120 * 86_400

    // Tip line: established players only, spaced out, and it gives up after a few showings.
    static let tipRuns = 30
    static let tipDays = 5
    static let tipInterval: TimeInterval = 21 * 86_400
    static let tipMaxShowings = 6

    static let goodRunDuration: TimeInterval = 45

    private enum Key {
        static let firstSeen = "engagement.firstSeen"
        static let completedRuns = "engagement.completedRuns"
        static let playDays = "engagement.playDays"
        static let lastPlayDay = "engagement.lastPlayDay"
        static let reviewVersion = "engagement.reviewVersion"
        static let reviewDate = "engagement.reviewDate"
        static let tipShownDate = "engagement.tipShownDate"
        static let tipShownCount = "engagement.tipShownCount"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .current }) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    /// Installs that predate this tracking start their 30-day clock at the update,
    /// because nothing earlier records when they were installed.
    func recordLaunch() {
        if defaults.object(forKey: Key.firstSeen) == nil {
            defaults.set(now(), forKey: Key.firstSeen)
        }
    }

    func recordCompletedRun() {
        recordLaunch()
        defaults.set(completedRuns + 1, forKey: Key.completedRuns)
        let today = calendar().startOfDay(for: now())
        let last = defaults.object(forKey: Key.lastPlayDay) as? Date
        // A clock set backwards must not mint extra play days.
        if last.map({ today > $0 }) ?? true {
            defaults.set(playDays + 1, forKey: Key.playDays)
            defaults.set(today, forKey: Key.lastPlayDay)
        }
    }

    var completedRuns: Int { defaults.integer(forKey: Key.completedRuns) }
    var playDays: Int { defaults.integer(forKey: Key.playDays) }

    func canRequestReview(version: String) -> Bool {
        let date = now()
        guard completedRuns >= Self.minimumRunsToAsk,
              defaults.string(forKey: Key.reviewVersion) != version else { return false }
        if let last = defaults.object(forKey: Key.reviewDate) as? Date,
           date < last || date.timeIntervalSince(last) < Self.reviewInterval { return false }

        let engaged = completedRuns >= Self.engagedRuns && playDays >= Self.engagedDays
        var loyal = false
        if let first = defaults.object(forKey: Key.firstSeen) as? Date {
            loyal = date.timeIntervalSince(first) >= Self.loyalInstallAge && playDays >= Self.loyalDays
        }
        return engaged || loyal
    }

    /// Record before asking: iOS may silently skip the sheet, and either way this version is spent.
    func recordReviewRequest(version: String) {
        defaults.set(version, forKey: Key.reviewVersion)
        defaults.set(now(), forKey: Key.reviewDate)
    }

    /// Someone who has already tipped has answered the question; the line never returns for them.
    func canShowTipLine(hasTipped: Bool) -> Bool {
        let shown = defaults.integer(forKey: Key.tipShownCount)
        guard !hasTipped, completedRuns >= Self.tipRuns, playDays >= Self.tipDays,
              shown < Self.tipMaxShowings else { return false }
        guard let last = defaults.object(forKey: Key.tipShownDate) as? Date else { return true }
        let date = now()
        return date >= last && date.timeIntervalSince(last) >= Self.tipInterval
    }

    func recordTipLineShown() {
        defaults.set(defaults.integer(forKey: Key.tipShownCount) + 1, forKey: Key.tipShownCount)
        defaults.set(now(), forKey: Key.tipShownDate)
    }
}
