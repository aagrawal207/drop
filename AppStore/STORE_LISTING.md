# Drop: App Store Listing (v1.2)

Mirrors what is in App Store Connect. The source of truth for `asc metadata push` is
`AppStore/metadata/` (app-info and version JSON); keep this file in sync with it.

## App Name  (max 30)
`Drop: Falling Ball Tilt Game`  (28 / 30). The on-device name stays `Drop`.

## Subtitle  (max 30)
`Endless reflex arcade, no ads`  (29 / 30)

## Keywords  (max 100, comma-separated, no spaces)
`offline,bounce,gravity,gap,hole,dodge,zen,relax,skill,reaction,casual,steer,motion,highscore,simple`  (99 / 100)

Words already in the name or subtitle (drop, falling, ball, tilt, game, endless,
reflex, arcade, ads) are indexed from there, so they are not repeated here.

## Promotional Text  (max 170)
Tilt your phone to steer a falling ball through the gaps. Chain clean drops for streak bonuses and climb the leaderboard. Free, offline, no ads.  (144 / 170)

## Description
Drop is a simple, endless reflex game. A red ball falls, wooden floors scroll up past it, and each floor has one gap. Tilt your phone to steer the ball into the gap before the floor pushes it off the top of the screen. It starts slow and gets faster the longer you last.

Reach a gap in a single clean drop, with no wall hits and no extra bounces, and it counts as a clean pass. String three clean passes together and a streak bonus kicks in, adding more points on every clean pass after that. Hit a wall or bounce twice and the streak resets.

New to it? A quick tutorial shows you how to tilt before your first run. Sensitivity is in Settings if the ball feels too quick.

Prefer something calmer? Zen mode starts at a speed you pick and only speeds up very gently, with its own best score.

Features:
- Tilt to steer, one-handed and simple
- Two modes: ranked play that speeds up, and relaxing Zen mode
- Clean-pass streak bonus for big scores
- The ball transforms as you climb: basketball at 100, baseball at 500, soccer ball at 1000 and more
- Game Center leaderboard, optional, plays fine without signing in
- Haptics and a wood-knock bounce sound that follow how hard you land
- Adjustable sensitivity and bounciness
- Works offline
- Free, no ads, no in-app purchases, no tracking

Made by one person. If you hit a bug or have an idea, open an issue on GitHub.

## What's New (v1.2)
- Tilt is now the way to steer. Touch steering is gone, so taps never fight your tilt mid-run.
- A quick tutorial shows how to play before your first run. Replay it any time from Settings.
- Game over screen is easier to read.

## Screenshots (6.9", `APP_IPHONE_67` set)
`AppStore/screenshots/01-streak.png` … `05-settings.png`, 1320 × 2868, captured from the
1.2 build on the iPhone 18 Pro Max simulator with `UITests/ScreenshotBot.swift`.

## Game Center
Leaderboard `com.agraabhi.drop.highscore`, shown as "High Score" (en-US, no suffix).
Its first version ships in the same review submission as app version 1.2.

## URLs
- Support: https://github.com/aagrawal207/drop/issues
- Privacy: https://github.com/aagrawal207/drop/blob/main/PRIVACY.md
