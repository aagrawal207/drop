import SpriteKit
import UIKit

/// SF Symbols rendered to cached SpriteKit textures, so scene icons match system
/// glyphs without bundling assets.
enum SceneIcons {
    /// Fixed 3x covers iPhone screens and the iPad field, which is upscaled to
    /// roughly 1.2-1.6x on a 2x screen; reading the live view scale would need plumbing.
    private static let renderScale: CGFloat = 3
    private static var cache: [String: (texture: SKTexture, size: CGSize)] = [:]

    private static func texture(_ symbol: String, pointSize: CGFloat, weight: UIImage.SymbolWeight,
                                color: UIColor) -> (texture: SKTexture, size: CGSize) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(symbol)|\(pointSize)|\(weight.rawValue)|\(r),\(g),\(b),\(a)"
        if let cached = cache[key] { return cached }

        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let base = UIImage(systemName: symbol, withConfiguration: config)
            ?? UIImage(systemName: "questionmark", withConfiguration: config)!
        let tinted = base.withTintColor(color, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: tinted.size, format: format).image { _ in
            tinted.draw(at: .zero)
        }
        let entry = (texture: SKTexture(image: image), size: tinted.size)
        cache[key] = entry
        return entry
    }

    static func sprite(_ symbol: String, pointSize: CGFloat,
                       weight: UIImage.SymbolWeight = .semibold, color: UIColor) -> SKSpriteNode {
        let entry = texture(symbol, pointSize: pointSize, weight: weight, color: color)
        // Pin to the point size so the 3x texture never renders at pixel dimensions.
        return SKSpriteNode(texture: entry.texture, size: entry.size)
    }

    /// Round corner button: the dark disc keeps the glyph legible over light planks,
    /// and as the accessible node its 44pt frame is also the visible target.
    static func cornerButton(_ symbol: String, color: UIColor, name: String,
                             pointSize: CGFloat = 22) -> SKShapeNode {
        let disc = SKShapeNode(circleOfRadius: 22)
        disc.fillColor = SKColor(white: 0, alpha: 0.25)
        disc.strokeColor = SKColor(white: 1, alpha: 0.08)
        disc.lineWidth = 1
        disc.name = name
        let glyph = sprite(symbol, pointSize: pointSize, color: color)
        glyph.name = name
        glyph.isAccessibilityElement = false
        disc.addChild(glyph)
        return disc
    }

    static func pressDip(_ node: SKNode) {
        node.removeAction(forKey: "pressDip")
        node.setScale(1)
        node.run(.sequence([.scale(to: 0.88, duration: 0.06),
                            .scale(to: 1.0, duration: 0.08)]), withKey: "pressDip")
    }
}
