import CoreGraphics

public enum DesktopPetDockEdge: Equatable, Sendable {
    case left
    case right
}

public enum DesktopPetEdgeDocking {
    /// Width of the strip along the screen edge that brings a hidden pet back.
    static let revealZoneWidth: CGFloat = 4
    /// Slack around a revealed pet so small mouse overshoots do not hide it again.
    static let revealedHoverMargin: CGFloat = 12
    /// How close to the edge the mouse must come before the hidden pet peeks out.
    static let approachDistance: CGFloat = 96
    static let approachVerticalMargin: CGFloat = 48
    /// Width of artwork left on screen while peeking.
    static let peekWidth: CGFloat = 56
    static let peekTilt: Double = 16

    /// The edge the pet is pushed against, unless another display continues past it there.
    public static func dockEdge(
        for frame: CGRect,
        visibleFrame: CGRect,
        screenFrame: CGRect,
        screenFrames: [CGRect]
    ) -> DesktopPetDockEdge? {
        let edge: DesktopPetDockEdge
        if frame.minX <= visibleFrame.minX {
            edge = .left
        } else if frame.maxX >= visibleFrame.maxX {
            edge = .right
        } else {
            return nil
        }

        let hiddenFrame = hiddenFrame(for: frame, edge: edge, screenFrame: screenFrame)
        let continuesOntoAnotherDisplay = screenFrames.contains { other in
            other != screenFrame && other.intersects(hiddenFrame)
        }
        return continuesOntoAnotherDisplay ? nil : edge
    }

    public static func hiddenFrame(
        for restingFrame: CGRect,
        edge: DesktopPetDockEdge,
        screenFrame: CGRect
    ) -> CGRect {
        var result = restingFrame
        switch edge {
        case .left:
            result.origin.x = screenFrame.minX - restingFrame.width
        case .right:
            result.origin.x = screenFrame.maxX
        }
        return result
    }

    public static func frame(
        for phase: DesktopPetEdgePhase,
        restingFrame: CGRect,
        edge: DesktopPetDockEdge,
        screenFrame: CGRect
    ) -> CGRect {
        switch phase {
        case .hidden:
            return hiddenFrame(for: restingFrame, edge: edge, screenFrame: screenFrame)
        case .peeking:
            let artworkInset = DesktopPetMetrics.artworkFrame.minX
            var result = restingFrame
            switch edge {
            case .left:
                result.origin.x = screenFrame.minX + peekWidth - (restingFrame.width - artworkInset)
            case .right:
                result.origin.x = screenFrame.maxX - artworkInset - peekWidth
            }
            return result
        case .revealed:
            return restingFrame
        }
    }

    /// Degrees the artwork leans toward the screen so the peeking head pokes out of the edge.
    public static func tilt(for phase: DesktopPetEdgePhase, edge: DesktopPetDockEdge) -> Double {
        guard phase == .peeking else { return 0 }
        return edge == .left ? peekTilt : -peekTilt
    }

    /// Peeks while the mouse approaches the edge, pops out once it touches the edge,
    /// and stays out until the mouse leaves the revealed pet.
    public static func phase(
        forMouseLocation mouseLocation: CGPoint,
        restingFrame: CGRect,
        edge: DesktopPetDockEdge,
        screenFrame: CGRect,
        current: DesktopPetEdgePhase
    ) -> DesktopPetEdgePhase {
        let revealZone = edgeStrip(width: revealZoneWidth, restingFrame: restingFrame, edge: edge, screenFrame: screenFrame)
        if revealZone.contains(mouseLocation) {
            return .revealed
        }
        if current == .revealed,
           restingFrame.insetBy(dx: -revealedHoverMargin, dy: -revealedHoverMargin).contains(mouseLocation) {
            return .revealed
        }
        let approachZone = edgeStrip(width: approachDistance, restingFrame: restingFrame, edge: edge, screenFrame: screenFrame)
            .insetBy(dx: 0, dy: -approachVerticalMargin)
        return approachZone.contains(mouseLocation) ? .peeking : .hidden
    }

    private static func edgeStrip(
        width: CGFloat,
        restingFrame: CGRect,
        edge: DesktopPetDockEdge,
        screenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: edge == .left ? screenFrame.minX : screenFrame.maxX - width,
            y: restingFrame.minY,
            width: width,
            height: restingFrame.height
        )
    }
}

public enum DesktopPetEdgePhase: Equatable, Sendable {
    case hidden
    case peeking
    case revealed
}

/// How the panel springs between edge phases; underdamped presets give the cartoon overshoot.
public enum DesktopPetSpringMotion: Equatable, Sendable {
    case peek(edge: DesktopPetDockEdge)
    case pop(edge: DesktopPetDockEdge)
    case hide(edge: DesktopPetDockEdge)

    var stiffness: CGFloat {
        switch self {
        case .peek: 220
        case .pop: 320
        case .hide: 110
        }
    }

    var damping: CGFloat {
        switch self {
        case .peek: 20
        case .pop: 14
        case .hide: 18
        }
    }

    /// Pop leaps inward with a hop; hide winds up toward the screen before ducking away.
    var initialVelocity: CGVector {
        switch self {
        case .peek:
            .zero
        case let .pop(edge):
            CGVector(dx: edge.inward * 300, dy: 700)
        case let .hide(edge):
            CGVector(dx: edge.inward * 260, dy: 0)
        }
    }
}

public struct DesktopPetSpring: Equatable, Sendable {
    public private(set) var position: CGPoint
    public private(set) var isSettled = false
    public let target: CGPoint
    private var velocity: CGVector
    private let motion: DesktopPetSpringMotion

    public init(position: CGPoint, target: CGPoint, motion: DesktopPetSpringMotion) {
        self.position = position
        self.target = target
        self.motion = motion
        velocity = motion.initialVelocity
    }

    public mutating func step(by duration: CGFloat) {
        guard !isSettled else { return }

        let substeps = max(1, Int((duration * 240).rounded(.up)))
        let delta = duration / CGFloat(substeps)
        for _ in 0..<substeps {
            velocity.dx += (-motion.stiffness * (position.x - target.x) - motion.damping * velocity.dx) * delta
            velocity.dy += (-motion.stiffness * (position.y - target.y) - motion.damping * velocity.dy) * delta
            position.x += velocity.dx * delta
            position.y += velocity.dy * delta
        }

        if hypot(position.x - target.x, position.y - target.y) < 0.5,
           hypot(velocity.dx, velocity.dy) < 8 {
            position = target
            isSettled = true
        }
    }
}

private extension DesktopPetDockEdge {
    /// Horizontal direction pointing from this edge into the screen.
    var inward: CGFloat {
        self == .left ? 1 : -1
    }
}
