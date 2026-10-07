import SwiftUI

/// Local scores + stats sheet shown by the trophy button. Always works offline
/// (shows on-device bests and lifetime stats). Offers the Game Center global
/// leaderboard only when the player is actually signed in — otherwise that entry
/// is hidden, so the button is never a dead tap.
struct ScoresView: View {
    var gameCenterAvailable: Bool
    var onShowGameCenter: () -> Void
    var onDone: () -> Void

    private let settings = GameSettings.shared
    private let records = RunRecords.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    bestRow(title: "Ranked Best",
                            icon: "trophy.fill", tint: .orange,
                            score: settings.rankedBest,
                            duration: settings.rankedBestDuration)
                    bestRow(title: "Zen Best",
                            icon: "leaf.fill", tint: .green,
                            score: settings.zenBest,
                            duration: settings.zenBestDuration)
                } header: {
                    Text("Best Scores")
                } footer: {
                    Text("Ranked is the classic speed-up mode and the only one that counts on the global leaderboard. Zen starts at a speed you choose and climbs only very gently. Times show how long that best run lasted.")
                }

                if hasTopRuns {
                    Section {
                        topRunsRow(title: "Ranked", icon: "trophy.fill", tint: .orange, mode: .ranked)
                        topRunsRow(title: "Zen", icon: "leaf.fill", tint: .green, mode: .zen)
                    } header: {
                        Text("Top Runs")
                    }
                }

                Section {
                    statRow("Total time played", value: longDuration(settings.totalTimePlayed))
                    statRow("Clean passes", value: "\(settings.totalCleanPasses)")
                } header: {
                    Text("Lifetime")
                }

                if gameCenterAvailable {
                    Section {
                        Button(action: onShowGameCenter) {
                            Label("View Global Leaderboard", systemImage: "globe")
                        }
                    } footer: {
                        Text("Compare your ranked best with players worldwide via Game Center.")
                    }
                } else {
                    Section {
                        Text("Sign in to Game Center in the Settings app to compete on the global leaderboard.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func bestRow(title: String, icon: String, tint: Color,
                         score: Int, duration: Double) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(tint)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(score)")
                    .font(.title3.bold())
                    .monospacedDigit()
                if score > 0 && duration > 0 {
                    Text("in \(shortDuration(duration))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var hasTopRuns: Bool {
        RunMode.allCases.contains { !records.topScores(for: $0).isEmpty }
    }

    @ViewBuilder
    private func topRunsRow(title: String, icon: String, tint: Color, mode: RunMode) -> some View {
        let top = records.topScores(for: mode)
        if !top.isEmpty {
            let deepest = records.deepestFloor(for: mode)
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .foregroundStyle(tint)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(top.map(String.init).joined(separator: "  "))
                        .monospacedDigit()
                    if deepest > 0 {
                        Text("Deepest: \(deepest) \(deepest == 1 ? "floor" : "floors")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// "1m 23s" style for a single run.
    private func shortDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t)s" : "\(t / 60)m \(t % 60)s"
    }

    /// "2h 5m" / "5m" style for a lifetime total.
    private func longDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}
