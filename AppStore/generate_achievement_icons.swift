#!/usr/bin/env swift
// Renders the 6 Game Center achievement icons (1024x1024 opaque PNGs) in the
// game's own procedural style: dark walnut wood backdrop (WoodTexture.background),
// an oak plank with a gap (the core gameplay image), and the glossy ball
// (BallTexture.render) with the achievement's number on it, billiard style.
//
// Run:  swift AppStore/generate_achievement_icons.swift
// Out:  AppStore/achievements/<id>.png
//
// This is macOS tooling only; it ports the UIKit drawing in Sources/BallTexture.swift
// and Sources/WoodTexture.swift to AppKit. Keep the colour constants in sync with
// those files if the game's look ever changes.

import AppKit

let S: CGFloat = 1024
let outDir = "AppStore/achievements"

// MARK: - Wood (ported from WoodTexture.swift)

func drawGrain(_ ctx: CGContext, rect: CGRect,
               base: (CGFloat, CGFloat, CGFloat),
               streak: (CGFloat, CGFloat, CGFloat),
               highlight: (CGFloat, CGFloat, CGFloat),
               grainVertical: Bool) {
    ctx.setFillColor(red: base.0, green: base.1, blue: base.2, alpha: 1)
    ctx.fill(rect)
    var seed: UInt64 = grainVertical ? 0x9E3779B97F4A7C15 : 0xD1B54A32D192ED03
    func rnd() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
    }
    let span = grainVertical ? rect.width : rect.height
    let length = grainVertical ? rect.height : rect.width
    for _ in 0..<Int(span / 3) {
        let pos = rnd() * span
        let c = rnd() > 0.5 ? streak : highlight
        let alpha = 0.05 + rnd() * 0.18
        let thickness = 0.5 + rnd() * 2.0
        ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: alpha)
        var t: CGFloat = 0
        while t < length {
            let segLen = 12 + rnd() * 40
            let wobble = (rnd() - 0.5) * 3
            if grainVertical {
                ctx.fill(CGRect(x: rect.minX + pos + wobble, y: rect.minY + t,
                                width: thickness, height: segLen))
            } else {
                ctx.fill(CGRect(x: rect.minX + t, y: rect.minY + pos + wobble,
                                width: segLen, height: thickness))
            }
            t += segLen
        }
    }
}

func drawBackground(_ ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    drawGrain(ctx, rect: rect,
              base: (0.24, 0.15, 0.09), streak: (0.14, 0.08, 0.04),
              highlight: (0.34, 0.22, 0.13), grainVertical: true)
    // Vertical plank seams (plankWidth 84 in game; scaled up for icon size).
    let plankWidth: CGFloat = 205
    ctx.setFillColor(NSColor(white: 0, alpha: 0.28).cgColor)
    var x: CGFloat = plankWidth
    while x < S { ctx.fill(CGRect(x: x, y: 0, width: 5, height: S)); x += plankWidth }
    // Soft vignette so the circular crop reads with depth.
    let colors = [NSColor(white: 0, alpha: 0).cgColor,
                  NSColor(white: 0, alpha: 0.45).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0.62, 1]) {
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                               endCenter: CGPoint(x: S/2, y: S/2), endRadius: S * 0.72,
                               options: [])
    }
}

/// Oak plank with a centered gap, near the bottom: the game's core image.
func drawPlankWithGap(_ ctx: CGContext, y: CGFloat, height: CGFloat, gapWidth: CGFloat) {
    let gapMinX = (S - gapWidth) / 2, gapMaxX = (S + gapWidth) / 2
    for r in [CGRect(x: 0, y: y, width: gapMinX, height: height),
              CGRect(x: gapMaxX, y: y, width: S - gapMaxX, height: height)] {
        ctx.saveGState()
        ctx.clip(to: r)
        drawGrain(ctx, rect: r,
                  base: (0.62, 0.44, 0.26), streak: (0.42, 0.28, 0.15),
                  highlight: (0.78, 0.60, 0.38), grainVertical: false)
        // Bevel: bright top edge, dark bottom edge (bottom-left origin here).
        ctx.setFillColor(NSColor(white: 1, alpha: 0.18).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.maxY - 8, width: r.width, height: 8))
        ctx.setFillColor(NSColor(white: 0, alpha: 0.22).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 8))
        ctx.restoreGState()
    }
}

// MARK: - Ball (ported from BallTexture.swift)

struct BallColors { let lit, mid, shadow: NSColor }

let classicRed = BallColors(
    lit: NSColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1),
    mid: NSColor(red: 0.86, green: 0.16, blue: 0.14, alpha: 1),
    shadow: NSColor(red: 0.45, green: 0.04, blue: 0.05, alpha: 1))

func tinted(_ tint: NSColor) -> BallColors {
    let c = tint.usingColorSpace(.deviceRGB)!
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return BallColors(
        lit: NSColor(hue: h, saturation: max(0, s * 0.42),
                     brightness: min(1, b * 1.10 + 0.18), alpha: 1),
        mid: c,
        shadow: NSColor(hue: h, saturation: min(1, s * 1.05),
                        brightness: b * 0.34, alpha: 1))
}

let gold   = tinted(NSColor(red: 1.00, green: 0.80, blue: 0.12, alpha: 1))
let teal   = tinted(NSColor(red: 0.13, green: 0.72, blue: 0.72, alpha: 1))
let violet = tinted(NSColor(red: 0.62, green: 0.35, blue: 0.96, alpha: 1))

func drawBall(_ ctx: CGContext, center: CGPoint, radius: CGFloat, colors: BallColors) {
    let d = radius * 2
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: d, height: d)
    // Grounding shadow (BallTexture.softShadow), offset below.
    let shColors = [NSColor(white: 0, alpha: 0.45).cgColor,
                    NSColor(white: 0, alpha: 0).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: shColors, locations: [0, 1]) {
        let shCenter = CGPoint(x: center.x, y: center.y - radius * 1.1)
        ctx.saveGState()
        ctx.translateBy(x: shCenter.x, y: shCenter.y)
        ctx.scaleBy(x: 1, y: 0.35)                     // squash into an ellipse
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: radius * 0.95, options: [])
        ctx.restoreGState()
    }
    // Base sphere: lit upper-left, dark lower-right. (In game the lit point is
    // at x 0.35, y 0.32 with a TOP-left origin; flip y for our bottom-left origin.)
    ctx.saveGState()
    ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
    ctx.clip()
    let cols = [colors.lit.cgColor, colors.mid.cgColor, colors.shadow.cgColor] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: cols, locations: [0.0, 0.55, 1.0]) {
        let litPoint = CGPoint(x: rect.minX + d * 0.35, y: rect.minY + d * 0.68)
        ctx.drawRadialGradient(grad, startCenter: litPoint, startRadius: 0,
                               endCenter: center, endRadius: d * 0.62,
                               options: [.drawsAfterEndLocation])
    }
    ctx.restoreGState()
    // Specular highlight, top-left.
    let hlCenter = CGPoint(x: rect.minX + d * 0.34, y: rect.minY + d * 0.72)
    let hlColors = [NSColor(white: 1, alpha: 0.9).cgColor,
                    NSColor(white: 1, alpha: 0).cgColor] as CFArray
    if let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: hlColors, locations: [0, 1]) {
        ctx.drawRadialGradient(hl, startCenter: hlCenter, startRadius: 0,
                               endCenter: hlCenter, endRadius: d * 0.22, options: [])
    }
}

// MARK: - Text and motifs

func drawText(_ ctx: CGContext, _ text: String, center: CGPoint, size: CGFloat,
              color: NSColor = .white) {
    let font = NSFont.systemFont(ofSize: size, weight: .heavy)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.045)
    shadow.shadowBlurRadius = size * 0.06
    let attrs: [NSAttributedString.Key: Any] =
        [.font: font, .foregroundColor: color, .shadow: shadow]
    let str = NSAttributedString(string: text, attributes: attrs)
    let bounds = str.boundingRect(with: NSSize(width: S, height: S))
    // Vertically center on cap height (digits have no descender to speak of).
    let origin = CGPoint(x: center.x - bounds.width / 2,
                         y: center.y - font.capHeight / 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    str.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
}

/// Horizontal motion streaks trailing left of the ball (streak achievements).
func drawStreaks(_ ctx: CGContext, ballCenter: CGPoint, radius: CGFloat) {
    ctx.setLineCap(.round)
    for (dy, len, alpha): (CGFloat, CGFloat, CGFloat) in
        [(-0.45, 0.95, 0.30), (0.0, 1.30, 0.42), (0.45, 0.95, 0.30)] {
        let y = ballCenter.y + dy * radius
        // Streak hugs the ball's left silhouette at that height.
        let edgeX = ballCenter.x - radius * sqrt(max(0, 1 - dy * dy)) - 28
        ctx.setStrokeColor(NSColor(white: 1, alpha: alpha).cgColor)
        ctx.setLineWidth(30)
        ctx.move(to: CGPoint(x: edgeX - len * radius, y: y))
        ctx.addLine(to: CGPoint(x: edgeX, y: y))
        ctx.strokePath()
    }
}

/// Big white checkmark, for the clean-pass achievement.
func drawCheck(_ ctx: CGContext, center: CGPoint, size: CGFloat) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * 0.22)
    // Shadow pass then white pass, matching the text treatment.
    for (color, dy): (NSColor, CGFloat) in
        [(NSColor(white: 0, alpha: 0.5), -size * 0.05), (.white, 0)] {
        ctx.setStrokeColor(color.cgColor)
        ctx.move(to: CGPoint(x: center.x - size * 0.42, y: center.y + dy))
        ctx.addLine(to: CGPoint(x: center.x - size * 0.10, y: center.y - size * 0.32 + dy))
        ctx.addLine(to: CGPoint(x: center.x + size * 0.46, y: center.y + size * 0.36 + dy))
        ctx.strokePath()
    }
}

// MARK: - Compose one icon

struct Icon {
    let file: String
    let ball: BallColors
    let label: String?       // text on the ball
    let labelSize: CGFloat
    let streaks: Bool
    let check: Bool
}

let icons: [Icon] = [
    Icon(file: "com.agraabhi.drop.ach.score25",  ball: classicRed, label: "25",
         labelSize: 300, streaks: false, check: false),
    Icon(file: "com.agraabhi.drop.ach.score50",  ball: classicRed, label: "50",
         labelSize: 300, streaks: false, check: false),
    Icon(file: "com.agraabhi.drop.ach.score100", ball: gold,       label: "100",
         labelSize: 250, streaks: false, check: false),
    Icon(file: "com.agraabhi.drop.ach.streak5",  ball: classicRed, label: "×5",
         labelSize: 270, streaks: true,  check: false),
    Icon(file: "com.agraabhi.drop.ach.streak10", ball: teal,       label: "×10",
         labelSize: 230, streaks: true,  check: false),
    Icon(file: "com.agraabhi.drop.ach.clean100", ball: violet,     label: nil,
         labelSize: 0,   streaks: false, check: true),
]

func render(_ icon: Icon) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    drawBackground(ctx)
    // Plank with a gap under the ball; sits low so the circular crop keeps it.
    drawPlankWithGap(ctx, y: 118, height: 96, gapWidth: 430)
    let ballCenter = CGPoint(x: S / 2, y: 560)
    let radius: CGFloat = 300
    if icon.streaks { drawStreaks(ctx, ballCenter: ballCenter, radius: radius) }
    drawBall(ctx, center: ballCenter, radius: radius, colors: icon.ball)
    if let label = icon.label {
        // Slightly below ball center so it sits under the specular highlight.
        drawText(ctx, label, center: CGPoint(x: ballCenter.x, y: ballCenter.y - 40),
                 size: icon.labelSize)
    }
    if icon.check {
        drawCheck(ctx, center: CGPoint(x: ballCenter.x, y: ballCenter.y - 30), size: 300)
    }
    return ctx.makeImage()!
}

// MARK: - Main

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for icon in icons {
    let img = render(icon)
    let url = URL(fileURLWithPath: "\(outDir)/\(icon.file).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}
