#!/usr/bin/env swift
// Renders every BallPalette tier to one strip image for eyeballing, at both
// game size (34 pt -> 102 px @3x) and large. The pattern painters and the
// sphere-effect overlay are copied VERBATIM from Sources/BallTexture.swift
// (they are pure CoreGraphics, y-up); the tinted render reimplements the same
// math. If BallTexture.swift changes, re-copy the painters.
//
// Run:  swift AppStore/preview_ball_tiers.swift
// Out:  /tmp/ball_tiers.png

import AppKit

// MARK: - Painters (verbatim from BallTexture.swift)

func addPolygon(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                sides: Int, rotation: CGFloat) {
    for i in 0..<sides {
        let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
        let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
    }
    ctx.closePath()
}

func paintBasketball(_ ctx: CGContext, _ d: CGFloat) {
    ctx.setFillColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
    ctx.setStrokeColor(red: 0.13, green: 0.05, blue: 0.03, alpha: 1)
    ctx.setLineWidth(d * 0.045)
    ctx.move(to: CGPoint(x: d / 2, y: 0)); ctx.addLine(to: CGPoint(x: d / 2, y: d))
    ctx.move(to: CGPoint(x: 0, y: d / 2)); ctx.addLine(to: CGPoint(x: d, y: d / 2))
    ctx.strokePath()
    for cx in [-d * 0.28, d * 1.28] {
        ctx.strokeEllipse(in: CGRect(x: cx - d * 0.55, y: d / 2 - d * 0.55,
                                     width: d * 1.1, height: d * 1.1))
    }
}

func paintBaseball(_ ctx: CGContext, _ d: CGFloat) {
    ctx.setFillColor(red: 0.97, green: 0.96, blue: 0.90, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
    ctx.setStrokeColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1)
    let r = d * 0.52
    let seams: [(cx: CGFloat, inward: Bool)] = [(-d * 0.14, true), (d * 1.14, false)]
    for seam in seams {
        let center = CGPoint(x: seam.cx, y: d / 2)
        ctx.setLineWidth(d * 0.032)
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                     width: r * 2, height: r * 2))
        ctx.setLineWidth(d * 0.018)
        let sweep: ClosedRange<CGFloat> = seam.inward ? (-0.62 ... 0.62) : (2.52 ... 3.76)
        var a = sweep.lowerBound
        while a <= sweep.upperBound {
            let dir = CGPoint(x: cos(a), y: sin(a))
            let p = CGPoint(x: center.x + r * dir.x, y: center.y + r * dir.y)
            let t = d * 0.045
            ctx.move(to: CGPoint(x: p.x - dir.x * t, y: p.y - dir.y * t))
            ctx.addLine(to: CGPoint(x: p.x + dir.x * t, y: p.y + dir.y * t))
            a += 0.16
        }
        ctx.strokePath()
    }
}

func paintSoccer(_ ctx: CGContext, _ d: CGFloat) {
    ctx.setFillColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
    let c = CGPoint(x: d / 2, y: d / 2)
    let ink: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.10, 0.10, 0.12, 1)
    ctx.setStrokeColor(red: ink.0, green: ink.1, blue: ink.2, alpha: 0.55)
    ctx.setLineWidth(d * 0.014)
    for i in 0..<5 {
        let a = .pi / 2 + CGFloat(i) * 2 * .pi / 5
        ctx.move(to: CGPoint(x: c.x + d * 0.17 * cos(a), y: c.y + d * 0.17 * sin(a)))
        ctx.addLine(to: CGPoint(x: c.x + d * 0.44 * cos(a), y: c.y + d * 0.44 * sin(a)))
    }
    ctx.strokePath()
    ctx.setFillColor(red: ink.0, green: ink.1, blue: ink.2, alpha: ink.3)
    addPolygon(ctx, center: c, radius: d * 0.17, sides: 5, rotation: .pi / 2)
    ctx.fillPath()
    for i in 0..<5 {
        let a = .pi / 2 + CGFloat(i) * 2 * .pi / 5
        let p = CGPoint(x: c.x + d * 0.44 * cos(a), y: c.y + d * 0.44 * sin(a))
        addPolygon(ctx, center: p, radius: d * 0.15, sides: 5, rotation: a + .pi)
        ctx.fillPath()
    }
}

func paintBowling(_ ctx: CGContext, _ d: CGFloat) {
    ctx.setFillColor(red: 0.13, green: 0.10, blue: 0.19, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
    let holes: [(CGFloat, CGFloat)] = [(-0.11, 0.16), (0.07, 0.19), (-0.03, -0.02)]
    for (hx, hy) in holes {
        let r = d * 0.075
        let center = CGPoint(x: d / 2 + hx * d, y: d / 2 + hy * d)
        ctx.setFillColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                   width: r * 2, height: r * 2))
        ctx.setStrokeColor(red: 0.45, green: 0.42, blue: 0.55, alpha: 0.55)
        ctx.setLineWidth(d * 0.010)
        ctx.addArc(center: center, radius: r - d * 0.006,
                   startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        ctx.strokePath()
    }
}

// MARK: - Sphere effect (verbatim, y-up)

func applySphereEffect(_ ctx: CGContext, d: CGFloat, paint: (CGContext, CGFloat) -> Void) {
    let rect = CGRect(x: 0, y: 0, width: d, height: d)
    ctx.saveGState()
    ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
    ctx.clip()
    paint(ctx, d)
    let space = CGColorSpaceCreateDeviceRGB()
    let shade = [
        CGColor(colorSpace: space, components: [1, 1, 1, 0.20])!,
        CGColor(colorSpace: space, components: [0, 0, 0, 0.0])!,
        CGColor(colorSpace: space, components: [0, 0, 0, 0.45])!,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: shade, locations: [0.0, 0.45, 1.0]) {
        let litPoint = CGPoint(x: d * 0.35, y: d * 0.68)
        ctx.drawRadialGradient(grad, startCenter: litPoint, startRadius: 0,
                               endCenter: CGPoint(x: d / 2, y: d / 2),
                               endRadius: d * 0.62, options: [.drawsAfterEndLocation])
    }
    ctx.restoreGState()
    let hlCenter = CGPoint(x: d * 0.34, y: d * 0.72)
    let hl = [
        CGColor(colorSpace: space, components: [1, 1, 1, 0.9])!,
        CGColor(colorSpace: space, components: [1, 1, 1, 0.0])!,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: hl, locations: [0, 1]) {
        ctx.drawRadialGradient(grad, startCenter: hlCenter, startRadius: 0,
                               endCenter: hlCenter, endRadius: d * 0.22, options: [])
    }
}

// MARK: - Tinted glossy (same math as BallTexture.render/glossy, y-up)

struct Tint { let r, g, b: CGFloat }

func glossyBall(_ ctx: CGContext, d: CGFloat, lit: NSColor, mid: NSColor, shadow: NSColor) {
    let rect = CGRect(x: 0, y: 0, width: d, height: d)
    ctx.saveGState()
    ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [lit.cgColor, mid.cgColor, shadow.cgColor] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 0.55, 1.0]) {
        let litPoint = CGPoint(x: d * 0.35, y: d * 0.68)
        ctx.drawRadialGradient(grad, startCenter: litPoint, startRadius: 0,
                               endCenter: CGPoint(x: d / 2, y: d / 2),
                               endRadius: d * 0.62, options: [.drawsAfterEndLocation])
    }
    ctx.restoreGState()
    let hlCenter = CGPoint(x: d * 0.34, y: d * 0.72)
    let hl = [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: hl, locations: [0, 1]) {
        ctx.drawRadialGradient(grad, startCenter: hlCenter, startRadius: 0,
                               endCenter: hlCenter, endRadius: d * 0.22, options: [])
    }
}

func tinted(_ t: Tint) -> (NSColor, NSColor, NSColor) {
    let c = NSColor(red: t.r, green: t.g, blue: t.b, alpha: 1).usingColorSpace(.deviceRGB)!
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return (NSColor(hue: h, saturation: max(0, s * 0.42), brightness: min(1, b * 1.10 + 0.18), alpha: 1),
            c,
            NSColor(hue: h, saturation: min(1, s * 1.05), brightness: b * 0.34, alpha: 1))
}

// MARK: - Compose the strip

enum Style { case classic, tint(Tint), basketball, baseball, soccer, bowling }
let tiers: [(String, Style)] = [
    ("0 red",        .classic),
    ("100 gold",     .tint(Tint(r: 1.00, g: 0.76, b: 0.03))),
    ("200 cyan",     .tint(Tint(r: 0.00, g: 0.78, b: 0.92))),
    ("350 bball",    .basketball),
    ("500 violet",   .tint(Tint(r: 0.58, g: 0.20, b: 1.00))),
    ("1k baseball",  .baseball),
    ("5k emerald",   .tint(Tint(r: 0.00, g: 0.84, b: 0.38))),
    ("10k soccer",   .soccer),
    ("50k magenta",  .tint(Tint(r: 1.00, g: 0.10, b: 0.55))),
    ("100k bowling", .bowling),
]

let classicRed = (NSColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1),
                  NSColor(red: 0.86, green: 0.16, blue: 0.14, alpha: 1),
                  NSColor(red: 0.45, green: 0.04, blue: 0.05, alpha: 1))

func drawBall(_ ctx: CGContext, style: Style, at origin: CGPoint, d: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    switch style {
    case .classic:
        glossyBall(ctx, d: d, lit: classicRed.0, mid: classicRed.1, shadow: classicRed.2)
    case .tint(let t):
        let (l, m, s) = tinted(t); glossyBall(ctx, d: d, lit: l, mid: m, shadow: s)
    case .basketball: applySphereEffect(ctx, d: d, paint: paintBasketball)
    case .baseball:   applySphereEffect(ctx, d: d, paint: paintBaseball)
    case .soccer:     applySphereEffect(ctx, d: d, paint: paintSoccer)
    case .bowling:    applySphereEffect(ctx, d: d, paint: paintBowling)
    }
    ctx.restoreGState()
}

let bigD: CGFloat = 220, gameD: CGFloat = 102   // 34pt ball @3x = 102px
let cell: CGFloat = 250
let W = cell * CGFloat(tiers.count), H: CGFloat = 470
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Walnut-ish backdrop matching the game background base colour.
ctx.setFillColor(red: 0.24, green: 0.15, blue: 0.09, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for (i, (label, style)) in tiers.enumerated() {
    let x = CGFloat(i) * cell
    drawBall(ctx, style: style, at: CGPoint(x: x + (cell - bigD) / 2, y: 190), d: bigD)
    drawBall(ctx, style: style, at: CGPoint(x: x + (cell - gameD) / 2, y: 60), d: gameD)
    let attrs: [NSAttributedString.Key: Any] =
        [.font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: label, attributes: attrs)
    str.draw(at: CGPoint(x: x + (cell - str.size().width) / 2, y: 14))
}

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: "/tmp/ball_tiers.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote /tmp/ball_tiers.png")
