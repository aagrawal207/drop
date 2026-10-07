import SpriteKit
import UIKit

/// Reward and danger visuals layered on top of the core game. GameScene owns one
/// instance and calls it from a handful of hook points; all nodes are built from
/// cached procedural textures and remove themselves when done.
final class GameEffects {
    private weak var scene: SKScene?
    private weak var camera: SKCameraNode?
    private let dangerGlow = SKSpriteNode(texture: GameEffects.glowTexture)
    private var lastDangerTick: CFTimeInterval = 0
    private weak var milestoneLabel: SKLabelNode?

    // Tuning.
    private let milestoneEvery = 50
    /// Fraction of the view height, measured from the top edge, where the glow starts.
    private let dangerZone: CGFloat = 0.25
    private let dangerMaxAlpha: CGFloat = 0.55
    private let hitStopDuration: TimeInterval = 0.1

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func attach(to scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
        dangerGlow.anchorPoint = CGPoint(x: 0.5, y: 1)
        dangerGlow.color = SKColor(red: 0.95, green: 0.18, blue: 0.12, alpha: 1)
        dangerGlow.colorBlendFactor = 1
        // Above floors and ball so the warning reads, below the HUD (10) and pause button (15).
        dangerGlow.zPosition = 6
        dangerGlow.alpha = 0
        dangerGlow.isHidden = true
        camera.addChild(dangerGlow)
    }

    // MARK: - Streak

    /// Combo label colour: the existing gold at the bonus threshold, warming to coral by ×10.
    static func streakColor(_ streak: Int) -> SKColor {
        let t = CGFloat(min(max(streak - 3, 0), 7)) / 7
        return SKColor(red: 1.0, green: 0.78 - 0.36 * t, blue: 0.28 - 0.06 * t, alpha: 1)
    }

    /// Wood chips kicked off the gap edge on a clean pass; sparks join once the bonus is live.
    func cleanPass(at point: CGPoint, streak: Int, bonusLive: Bool) {
        guard let scene else { return }
        let chips = Self.chipTemplate.copy() as! SKEmitterNode
        chips.numParticlesToEmit = min(6 + 2 * streak, 18)
        chips.particleSpeed = bonusLive ? 190 : 140
        if bonusLive {
            chips.particleColor = SKColor(red: 0.98, green: 0.66, blue: 0.30, alpha: 1)
        }
        if reduceMotion { chips.particleSpeed *= 0.5 }
        spawn(chips, at: point, in: scene, z: 4)

        guard bonusLive else { return }
        let sparks = Self.sparkTemplate.copy() as! SKEmitterNode
        sparks.numParticlesToEmit = min(4 + streak, 14)
        if reduceMotion { sparks.particleSpeed *= 0.5 }
        spawn(sparks, at: point, in: scene, z: 4)
    }

    // MARK: - Milestones

    /// Celebrates each 50-point boundary once, even when a bonus jumps the score across it.
    func scoreRose(from old: Int, to new: Int) {
        guard new / milestoneEvery > old / milestoneEvery, new > 0 else { return }
        let reached = (new / milestoneEvery) * milestoneEvery
        showMilestone(reached)
        SoundManager.shared.milestone()
        HapticsManager.shared.milestone()
    }

    private func showMilestone(_ value: Int) {
        guard let camera, let scene else { return }
        milestoneLabel?.removeFromParent()
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "\(value)"
        label.fontSize = min(scene.size.width * 0.38, 200)
        label.fontColor = SKColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: scene.size.height * 0.08)
        // Over the planks, under the ball (5), so it reads as a backdrop rather than HUD.
        label.zPosition = 3
        label.alpha = 0
        let fade = SKAction.sequence([
            .fadeAlpha(to: 0.26, duration: 0.12),
            .wait(forDuration: 0.3),
            .fadeOut(withDuration: 0.5),
        ])
        if reduceMotion {
            label.run(.sequence([fade, .removeFromParent()]))
        } else {
            label.setScale(0.6)
            let grow = SKAction.scale(to: 1.15, duration: 0.92)
            grow.timingMode = .easeOut
            label.run(.sequence([.group([fade, grow]), .removeFromParent()]))
        }
        camera.addChild(label)
        milestoneLabel = label
    }

    // MARK: - Danger

    /// Call every frame. The glow eases toward a target set by how close the ball's top is to
    /// the kill line; when not playing it snaps off so pause and menus never show it.
    func updateDanger(active: Bool, ballTop: CGFloat, viewTop: CGFloat) {
        let now = CACurrentMediaTime()
        let dt = lastDangerTick == 0 ? 0 : min(now - lastDangerTick, 0.1)
        lastDangerTick = now
        guard active, let scene else {
            dangerGlow.alpha = 0
            dangerGlow.isHidden = true
            return
        }
        let h = scene.size.height
        let zone = h * dangerZone
        let closeness = min(max(1 - (viewTop - ballTop) / zone, 0), 1)
        let target = pow(closeness, 1.5) * dangerMaxAlpha
        // Time-based easing so 60Hz and 120Hz devices fade at the same rate.
        let k = CGFloat(1 - exp(-dt * 12))
        dangerGlow.alpha += (target - dangerGlow.alpha) * k
        dangerGlow.isHidden = dangerGlow.alpha < 0.01
        guard !dangerGlow.isHidden else { return }
        dangerGlow.size = CGSize(width: scene.size.width, height: h * 0.2)
        dangerGlow.position = CGPoint(x: 0, y: h / 2)
    }

    // MARK: - Death

    /// Ring pop and chip burst at the ball, a squash, and a short hit-stop that holds the
    /// camera's actions (the shake) for a beat. Never delays overlay creation or input.
    func playDeath(at point: CGPoint, ballSprite: SKSpriteNode) {
        guard let scene else { return }
        dangerGlow.alpha = 0
        dangerGlow.isHidden = true

        let ring = SKShapeNode(circleOfRadius: 18)
        ring.strokeColor = SKColor(red: 1.0, green: 0.62, blue: 0.5, alpha: 1)
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.position = point
        ring.zPosition = 6
        scene.addChild(ring)

        if reduceMotion {
            ring.setScale(1.6)
            ring.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
        } else {
            let grow = SKAction.scale(to: 3.4, duration: 0.38)
            grow.timingMode = .easeOut
            ring.run(.sequence([.group([grow, .fadeOut(withDuration: 0.38)]), .removeFromParent()]))

            let burst = Self.chipTemplate.copy() as! SKEmitterNode
            burst.numParticlesToEmit = 20
            burst.emissionAngleRange = .pi * 2
            burst.particleSpeed = 220
            burst.particleColor = SKColor(red: 1.0, green: 0.55, blue: 0.42, alpha: 1)
            spawn(burst, at: point, in: scene, z: 6)

            let squash = SKAction.sequence([
                .group([.scaleX(to: 1.35, duration: 0.05), .scaleY(to: 0.68, duration: 0.05)]),
                .group([.scaleX(to: 1.0, duration: 0.16), .scaleY(to: 1.0, duration: 0.16)]),
            ])
            ballSprite.run(squash, withKey: "deathSquash")

            // Speed is hierarchical, so this freezes the shake and the camera-space fades for
            // one beat. The restore runs on the scene, which is never slowed.
            if let camera {
                camera.speed = 0
                scene.run(.sequence([
                    .wait(forDuration: hitStopDuration),
                    .run { [weak camera] in camera?.speed = 1 },
                ]), withKey: "hitStop")
            }
        }
    }

    // MARK: - Helpers

    private func spawn(_ emitter: SKEmitterNode, at point: CGPoint, in scene: SKScene, z: CGFloat) {
        emitter.position = point
        emitter.zPosition = z
        scene.addChild(emitter)
        let life = TimeInterval(emitter.particleLifetime + emitter.particleLifetimeRange)
        emitter.run(.sequence([.wait(forDuration: life + 0.1), .removeFromParent()]))
    }

    /// Walnut-toned splinters thrown upward and falling back under gravity.
    private static let chipTemplate: SKEmitterNode = {
        let e = SKEmitterNode()
        e.particleTexture = chipTexture
        e.particleBirthRate = 800
        e.particleLifetime = 0.45
        e.particleLifetimeRange = 0.2
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi * 0.85
        e.particleSpeed = 140
        e.particleSpeedRange = 70
        e.yAcceleration = -620
        // Spread across the gap width so chips come off both plank edges.
        e.particlePositionRange = CGVector(dx: 60, dy: 4)
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = 8
        e.particleScale = 1
        e.particleScaleRange = 0.5
        e.particleScaleSpeed = -0.9
        e.particleAlpha = 0.95
        e.particleAlphaSpeed = -1.4
        e.particleColor = SKColor(red: 0.86, green: 0.58, blue: 0.34, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleColorRedRange = 0.1
        e.particleColorGreenRange = 0.12
        e.particleBlendMode = .alpha
        return e
    }()

    /// Small additive embers for a live streak bonus.
    private static let sparkTemplate: SKEmitterNode = {
        let e = SKEmitterNode()
        e.particleTexture = sparkTexture
        e.particleBirthRate = 800
        e.particleLifetime = 0.4
        e.particleLifetimeRange = 0.15
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi * 0.7
        e.particleSpeed = 210
        e.particleSpeedRange = 90
        e.yAcceleration = -300
        e.particlePositionRange = CGVector(dx: 40, dy: 4)
        e.particleScale = 0.9
        e.particleScaleRange = 0.4
        e.particleScaleSpeed = -1.5
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -2.0
        e.particleColor = SKColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        return e
    }()

    private static let chipTexture: SKTexture = {
        let size = CGSize(width: 7, height: 3)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1).fill()
        }
        return SKTexture(image: image)
    }()

    private static let sparkTexture: SKTexture = {
        let size = CGSize(width: 10, height: 10)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                     locations: [0, 1]) else { return }
            let c = CGPoint(x: 5, y: 5)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                             endCenter: c, endRadius: 5, options: [])
        }
        return SKTexture(image: image)
    }()

    /// White fading to clear top-to-bottom with a quadratic falloff; tinted red by the sprite.
    private static let glowTexture: SKTexture = {
        let size = CGSize(width: 4, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let stops: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
            let colors = stops.map { UIColor.white.withAlphaComponent(pow(1 - $0, 2)).cgColor } as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                     locations: stops) else { return }
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height),
                                             options: [])
        }
        return SKTexture(image: image)
    }()
}
