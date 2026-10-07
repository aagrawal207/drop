import SpriteKit

/// A faint line in the world at the depth of the player's deepest run, so a new run has a
/// visible target. Lives in world space, not on the camera, so it scrolls with the floors.
final class BestDropMarker {
    static let gold = SKColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
    /// Below the floor's underside, clear of the plank but well above the next floor.
    static let offsetBelowFloor: CGFloat = 30
    private static let restingAlpha: CGFloat = 0.6

    let node = SKNode()
    let y: CGFloat
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var passed = false

    /// Floor k (1-based) relies on floors being laid exactly `spacing` apart from the first.
    static func y(forFloor k: Int, firstFloorY: CGFloat, spacing: CGFloat) -> CGFloat {
        firstFloorY - CGFloat(k - 1) * spacing - offsetBelowFloor
    }

    init(y: CGFloat, fieldWidth: CGFloat) {
        self.y = y
        node.position = CGPoint(x: 0, y: y)
        node.zPosition = 1          // under the ball, over the background
        node.alpha = Self.restingAlpha

        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: fieldWidth, y: 0))
        let line = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: [10, 8]))
        line.strokeColor = Self.gold.withAlphaComponent(0.7)
        line.lineWidth = 2
        node.addChild(line)

        label.text = "BEST DROP"
        label.fontSize = 13
        label.fontColor = Self.gold
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: fieldWidth - 12, y: -5)
        node.addChild(label)
    }

    /// True only on the first call where the ball is below the line, then it celebrates.
    func checkPassed(ballY: CGFloat) -> Bool {
        guard !passed, ballY < y else { return false }
        passed = true
        node.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.12),
            .wait(forDuration: 0.5),
            .fadeAlpha(to: Self.restingAlpha, duration: 0.6),
        ]))
        label.run(.sequence([.scale(to: 1.35, duration: 0.12), .scale(to: 1, duration: 0.25)]))
        return true
    }

    /// A short-lived callout for the camera; it removes itself after about 1.2s.
    static func celebrationLabel(at position: CGPoint) -> SKNode {
        let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        l.text = "Past your best drop!"
        l.fontSize = 18
        l.fontColor = gold
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .top
        l.position = position
        l.zPosition = 10
        l.alpha = 0
        l.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .moveBy(x: 0, y: 6, duration: 0.12)]),
            .wait(forDuration: 0.75),
            .fadeOut(withDuration: 0.33),
            .removeFromParent(),
        ]))
        return l
    }
}
