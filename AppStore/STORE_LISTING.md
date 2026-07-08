# Drop — App Store Listing (v1.0)

Copy-paste reference for the App Store Connect listing fields. Character counts noted where limits apply.

## App Name
`Drop`  (4 / 30)

## Subtitle  (max 30)
**Minimalist reflex arcade game**  (29 / 30)

Alternates, if you prefer:
- `Thread the ball through gaps`  (28 / 30)
- `Fall, steer, keep the streak`  (28 / 30)

## Promotional Text  (max 170)
A glossy red ball, floors scrolling up, one gap in each. Tilt or tap to steer through. It starts gentle, then speeds up. Free, no ads.  (133 / 170)

## Description
Drop is a simple reflex game. A red ball falls, wooden floors scroll up past it, and each floor has one gap. Your job is to steer the ball into the gap before the floor pushes it to the top of the screen. It starts slow and gets faster the longer you last.

Reach a gap in a single clean drop, no wall hits and no extra bounces, and it counts as a clean pass. String three clean passes together and a streak bonus kicks in, adding more points on every clean pass after that. Hit a wall or bounce twice and the streak resets. Your best score is saved on your device.

How to play: steer left or right by tilting your phone or tapping and holding either side of the screen. Sensitivity is in Settings if you want it slower.

Features:
- Steer by tilt or by touch, whichever you prefer
- Adjustable steering sensitivity
- Speed that ramps up the longer you survive
- Clean-pass streak bonus for scoring runs
- Adjustable ball bounciness
- Haptics that scale with impact speed
- Soft synthesized score and bounce sounds, each toggleable, no music
- Optional Game Center leaderboard, plays fine without it
- Free, no ads, no in-app purchases, no tracking

Made by one person. If you hit a bug or have an idea, open an issue on GitHub.

## Keywords  (max 100, comma-separated, no spaces)
`arcade,reflex,ball,tilt,gap,minimalist,reaction,gravity,tap,steer,leaderboard,casual,timing,onehand,falling`  (97 / 100)

## What's New (v1.0)
First release. Steer a falling ball through scrolling gaps, chase clean-pass streaks, and post your best to the Game Center leaderboard.

## Category
- Primary: Games — Arcade
- Secondary: Games — Action

## Age Rating
4+ (no objectionable content)

## URLs
- Support URL: `https://github.com/aagrawal207/drop/issues`
- Privacy Policy URL: `https://github.com/aagrawal207/drop/blob/<branch>/PRIVACY.md`
- Marketing URL: (optional — leave blank)

> ACTION BEFORE SUBMIT: The Drop repo is not published yet and PRIVACY.md is not hosted. Both URLs above must resolve (HTTP 200) before you submit, or App Review rejects on a broken privacy-policy / support link. If you host the policy elsewhere (gist, personal site), update both fields to match. Confirm the repo's default branch name (`mainline` vs `main`) in the blob URL.

## Copyright
`2026 Abhishek Agrawal`

## App Privacy (Data Collection)
- Select **Data Not Collected** — with one nuance below for Game Center.
- The app stores only your high score and settings locally in UserDefaults; nothing is sent to the developer or any third party.
- No analytics, no crash reporting, no advertising SDKs, no third-party SDKs — Apple frameworks only.
- Game Center: if you want to be strict, declare **Identifiers → User ID** (the Game Center player ID, only when signed in), **not linked to identity**, **not used for tracking**, purpose **App Functionality**. See the submission guide for the exact buckets.

## Tracking / IDFA
- App Tracking Transparency: not used (no tracking, no IDFA access).
- IDFA answer in App Store Connect: **No.**

## Export Compliance
- `ITSAppUsesNonExemptEncryption = NO` is already set in the build, so uploads skip the encryption questionnaire. Uses only standard HTTPS / OS crypto — qualifies for exemption. Nothing to file.

## Game Center
- One global leaderboard, ID `com.agraabhi.drop.highscore` (Classic, all-time, global scope).
- Fully playable signed out; the trophy button then shows only the local best. Game Center handles player identity; that is the only identity data involved and it is managed by iOS, not stored by the app.

## Fixed-config reference
- Bundle ID: `com.agraabhi.drop`
- Deployment target: iOS 17.0+
- Orientation: Portrait only
- Price: Free — no ads, no in-app purchases
