import UIKit
import SpriteKit

/// A glossy sphere drawn procedurally: radial base shading for volume, a bright
/// off-center specular highlight for the shine, and a darkened rim. Rendered
/// oversized (with padding) so the highlight/rim aren't clipped.
enum BallTexture {

    /// The classic red ball (tier 0). Exact colours preserved.
    static func glossyRed(radius: CGFloat) -> SKTexture {
        render(radius: radius,
               lit: UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1),
               mid: UIColor(red: 0.86, green: 0.16, blue: 0.14, alpha: 1),
               shadow: UIColor(red: 0.45, green: 0.04, blue: 0.05, alpha: 1))
    }

    /// A glossy sphere tinted from a single vivid base colour. The lit and shadow
    /// stops are derived from the tint in HSB, so every colour tier keeps the same
    /// shaded, shiny look as the red one.
    static func glossy(radius: CGFloat, tint: UIColor) -> SKTexture {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let lit = UIColor(hue: h, saturation: max(0, s * 0.42),
                          brightness: min(1, b * 1.10 + 0.18), alpha: 1)
        let shadow = UIColor(hue: h, saturation: min(1, s * 1.05),
                             brightness: b * 0.34, alpha: 1)
        return render(radius: radius, lit: lit, mid: tint, shadow: shadow)
    }

    private static func render(radius: CGFloat, lit: UIColor, mid: UIColor, shadow: UIColor) -> SKTexture {
        let scale: CGFloat = 3                       // crisp on retina
        let d = radius * 2
        let size = CGSize(width: d, height: d)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: d / 2, y: d / 2)

            ctx.saveGState()
            ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
            ctx.clip()

            // Base sphere shading: lit upper-left, dark lower-right.
            let colors = [lit.cgColor, mid.cgColor, shadow.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors,
                                     locations: [0.0, 0.55, 1.0]) {
                let litPoint = CGPoint(x: d * 0.35, y: d * 0.32)
                ctx.drawRadialGradient(grad,
                                       startCenter: litPoint, startRadius: 0,
                                       endCenter: center, endRadius: d * 0.62,
                                       options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            // Specular highlight — a soft bright blob near the top-left.
            ctx.saveGState()
            let hlCenter = CGPoint(x: d * 0.34, y: d * 0.28)
            let hlColors = [
                UIColor(white: 1, alpha: 0.9).cgColor,
                UIColor(white: 1, alpha: 0.0).cgColor
            ] as CFArray
            if let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: hlColors, locations: [0, 1]) {
                ctx.drawRadialGradient(hl,
                                       startCenter: hlCenter, startRadius: 0,
                                       endCenter: hlCenter, endRadius: d * 0.22,
                                       options: [])
            }
            ctx.restoreGState()
        }
        return SKTexture(image: image)
    }

    /// A soft blurred shadow blob to sit beneath the ball for grounding.
    static func softShadow(radius: CGFloat) -> SKTexture {
        let d = radius * 2
        let size = CGSize(width: d, height: d)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            let center = CGPoint(x: d / 2, y: d / 2)
            let colors = [
                UIColor(white: 0, alpha: 0.45).cgColor,
                UIColor(white: 0, alpha: 0.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(grad,
                                       startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: d / 2,
                                       options: [])
            }
        }
        return SKTexture(image: image)
    }
}

/// The ball stays the classic red until the score is high, then shifts colour at
/// widely-spaced milestones — a rare, earned reward rather than a constant churn.
/// Nothing changes before 100. Tier 0 is the classic red; a `nil` tint means
/// "use glossyRed" so the default ball is byte-for-byte unchanged.
/// The tail tiers (1 000+) are aspirational: ranked's ramping speed makes them
/// near-unreachable there, but a patient Zen run at low speed can get to them.
enum BallPalette {
    static let tiers: [(minScore: Int, tint: UIColor?)] = [
        (0,   nil),                                                   // red (classic)
        (100, UIColor(red: 1.00, green: 0.80, blue: 0.12, alpha: 1)), // gold
        (200, UIColor(red: 0.13, green: 0.72, blue: 0.72, alpha: 1)), // teal
        (350, UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)), // blue
        (500, UIColor(red: 0.62, green: 0.35, blue: 0.96, alpha: 1)), // violet
        (1_000,   UIColor(red: 0.96, green: 0.26, blue: 0.62, alpha: 1)), // magenta
        (5_000,   UIColor(red: 0.16, green: 0.80, blue: 0.40, alpha: 1)), // emerald
        (10_000,  UIColor(red: 1.00, green: 0.48, blue: 0.08, alpha: 1)), // ember
        (50_000,  UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1)), // pearl
        (100_000, UIColor(red: 0.16, green: 0.16, blue: 0.20, alpha: 1)), // obsidian
    ]

    /// The highest tier whose threshold the score has reached.
    static func tierIndex(for score: Int) -> Int {
        var idx = 0
        for (i, t) in tiers.enumerated() where score >= t.minScore { idx = i }
        return idx
    }

    private static var cache: [Int: SKTexture] = [:]

    /// Cached texture for a tier (radius is fixed in practice).
    static func texture(tier: Int, radius: CGFloat) -> SKTexture {
        if let cached = cache[tier] { return cached }
        let tint = tiers[tier].tint
        let tex = tint.map { BallTexture.glossy(radius: radius, tint: $0) }
            ?? BallTexture.glossyRed(radius: radius)
        cache[tier] = tex
        return tex
    }
}
