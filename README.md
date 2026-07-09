# Drop

A minimalist arcade reflex game for iOS. A glossy red ball falls; wooden floors scroll up past it, each with a single gap. Steer the ball through the gaps before the floors push it off the top. It starts gentle and gets faster the longer you last.

Built with SpriteKit, Core Haptics, GameKit, and a bit of procedural audio. No third-party dependencies.

## Play

- **Steer** by tilting the device or by tapping/holding the left or right half of the screen.
- **Clean pass**: reach a gap in a single drop, no wall hits or extra bounces.
- **Streak bonus**: three clean passes in a row start a growing bonus (+1, then +2, then +3) on each further clean pass. Hitting a wall or bouncing twice resets it.
- **Zen mode** holds a constant speed you pick in Settings, with its own local best. Ranked is the mode that speeds up and feeds the leaderboard.
- Best score is saved on the device. An optional Game Center leaderboard is there if you sign in; the game plays fully without it.

## Build

The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonatan/xcodegen) (`brew install xcodegen`):

```bash
xcodegen generate
xcodebuild -project FallingBall.xcodeproj -scheme FallingBall \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

The generated `FallingBall.xcodeproj` and `FallingBall.entitlements` are not tracked, so run `xcodegen generate` after cloning.

- Swift, SpriteKit, iOS 17+
- Portrait only
- Bundle ID: `com.agraabhi.drop`

## Project layout

```
Sources/          game code (scene, textures, haptics, sound, settings, Game Center)
AppStore/         store listing, submission guide, screenshots
PRIVACY.md        privacy policy
project.yml       xcodegen project definition
tools/            icon generator
```

## Privacy

Drop collects nothing. Everything it saves stays on your device. See [PRIVACY.md](PRIVACY.md).

## Support

Bug reports and ideas: [open an issue](https://github.com/aagrawal207/drop/issues).
