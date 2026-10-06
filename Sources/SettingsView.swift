import SwiftUI

struct SettingsView: View {
    var onDone: () -> Void

    @State private var sensitivity = GameSettings.shared.sensitivity
    @State private var bounciness = GameSettings.shared.bounciness
    @State private var zenSpeed = GameSettings.shared.zenSpeed
    @State private var hapticsEnabled = GameSettings.shared.hapticsEnabled
    @State private var scoreSoundEnabled = GameSettings.shared.scoreSoundEnabled
    @State private var bounceSoundEnabled = GameSettings.shared.bounceSoundEnabled
    @State private var ballColorEnabled = GameSettings.shared.ballColorEnabled
    @State private var tutorialQueued = !GameSettings.shared.hasSeenTutorial
    @State private var showTipJar = false

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
                    Text("Tilt your \(GameSettings.deviceNoun) to steer. Sensitivity is how strongly the tilt moves the ball. Bounciness is how high it springs off floors. Changes apply on your next run.")
                }

                Section {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { _, v in GameSettings.shared.hapticsEnabled = v }
                    Toggle("Score Sound", isOn: $scoreSoundEnabled)
                        .onChange(of: scoreSoundEnabled) { _, v in GameSettings.shared.scoreSoundEnabled = v }
                    Toggle("Bounce Sound", isOn: $bounceSoundEnabled)
                        .onChange(of: bounceSoundEnabled) { _, v in GameSettings.shared.bounceSoundEnabled = v }
                    Toggle("Ball Color Changes", isOn: $ballColorEnabled)
                        .onChange(of: ballColorEnabled) { _, v in GameSettings.shared.ballColorEnabled = v }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Bounce Sound is a wood knock that gets louder the harder the ball lands. Score Sound plays soft blips as points come in. The ball changes look at score milestones, starting at 100; climb far enough and it becomes a whole different ball. Turn this off to stay red.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Zen Speed")
                            Spacer()
                            Text("\(Int(zenSpeed))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $zenSpeed,
                               in: GameSettings.minZenSpeed...GameSettings.maxZenSpeed,
                               step: 5) {
                            Text("Zen Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        }
                        .onChange(of: zenSpeed) { _, v in GameSettings.shared.zenSpeed = v }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Zen Mode")
                } footer: {
                    Text("Zen starts at this speed and speeds up very, very gently the longer you last, nothing like the regular mode's ramp. It keeps its own best score and never touches the Game Center leaderboard.")
                }

                Section {
                    scoringRow("Every hole", detail: "+1 point")
                    scoringRow("Clean pass", detail: "Reach the next hole in one bounce or less")
                    scoringRow("Streak", detail: "From your 3rd clean pass in a row, each one earns extra: +1, then +2, then +3, and so on")
                    scoringRow("Streak ends", detail: "Touch a wall or bounce twice on the same floor")
                } header: {
                    Text("Scoring")
                } footer: {
                    Text("So 5 clean passes in a row score 1, 1, 2, 3, 4. That's 11 points instead of 5. Clean play is where big scores come from.")
                }

                Section {
                    Button {
                        showTipJar = true
                    } label: {
                        HStack {
                            Label("Support Development", systemImage: "cup.and.saucer.fill")
                                .foregroundStyle(.pink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("settings.tipJar")
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Drop is a free, independent arcade game with no ads and no tracking. Your best score stays on this device.")
                        Text("Tips are optional one-time purchases through Apple. They unlock nothing and keep development going.")
                    }
                    .padding(.top, 8)
                }

                Section {
                    Link(destination: URL(string: "https://apps.apple.com/app/bruce-workout-tracker/id6770409619")!) {
                        appRow("Bruce", subtitle: "Workout tracker", image: "BruceIcon")
                    }
                    Link(destination: URL(string: "https://apps.apple.com/app/osho-talks-audio-discourses/id6774409039")!) {
                        appRow("Osho Talks", subtitle: "Audio discourses", image: "OshoIcon")
                    }
                } header: {
                    Text("My Other Apps")
                }

                Section {
                    LabeledContent("Version", value: version)
                    Button(tutorialQueued ? "Shows When You Next Tap Play" : "Show How to Play") {
                        GameSettings.shared.hasSeenTutorial = false
                        tutorialQueued = true
                    }
                    .disabled(tutorialQueued)
                }
            }
            .sheet(isPresented: $showTipJar) { TipJarView() }
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

    /// A row for another app: bundled icon, name + one-liner, App Store arrow.
    /// The icons are the only bundled images in the project (everything else is
    /// drawn at runtime) — other apps' icons can't be synthesized.
    private func appRow(_ title: String, subtitle: String, image: String) -> some View {
        HStack(spacing: 12) {
            Image(image)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
