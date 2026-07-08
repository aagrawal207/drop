#!/usr/bin/env swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders the Drop app icon: dark walnut backdrop, one oak plank with a gap,
// and a glossy red ball hovering above the hole. 1024×1024, no rounded corners
// (iOS masks the icon itself).

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Deterministic pseudo-random for grain.
var seed: UInt64 = 0xD1B54A32D192ED03
func rnd() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
}

// --- Background: dark walnut with vertical grain ---
ctx.setFillColor(rgb(0.24, 0.15, 0.09))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
for _ in 0..<Int(S / 3) {
    let x = rnd() * S
    let dark = rnd() > 0.5
    let c = dark ? rgb(0.14, 0.08, 0.04, 0.15) : rgb(0.34, 0.22, 0.13, 0.15)
    ctx.setFillColor(c)
    var y: CGFloat = 0
    while y < S {
        let seg = 40 + rnd() * 120
        ctx.fill(CGRect(x: x + (rnd() - 0.5) * 8, y: y, width: 1 + rnd() * 4, height: seg))
        y += seg
    }
}
// Vertical plank seams.
ctx.setFillColor(rgb(0, 0, 0, 0.28))
var sx: CGFloat = 200
while sx < S { ctx.fill(CGRect(x: sx, y: 0, width: 5, height: S)); sx += 200 }

// --- The plank (with a gap) ---
let plankH: CGFloat = 150
let plankY = S * 0.24
let gapCenter = S * 0.58
let gapW: CGFloat = 250

func drawPlank(x: CGFloat, w: CGFloat) {
    guard w > 1 else { return }
    // Clip so grain never bleeds past the plank edge into the gap.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: plankY, width: w, height: plankH))
    // Oak base.
    ctx.setFillColor(rgb(0.62, 0.44, 0.26))
    ctx.fill(CGRect(x: x, y: plankY, width: w, height: plankH))
    // Horizontal grain.
    for _ in 0..<Int(plankH / 4) {
        let yy = plankY + rnd() * plankH
        let dark = rnd() > 0.5
        ctx.setFillColor(dark ? rgb(0.42, 0.28, 0.15, 0.18) : rgb(0.78, 0.60, 0.38, 0.18))
        var xx = x
        while xx < x + w {
            let seg = 30 + rnd() * 90
            ctx.fill(CGRect(x: xx, y: yy + (rnd() - 0.5) * 6, width: seg, height: 1 + rnd() * 3))
            xx += seg
        }
    }
    // Bevel: bright top, dark bottom.
    ctx.setFillColor(rgb(1, 1, 1, 0.18))
    ctx.fill(CGRect(x: x, y: plankY + plankH - 10, width: w, height: 10))
    ctx.setFillColor(rgb(0, 0, 0, 0.25))
    ctx.fill(CGRect(x: x, y: plankY, width: w, height: 10))
    ctx.restoreGState()
}
drawPlank(x: 0, w: gapCenter - gapW / 2)
drawPlank(x: gapCenter + gapW / 2, w: S - (gapCenter + gapW / 2))

// --- The red ball, centered over the gap, above the plank ---
let ballR: CGFloat = 200
let ballC = CGPoint(x: gapCenter, y: S * 0.62)

// Soft drop shadow beneath.
ctx.saveGState()
let shadowC = CGPoint(x: ballC.x + 10, y: ballC.y - ballR * 0.9)
if let sh = CGGradient(colorsSpace: cs,
                       colors: [rgb(0,0,0,0.4), rgb(0,0,0,0)] as CFArray,
                       locations: [0, 1]) {
    ctx.drawRadialGradient(sh, startCenter: shadowC, startRadius: 0,
                           endCenter: shadowC, endRadius: ballR * 0.95, options: [])
}
ctx.restoreGState()

// Sphere body.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: ballC.x - ballR, y: ballC.y - ballR, width: ballR * 2, height: ballR * 2))
ctx.clip()
let lit = CGPoint(x: ballC.x - ballR * 0.3, y: ballC.y + ballR * 0.32)
if let grad = CGGradient(colorsSpace: cs,
                         colors: [rgb(1.0, 0.42, 0.38), rgb(0.86, 0.16, 0.14), rgb(0.45, 0.04, 0.05)] as CFArray,
                         locations: [0, 0.55, 1]) {
    ctx.drawRadialGradient(grad, startCenter: lit, startRadius: 0,
                           endCenter: ballC, endRadius: ballR * 1.25,
                           options: [.drawsAfterEndLocation])
}
ctx.restoreGState()

// Specular highlight.
ctx.saveGState()
let hl = CGPoint(x: ballC.x - ballR * 0.32, y: ballC.y + ballR * 0.4)
if let g = CGGradient(colorsSpace: cs,
                      colors: [rgb(1,1,1,0.9), rgb(1,1,1,0)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawRadialGradient(g, startCenter: hl, startRadius: 0,
                           endCenter: hl, endRadius: ballR * 0.5, options: [])
}
ctx.restoreGState()

// --- Write PNG ---
guard let image = ctx.makeImage() else { fatalError("no image") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
