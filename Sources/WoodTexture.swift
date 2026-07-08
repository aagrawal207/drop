import UIKit
import SpriteKit

/// Procedurally drawn wood textures so the game ships with no image assets.
/// Grain is faked with a base gradient plus semi-transparent streaks; it reads
/// as wood at gameplay scale without needing real Perlin noise.
enum WoodTexture {

    /// A horizontal wooden plank for the floors: light, warm oak tone with a
    /// bevelled top edge so stacked floors read as separate boards.
    static func plank(width: CGFloat, height: CGFloat) -> SKTexture {
        let size = CGSize(width: max(width, 1), height: height)
        let image = render(size: size) { ctx, rect in
            drawGrain(in: ctx, rect: rect,
                      base: (0.62, 0.44, 0.26),   // warm oak
                      streak: (0.42, 0.28, 0.15),
                      highlight: (0.78, 0.60, 0.38),
                      grainVertical: false)
            // Bevel: bright top edge, dark bottom edge for depth.
            ctx.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
            ctx.fill(CGRect(x: 0, y: rect.height - 3, width: rect.width, height: 3))
            ctx.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: rect.width, height: 3))
        }
        return SKTexture(image: image)
    }

    /// A darker walnut backdrop with vertical planks so it clearly differs in
    /// shade from the floors.
    static func background(width: CGFloat, height: CGFloat) -> SKTexture {
        let size = CGSize(width: width, height: height)
        let image = render(size: size) { ctx, rect in
            drawGrain(in: ctx, rect: rect,
                      base: (0.24, 0.15, 0.09),   // dark walnut
                      streak: (0.14, 0.08, 0.04),
                      highlight: (0.34, 0.22, 0.13),
                      grainVertical: true)
            // Seams between vertical planks.
            let plankWidth: CGFloat = 84
            ctx.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var x: CGFloat = plankWidth
            while x < rect.width {
                ctx.fill(CGRect(x: x, y: 0, width: 2, height: rect.height))
                x += plankWidth
            }
        }
        return SKTexture(image: image)
    }

    // MARK: - Drawing helpers

    private static func render(size: CGSize, _ draw: (CGContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            draw(ctx, rect)
        }
    }

    private static func drawGrain(in ctx: CGContext,
                                  rect: CGRect,
                                  base: (CGFloat, CGFloat, CGFloat),
                                  streak: (CGFloat, CGFloat, CGFloat),
                                  highlight: (CGFloat, CGFloat, CGFloat),
                                  grainVertical: Bool) {
        // Base fill.
        ctx.setFillColor(red: base.0, green: base.1, blue: base.2, alpha: 1)
        ctx.fill(rect)

        // Grain streaks run along the plank's long axis. Deterministic pseudo
        // random so textures look consistent between launches.
        var seed: UInt64 = grainVertical ? 0x9E3779B97F4A7C15 : 0xD1B54A32D192ED03
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
        }

        let span = grainVertical ? rect.width : rect.height
        let length = grainVertical ? rect.height : rect.width
        let lineCount = Int(span / 3)

        for _ in 0..<lineCount {
            let pos = rnd() * span
            let dark = rnd() > 0.5
            let c = dark ? streak : highlight
            let alpha = 0.05 + rnd() * 0.18
            let thickness = 0.5 + rnd() * 2.0
            ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: alpha)
            // Break each streak into wavy segments for a more organic grain.
            var t: CGFloat = 0
            while t < length {
                let segLen = 12 + rnd() * 40
                let wobble = (rnd() - 0.5) * 3
                if grainVertical {
                    ctx.fill(CGRect(x: pos + wobble, y: t, width: thickness, height: segLen))
                } else {
                    ctx.fill(CGRect(x: t, y: pos + wobble, width: segLen, height: thickness))
                }
                t += segLen
            }
        }
    }
}
