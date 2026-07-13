import CoreGraphics

public enum DesktopPetLayout {
    public static func defaultFrame(
        size: CGSize,
        visibleFrame: CGRect,
        inset: CGFloat = 28
    ) -> CGRect {
        CGRect(
            x: visibleFrame.minX + inset,
            y: visibleFrame.minY + inset,
            width: size.width,
            height: size.height
        )
    }

    public static func constrainedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(
            max(frame.origin.x, visibleFrame.minX),
            visibleFrame.maxX - frame.width
        )
        result.origin.y = min(
            max(frame.origin.y, visibleFrame.minY),
            visibleFrame.maxY - frame.height
        )
        return result
    }

    public static func bestScreenIndex(
        for frame: CGRect,
        visibleFrames: [CGRect]
    ) -> Int? {
        guard !visibleFrames.isEmpty else { return nil }

        let intersections = visibleFrames.map { frame.intersection($0) }
        if let largest = intersections.enumerated().max(by: { lhs, rhs in
            lhs.element.area < rhs.element.area
        }), largest.element.area > 0 {
            return largest.offset
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.enumerated().min(by: { lhs, rhs in
            lhs.element.center.distanceSquared(to: center)
                < rhs.element.center.distanceSquared(to: center)
        })?.offset
    }
}

public enum DesktopPetInteraction {
    public static func isClick(
        translation: CGSize,
        threshold: CGFloat = 4
    ) -> Bool {
        hypot(translation.width, translation.height) <= threshold
    }

    public static func draggedOrigin(
        startOrigin: CGPoint,
        startMouseLocation: CGPoint,
        currentMouseLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: startOrigin.x + currentMouseLocation.x - startMouseLocation.x,
            y: startOrigin.y + currentMouseLocation.y - startMouseLocation.y
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let xDistance = x - other.x
        let yDistance = y - other.y
        return xDistance * xDistance + yDistance * yDistance
    }
}
