# Submitting Drop to the App Store

A checklist for getting Drop live. Work through it top to bottom; each section assumes the one before it is done.

## The short version

Drop is a free arcade game — no ads, no purchases, no accounts, no tracking. Most of the App Store Connect flow is quick because there's so little to declare. The two parts that take real attention are the Game Center leaderboard wiring and the App Privacy answers, so slow down for those.

One naming note before you start: the Xcode project and scheme are still called `FallingBall` (the entitlements file is `FallingBall.entitlements`), but the app ships as **Drop** — display name `Drop`, bundle ID `com.agraabhi.drop`. That mismatch is fine; just don't be thrown by it when you archive.

## Prerequisites

- A paid Apple Developer Program membership (99 USD/year). Free accounts can't publish.
- Xcode 15 or later (Drop targets iOS 17.0+).
- A physical iPhone running iOS 17 or later for testing. The tilt controls and Core Haptics don't work in the Simulator, and Game Center sign-in is easier to test on device.
- Signing sorted in Xcode (Automatic signing under Signing & Capabilities is fine).
- A place to host the privacy policy. `PRIVACY.md` lives in the project root; push it to a public GitHub repo and use the blob URL, or paste it into a gist. You need a stable public URL before you start the listing.

A note on Info.plist: this project doesn't ship a hand-edited `Info.plist`. It's generated at build time from the build settings in `project.yml` (`GENERATE_INFOPLIST_FILE: YES`, with the `INFOPLIST_KEY_*` entries). So confirm these settings, not a file:

- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` is `NO`.
- `INFOPLIST_KEY_NSMotionUsageDescription` has a short reason string (currently: "Drop uses motion to let you steer the ball by tilting your device.").

Both are already in `project.yml`. If you regenerate the project with xcodegen, they carry over.

## App Store Connect setup

1. Sign in at appstoreconnect.apple.com.
2. Register the App ID first if it doesn't exist. Go to developer.apple.com → Certificates, Identifiers & Profiles → Identifiers, and create an App ID with the explicit bundle ID `com.agraabhi.drop`. Enable the **Game Center** capability on it (this has to happen before the leaderboard exists).
3. Back in App Store Connect, go to Apps → "+" → New App.
   - Platform: iOS
   - Name: `Drop`
   - Primary language: English (U.S.)
   - Bundle ID: `com.agraabhi.drop`
   - SKU: any stable internal string, e.g. `drop-ios-001`
   - User access: Full Access
4. Create it. You now have an app record with empty sections to fill in.

## App Information

- **Name:** Drop
- **Subtitle:** a plain one like "Minimalist reflex arcade game" (max 30 chars, optional)
- **Category:** Games (primary), Arcade (subcategory)
- **Content Rights:** you own all content; no third-party content
- **Age Rating:** work through the questionnaire honestly — no violence, no mature themes — lands at **4+**
- **Privacy Policy URL:** the public URL where you hosted `PRIVACY.md`. Required even for a game that collects almost nothing.
- **Price:** Free (Tier 0). No in-app purchases.

## App Privacy (data collection answers)

Answer for what the app actually does, not what a typical game does.

The only thing worth declaring is the Game Center player identifier, and only because it exists when a player is signed in. Everything Drop stores itself (high score, settings) lives in UserDefaults on the device and is not "collected" in Apple's sense.

Declare a single data type:

- **Identifiers → User ID** (the Game Center player ID)
  - Used to track you? **No.**
  - Linked to identity? **No** → select **Data Not Linked to You**.
  - Purpose: **App Functionality** (the leaderboard). Not analytics, not advertising.

Everything else is "No": no usage data, no diagnostics, no location, no contacts, no purchases, no browsing history, no health data.

Three-bucket summary:
- Data Used to Track You: **None**
- Data Linked to You: **None**
- Data Not Linked to You: **Identifiers (Game Center player ID, only when signed in)**

The accelerometer is used only to steer and never leaves the device, so it is not a data-collection item — it's covered by the `NSMotionUsageDescription` runtime prompt, not the privacy label.

## Screenshots

Required for the 6.9"/6.7" iPhone display; App Store Connect scales down for smaller devices. Four ready-made shots (1320×2868, portrait) are in `AppStore/screenshots/`:

1. `01-menu.png` — title screen
2. `02-gameplay.png` — ball mid-drop, score 7
3. `03-streak.png` — score 14 with the streak-bonus readout
4. `04-settings.png` — controls and feedback toggles

Upload them under the 6.9" display tab. No marketing frames — what's on screen is what players get.

## Description

See `AppStore/STORE_LISTING.md` for the full description, keywords, and promo text, all within character limits.

## Game Center setup

Do this in order.

1. **Enable the capability on the App ID** (done in the App Store Connect setup step). Regenerate provisioning profiles if you manage them manually; automatic signing handles it.
2. **Add the capability in Xcode.** Target → Signing & Capabilities → add **Game Center**. The entitlement is already declared in `FallingBall.entitlements` (`com.apple.developer.game-center: true`); this just makes Xcode and the profile agree.
3. **Create the leaderboard in App Store Connect.** App record → **Features → Game Center** → add a leaderboard:
   - Type: **Classic** (not recurring)
   - Reference name: anything readable, e.g. "High Score"
   - **Leaderboard ID:** `com.agraabhi.drop.highscore` — must match the code exactly (the `leaderboardID` constant in `GameCenterManager`)
   - Score format: Integer
   - Sort order: **High to Low**
   - Add an English localization with a display name like "High Score"
4. **Test on a device.** Install a dev build, sign into Game Center (ideally a sandbox tester account), play a run, confirm the score reaches the leaderboard. Also test the signed-out path: the trophy shows the local best and the game stays playable. Sandbox scores can take a few minutes to appear.

How sign-in works: the app authenticates silently at launch and never forces the sign-in sheet. GameKit's sheet only appears when you tap the trophy. So a reviewer without an account gets either the local best or a sign-in prompt — never a frozen modal. The leaderboard is a bonus, never a gate.

## Archive & Upload

1. Pick the **FallingBall** scheme (that's the project name; the app is still Drop) and set the destination to **Any iOS Device (arm64)**.
2. Bump the build number if re-uploading (`CURRENT_PROJECT_VERSION` in `project.yml`; `MARKETING_VERSION` is the user-facing version).
3. Product → Archive.
4. In the Organizer, select the archive → Distribute App → App Store Connect → Upload.
5. Let it validate and upload; it takes a few minutes to process before it shows under the version's Build section.
6. Back in App Store Connect, on the version page, select the processed build.

## Export Compliance

Because `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` is `NO`, App Store Connect won't ask the encryption question at upload. Drop uses no custom encryption — only HTTPS through Apple's frameworks (Game Center) and the Support link opening Safari, which is exempt. Nothing to file.

## Submit for Review

On the version page:

- **Version:** 1.0
- **What's New:** "First release." is fine.
- **Build:** the one you selected.
- **App Review Information:** your contact info; leave demo-account fields empty (no login needed); notes like "No account needed. Tilt or tap left/right to steer. Game Center leaderboard is optional and the game is fully playable without signing in."
- **Version Release:** manual or automatic, your call.

Then **Add for Review** / **Submit for Review**.

## Review timeline

Usually 24–48 hours, sometimes faster, occasionally longer around holidays or a major OS release. Watch the state change in App Store Connect.

## Common rejection reasons (and why Drop is mostly clear of them)

- **Privacy label doesn't match behavior.** The most common trap. Make sure the App Privacy answers say exactly what's above: Game Center identifier only, not linked, not tracking. Don't let a template pre-fill "usage data."
- **Broken or missing privacy policy URL.** Verify the hosted `PRIVACY.md` link actually loads before submitting.
- **Missing usage string for a permission.** Drop already sets `NSMotionUsageDescription`; make sure the string clearly says motion is for steering.
- **Crashes on launch or during review.** Test a release build on a real device first. Check both Game Center paths.
- **Placeholder or misleading screenshots.** Use real gameplay, portrait, correct resolution (the provided shots are fine).
- **Age rating mismatch.** 4+ is honest for Drop.
- **Game Center configured but not working.** Double-check the leaderboard ID matches exactly and that you tested a score posting on device.

Once it's approved and you flip it to release, Drop goes live. Watch GitHub Issues for the first bug reports.
