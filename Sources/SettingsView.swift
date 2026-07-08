import SwiftUI

struct SettingsView: View {
    var onDone: () -> Void

    @State private var sensitivity = GameSettings.shared.sensitivity
    @State private var bounciness = GameSettings.shared.bounciness
    @State private var hapticsEnabled = GameSettings.shared.hapticsEnabled
    @State private var scoreSoundEnabled = GameSettings.shared.scoreSoundEnabled
    @State private var bounceSoundEnabled = GameSettings.shared.bounceSoundEnabled

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Steering Sensitivity")
                            Spacer()
                            Text(String(format: "%.1f×", sensitivity))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $sensitivity,
                               in: GameSettings.minSensitivity...GameSettings.maxSensitivity,
                               step: 0.1) {
                            Text("Steering Sensitivity")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        }
                        .onChange(of: sensitivity) { _, newValue in
                            GameSettings.shared.sensitivity = newValue
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Bounciness")
                            Spacer()
                            Text(String(format: "%.2f", bounciness))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $bounciness,
                               in: GameSettings.minBounciness...GameSettings.maxBounciness,
                               step: 0.05) {
                            Text("Bounciness")
                        } minimumValueLabel: {
                            Image(systemName: "circle.fill").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.secondary)
                        }
                        .onChange(of: bounciness) { _, newValue in
                            GameSettings.shared.bounciness = newValue
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Sensitivity sets how strongly tilt and touch move the ball — lower is calmer, higher is twitchier. Bounciness sets how much the ball springs off floors. Takes effect on your next drop.")
                }

                Section {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { _, v in GameSettings.shared.hapticsEnabled = v }
                    Toggle("Score Sound", isOn: $scoreSoundEnabled)
                        .onChange(of: scoreSoundEnabled) { _, v in GameSettings.shared.scoreSoundEnabled = v }
                    Toggle("Bounce Sound", isOn: $bounceSoundEnabled)
                        .onChange(of: bounceSoundEnabled) { _, v in GameSettings.shared.bounceSoundEnabled = v }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Haptics buzz on bounces. Score Sound chimes as points rise — more for a streak bonus. Bounce Sound is a soft knock each time the ball lands.")
                }

                Section {
                    scoringRow("Clear a hole", detail: "+1 point")
                    scoringRow("Clean pass", detail: "Reach a hole in one drop — no wall, no extra bounces")
                    scoringRow("Streak bonus", detail: "3 clean passes in a row start a bonus: +1, then +2, +3… each next clean pass")
                    scoringRow("Streak breaks", detail: "Hitting a wall, or bouncing twice before a hole, resets the streak")
                } header: {
                    Text("Scoring")
                } footer: {
                    Text("Example: 5 clean passes in a row score 1, 1, 2 (+1), 3 (+2), 4 (+3) — 11 points instead of 5. Threading holes cleanly is where the big scores come from.")
                }

                Section {
                    Link(destination: URL(string: "https://buymeacoffee.com/aagrawal207")!) {
                        linkRow("Support Development", icon: "cup.and.saucer.fill", tint: .pink)
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Drop is a free, independent arcade game with no ads and no tracking. Your best score stays on this device.")
                        Text("Support keeps development going — new features, fixes, and upkeep. It's a voluntary thank-you, not a purchase, and unlocks nothing.")
                    }
                    .padding(.top, 8)
                }

                Section {
                    LabeledContent("Version", value: version)
                    LabeledContent("Controls", value: "Tilt & Touch")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func scoringRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func linkRow(_ title: String, icon: String, tint: Color) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(tint)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
