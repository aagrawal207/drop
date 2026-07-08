import UIKit
import SpriteKit

/// A glossy red sphere drawn procedurally: radial base shading for volume,
/// a bright off-center specular highlight for the shine, and a darkened rim.
/// Rendered oversized (with padding) so the highlight/rim aren't clipped.
enum BallTexture {

    static func glossyRed(radius: CGFloat) -> SKTexture {
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
            let colors = [
                UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1).cgColor, // lit
                UIColor(red: 0.86, green: 0.16, blue: 0.14, alpha: 1).cgColor, // mid
                UIColor(red: 0.45, green: 0.04, blue: 0.05, alpha: 1).cgColor  // shadow rim
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space, colors: colors,
                                     locations: [0.0, 0.55, 1.0]) {
                let lit = CGPoint(x: d * 0.35, y: d * 0.32)
                ctx.drawRadialGradient(grad,
                                       startCenter: lit, startRadius: 0,
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
