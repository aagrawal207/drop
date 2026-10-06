# AGENTS.md

iOS arcade game "Drop" (SpriteKit, Swift, iOS 17+, iPhone and iPad; portrait-only on iPhone). No third-party dependencies, no unit-test target, no CI, no lint config. `FallingBallUITests` holds screenshot/acceptance UI tests.

## Build

The Xcode project is **generated** — `FallingBall.xcodeproj` and `FallingBall.entitlements` are gitignored. Never edit the `.xcodeproj`; edit `project.yml` and regenerate:

```bash
xcodegen generate   # required after cloning AND after adding/removing source files
xcodebuild -project FallingBall.xcodeproj -scheme FallingBall \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Verification = a clean `xcodebuild`. There are no unit tests to run.

Bundle ID must stay `com.agraabhi.drop` — the old `com.agraabhi.FallingBall` is claimed by a different team and would break the Game Center App ID (see comment in project.yml).

## Architecture

- `GameScene.swift` (~900 lines) is the whole game: a private `GameState` enum state machine (menu/playing/paused/gameOver) with overlays parented to the camera. Two modes: `.ranked` (ramping speed, Game Center) and `.zen` (player-chosen speed with a deliberately glacial ramp, local best only).
- Physics inversion: the world is stationary, floors are static bodies, and the **camera descends** — floors only *appear* to rise. Don't "fix" this by moving floors.
- `GameViewController` is a UIKit host; Settings and Scores are SwiftUI sheets via `UIHostingController`.
- Everything is procedural — no bundled assets: sounds are synthesized PCM buffers (`SoundManager`), textures are drawn at runtime (`WoodTexture`, `BallTexture`). Adding an asset file is a design departure.
- `GameSettings` is a UserDefaults wrapper read live each frame by the scene, so settings changes apply immediately without plumbing.

## Gotchas (hard-earned, don't regress)

- **`preStepVelocity`**: ball velocity is sampled at the top of `update()` because by the time `didBegin(contact:)` fires, the solver has often already reflected it. Impact-driven haptics/sounds must use this, not the live body velocity.
- **UserDefaults legacy key**: `rankedBest` is stored under the key `"highScore"` for continuity with existing installs. Never rename the key.
- **`v == 0` means "never set"** pattern in `GameSettings` doubles (`sensitivity`, `bounciness`, `zenSpeed`) — safe only because valid ranges exclude 0. Prefer `object(forKey:) == nil` for new settings.
- **Game Center is never a gate**: `authenticate()` deliberately does NOT present the sign-in sheet at launch; the pending VC is stashed and shown only when the player taps the trophy. Keep it that way.
- **iPad letterboxes a fixed field**: on iPad the scene is a fixed 600×860 portrait field with `.aspectFit`, and `GameViewController` sizes the SKView to fit it over a walnut backdrop. iPad multitasking requires all four orientations and resizable windows, while physics needs fixed coordinates; don't switch iPad to `.resizeFill`. `TARGETED_DEVICE_FAMILY` lives at the *target* level in project.yml (xcodegen overrides a project-level value).
- **Tilt follows interface orientation**: `startMotion` picks the accelerometer axis from the window scene's orientation, because iPad rotates. Horizontal speed scales with field width above 440pt, so iPhones are unaffected.
- **Debug-only test hooks**: `-uiTestTouchSteering` (hold a screen half) and `-uiTestAutopilot` / `-uiTestAutopilotUntil N` (steer to the next gap) exist only in Debug builds, so simulators without an accelerometer can play. Scene buttons are accessibility elements; UI tests tap them by label.
- **Tips are In-App Purchase only**: App Review rejected an external donation link. `TipJarService` (StoreKit 2, consumables `com.agraabhi.drop.tip.*`) is ported from Howzat; tips unlock nothing.
- **App lifecycle workarounds** in `GameViewController` are deliberate: auto-pause on `didEnterBackground` (not `willResignActive` — that fires for Control Center and the Game Center banner), audio/haptic engines rebuilt on `willEnterForeground`, and `SKView.isPaused = false` forced on `didBecomeActive` because system overlays freeze the render loop. Don't simplify these.
- GameKit's `authenticateHandler` is not guaranteed on the main thread — all UIKit/state work in `GameCenterManager` hops to main.
- The Game Center leaderboard ID (`com.agraabhi.drop.highscore` in `GameCenterManager`) must match App Store Connect exactly. Achievements were deliberately removed in 1.1; don't reintroduce them.

## Conventions

- Comment style: explanatory "why" comments are dense and intentional throughout — match this when editing.
- UI in the scene is built from `SKLabelNode`/`SKShapeNode` parented to the camera; buttons are hit-tested via `frame.insetBy(dx:dy:)` in `touchesBegan`.
