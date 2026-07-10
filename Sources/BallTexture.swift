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

    // MARK: - Patterned sports balls

    /// The sports balls (basketball, baseball, soccer, bowling) are drawn as a
    /// flat pattern first, then unified with the tinted tiers by the same trick:
    /// a shading overlay (lit upper-left, dark rim) plus the specular highlight.
    /// The ball sprite never rotates (see the physics body), so these are static
    /// art with the same fixed lighting as the glossy tiers.
    ///
    /// All painters use pure CoreGraphics in a y-up space — they are shared
    /// verbatim with the macOS preview script (AppStore/preview_ball_tiers.swift);
    /// keep the two in sync.

    static func basketball(radius: CGFloat) -> SKTexture {
        renderPatterned(radius: radius, paint: paintBasketball)
    }
    static func baseball(radius: CGFloat) -> SKTexture {
        renderPatterned(radius: radius, paint: paintBaseball)
    }
    static func soccer(radius: CGFloat) -> SKTexture {
        renderPatterned(radius: radius, paint: paintSoccer)
    }
    static func bowling(radius: CGFloat) -> SKTexture {
        renderPatterned(radius: radius, paint: paintBowling)
    }

    /// Flat pattern -> sphere: clip to the circle, paint, then add volume with a
    /// radial shade (bright at the lit point, dark at the rim) and the same
    /// specular blob the tinted balls use. The context is flipped to y-up before
    /// painting so pattern math matches the preview script.
    private static func renderPatterned(radius: CGFloat,
                                        paint: (CGContext, CGFloat) -> Void) -> SKTexture {
        let scale: CGFloat = 3
        let d = radius * 2
        let size = CGSize(width: d, height: d)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            // UIKit contexts are y-down; flip so the painters (and the shading
            // points below) are in y-up coordinates.
            ctx.translateBy(x: 0, y: d)
            ctx.scaleBy(x: 1, y: -1)
            applySphereEffect(ctx, d: d, paint: paint)
        }
        return SKTexture(image: image)
    }

    /// Shared by the game and (copy-pasted) the preview script. Y-up context.
    private static func applySphereEffect(_ ctx: CGContext, d: CGFloat,
                                          paint: (CGContext, CGFloat) -> Void) {
        let rect = CGRect(x: 0, y: 0, width: d, height: d)
        ctx.saveGState()
        ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        ctx.clip()
        paint(ctx, d)

        // Volume: light at the upper-left lit point, falling to a dark rim.
        let space = CGColorSpaceCreateDeviceRGB()
        let shade = [
            CGColor(colorSpace: space, components: [1, 1, 1, 0.20])!,
            CGColor(colorSpace: space, components: [0, 0, 0, 0.0])!,
            CGColor(colorSpace: space, components: [0, 0, 0, 0.45])!,
        ] as CFArray
        if let grad = CGGradient(colorsSpace: space, colors: shade,
                                 locations: [0.0, 0.45, 1.0]) {
            let litPoint = CGPoint(x: d * 0.35, y: d * 0.68)
            ctx.drawRadialGradient(grad,
                                   startCenter: litPoint, startRadius: 0,
                                   endCenter: CGPoint(x: d / 2, y: d / 2),
                                   endRadius: d * 0.62,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()

        // Specular highlight, top-left — identical to the tinted render.
        let hlCenter = CGPoint(x: d * 0.34, y: d * 0.72)
        let hl = [
            CGColor(colorSpace: space, components: [1, 1, 1, 0.9])!,
            CGColor(colorSpace: space, components: [1, 1, 1, 0.0])!,
        ] as CFArray
        if let grad = CGGradient(colorsSpace: space, colors: hl, locations: [0, 1]) {
            ctx.drawRadialGradient(grad,
                                   startCenter: hlCenter, startRadius: 0,
                                   endCenter: hlCenter, endRadius: d * 0.22,
                                   options: [])
        }
    }

    // MARK: Pattern painters (pure CG, y-up, shared with the preview script)

    /// Regular polygon path helper. `rotation` in radians; 0 puts a vertex at
    /// the +x axis, angles increase counter-clockwise.
    private static func addPolygon(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                   sides: Int, rotation: CGFloat) {
        for i in 0..<sides {
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
    }

    /// Basketball: vivid orange with the classic four seams — vertical,
    /// horizontal, and one side arc hugging each edge.
    private static func paintBasketball(_ ctx: CGContext, _ d: CGFloat) {
        ctx.setFillColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setStrokeColor(red: 0.13, green: 0.05, blue: 0.03, alpha: 1)
        ctx.setLineWidth(d * 0.045)
        // Great circles seen face-on: straight vertical + horizontal seams.
        ctx.move(to: CGPoint(x: d / 2, y: 0)); ctx.addLine(to: CGPoint(x: d / 2, y: d))
        ctx.move(to: CGPoint(x: 0, y: d / 2)); ctx.addLine(to: CGPoint(x: d, y: d / 2))
        ctx.strokePath()
        // Side seams: big circles centered outside the ball, clipped to arcs.
        for cx in [-d * 0.28, d * 1.28] {
            ctx.strokeEllipse(in: CGRect(x: cx - d * 0.55, y: d / 2 - d * 0.55,
                                         width: d * 1.1, height: d * 1.1))
        }
    }

    /// Baseball: cream white with two red stitched seams curving in from the
    /// sides (the classic "tennis ball curve" layout).
    private static func paintBaseball(_ ctx: CGContext, _ d: CGFloat) {
        ctx.setFillColor(red: 0.97, green: 0.96, blue: 0.90, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setStrokeColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1)

        // Each seam is an arc of a circle whose center sits outside the ball.
        let r = d * 0.52
        let seams: [(cx: CGFloat, inward: Bool)] = [(-d * 0.14, true), (d * 1.14, false)]
        for seam in seams {
            let center = CGPoint(x: seam.cx, y: d / 2)
            ctx.setLineWidth(d * 0.032)
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                         width: r * 2, height: r * 2))
            // Stitches: short radial ticks crossing the seam, every few degrees
            // along the portion of the arc that lies inside the ball.
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

    /// Soccer ball: white with a black center pentagon, five rim pentagons at
    /// the vertices' angles, and thin radial spokes joining them.
    private static func paintSoccer(_ ctx: CGContext, _ d: CGFloat) {
        ctx.setFillColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
        let c = CGPoint(x: d / 2, y: d / 2)
        let ink: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.10, 0.10, 0.12, 1)

        // Spokes first so the pentagons paint over their ends.
        ctx.setStrokeColor(red: ink.0, green: ink.1, blue: ink.2, alpha: 0.55)
        ctx.setLineWidth(d * 0.014)
        for i in 0..<5 {
            let a = .pi / 2 + CGFloat(i) * 2 * .pi / 5
            ctx.move(to: CGPoint(x: c.x + d * 0.17 * cos(a), y: c.y + d * 0.17 * sin(a)))
            ctx.addLine(to: CGPoint(x: c.x + d * 0.44 * cos(a), y: c.y + d * 0.44 * sin(a)))
        }
        ctx.strokePath()

        ctx.setFillColor(red: ink.0, green: ink.1, blue: ink.2, alpha: ink.3)
        // Center pentagon, point-up.
        addPolygon(ctx, center: c, radius: d * 0.17, sides: 5, rotation: .pi / 2)
        ctx.fillPath()
        // Rim pentagons at each spoke end, points aimed at the center.
        for i in 0..<5 {
            let a = .pi / 2 + CGFloat(i) * 2 * .pi / 5
            let p = CGPoint(x: c.x + d * 0.44 * cos(a), y: c.y + d * 0.44 * sin(a))
            addPolygon(ctx, center: p, radius: d * 0.15, sides: 5, rotation: a + .pi)
            ctx.fillPath()
        }
    }

    /// Bowling ball: deep glossy night-purple with the two finger holes and a
    /// thumb hole. The holes get a faint bright lower lip so they read as
    /// drilled, not painted.
    private static func paintBowling(_ ctx: CGContext, _ d: CGFloat) {
        ctx.setFillColor(red: 0.13, green: 0.10, blue: 0.19, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: d, height: d))
        let holes: [(CGFloat, CGFloat)] = [(-0.11, 0.16), (0.07, 0.19), (-0.03, -0.02)]
        for (hx, hy) in holes {
            let r = d * 0.075
            let center = CGPoint(x: d / 2 + hx * d, y: d / 2 + hy * d)
            ctx.setFillColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                       width: r * 2, height: r * 2))
            // Bright lower lip: light catches the inside edge opposite the light.
            ctx.setStrokeColor(red: 0.45, green: 0.42, blue: 0.55, alpha: 0.55)
            ctx.setLineWidth(d * 0.010)
            ctx.addArc(center: center, radius: r - d * 0.006,
                       startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
            ctx.strokePath()
        }
    }
}

/// The ball stays the classic red until the score is high, then changes look at
/// widely-spaced milestones — a rare, earned reward rather than a constant churn.
/// Nothing changes before 100. Tints alternate with full sports-ball makeovers
/// so the bigger surprises land on the bigger milestones. The tail tiers are
/// aspirational: ranked's ramping speed makes them near-unreachable there, but
/// a patient Zen run at low speed can get to them.
enum BallPalette {
    enum Style {
        case classic                 // the original red, byte-for-byte unchanged
        case tint(UIColor)           // glossy recolour of the classic ball
        case basketball, baseball, soccer, bowling
    }

    static let tiers: [(minScore: Int, style: Style)] = [
        (0,   .classic),
        (100, .tint(UIColor(red: 1.00, green: 0.76, blue: 0.03, alpha: 1))), // gold
        (200, .tint(UIColor(red: 0.00, green: 0.78, blue: 0.92, alpha: 1))), // cyan
        (350, .basketball),
        (500, .tint(UIColor(red: 0.58, green: 0.20, blue: 1.00, alpha: 1))), // violet
        (1_000,  .baseball),
        (5_000,  .tint(UIColor(red: 0.00, green: 0.84, blue: 0.38, alpha: 1))), // emerald
        (10_000, .soccer),
        (50_000, .tint(UIColor(red: 1.00, green: 0.10, blue: 0.55, alpha: 1))), // magenta
        (100_000, .bowling),
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
        let tex: SKTexture
        switch tiers[tier].style {
        case .classic:         tex = BallTexture.glossyRed(radius: radius)
        case .tint(let color): tex = BallTexture.glossy(radius: radius, tint: color)
        case .basketball:      tex = BallTexture.basketball(radius: radius)
        case .baseball:        tex = BallTexture.baseball(radius: radius)
        case .soccer:          tex = BallTexture.soccer(radius: radius)
        case .bowling:         tex = BallTexture.bowling(radius: radius)
        }
        cache[tier] = tex
        return tex
    }
}
