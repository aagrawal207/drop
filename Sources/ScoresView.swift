import SwiftUI

/// Local scores sheet shown by the trophy button. Always works offline (shows
/// the on-device best). Offers the Game Center global leaderboard only when the
/// player is actually signed in — otherwise that entry is hidden, so the button
/// is never a dead tap.
struct ScoresView: View {
    var gameCenterAvailable: Bool
    var onShowGameCenter: () -> Void
    var onDone: () -> Void

    private var best: Int { UserDefaults.standard.integer(forKey: "highScore") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Best Score", systemImage: "trophy.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("\(best)")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text("Your best is saved on this device.")
                }

                if gameCenterAvailable {
                    Section {
                        Button(action: onShowGameCenter) {
                            Label("View Global Leaderboard", systemImage: "globe")
                        }
                    } footer: {
                        Text("Compare your best with players worldwide via Game Center.")
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
}
