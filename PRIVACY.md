# Privacy Policy for Drop

Last updated: July 2026

## The short version

Drop is a free arcade game. It doesn't collect your data, doesn't show ads, and doesn't track you. Everything it saves — your high score and your settings — stays on your device. The only two things that ever reach outside the app are Apple's Game Center, if you choose to use it, and the "Support Development" link, which opens a web page in Safari.

The rest of this page fills in the details.

## What's stored on your device

Drop saves a few things locally, using iOS's standard UserDefaults:

- Your high score.
- Your settings: steering sensitivity, bounciness, and the haptics and sound toggles.

Nothing else is stored, and none of it leaves your device (except your score, if you opt into Game Center — see below). There's no iCloud sync, so your high score lives only on the device where you set it.

## Game Center

Drop uses Apple's Game Center for an optional global leaderboard (leaderboard ID `com.agraabhi.drop.highscore`). If you sign in to Game Center, your score can be submitted to that leaderboard, and your Game Center identity is handled entirely by Apple.

If you don't sign in, the trophy button just shows your local best. The game is fully playable without Game Center.

Game Center is Apple's service, so how it handles your player identity is covered by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/), not this one.

## Motion (accelerometer)

You can steer the ball by tilting your device. When you do, Drop reads the accelerometer to move the ball left and right. That motion data is used in the moment and never stored, never sent anywhere, and never leaves your device. You can also steer by touch instead, if you prefer.

## Network access

Drop itself makes no network calls. The only network activity involves:

- Game Center, when you use the leaderboard. That traffic is handled by iOS, not by Drop.
- The "Support Development" link, which opens `buymeacoffee.com` in Safari. Drop sends nothing to that site; it just hands the link to your browser. Anything that happens after that is between you and Buy Me a Coffee.

## Analytics and tracking

None. No analytics, no crash reporting, no advertising SDKs, no tracking of any kind.

## Third-party services

None beyond Apple's own frameworks. Drop uses no third-party SDKs or libraries. There's no account, no login, and no sign-up.

## Children's privacy

Drop is rated 4+ and contains no objectionable content. Since it collects no personal data from anyone, it collects none from children either.

## Deleting your data

Your high score and settings live in the app. Deleting Drop removes them from your device.

Your Game Center leaderboard entry is managed through Game Center. You can remove it in your device's Game Center settings, or by contacting Apple.

## Changes to this policy

If this policy changes, the updated version will be posted here with a new "Last updated" date. Drop doesn't collect anything, so changes here should be rare.

## Contact

Questions? Open an issue on GitHub: [github.com/aagrawal207/drop/issues](https://github.com/aagrawal207/drop/issues)
