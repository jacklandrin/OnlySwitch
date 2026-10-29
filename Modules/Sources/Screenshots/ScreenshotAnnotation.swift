#if os(macOS)
import CoreGraphics
import Foundation

public enum ScreenshotTool: String, CaseIterable, Sendable { case pen, rectangle, ellipse, arrow, blur, crop }

/// sRGB color with components in 0...1.
public struct RGBAColor: Equatable, Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }

    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, alpha].map { CGFloat($0) })
            ?? CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public static let red = Self(red: 1, green: 0.23, blue: 0.19)
    public static let orange = Self(red: 1, green: 0.58, blue: 0)
    public static let yellow = Self(red: 1, green: 0.8, blue: 0)
    public static let green = Self(red: 0.2, green: 0.78, blue: 0.35)
    public static let blue = Self(red: 0, green: 0.48, blue: 1)
    public static let white = Self(red: 1, green: 1, blue: 1)
    /// The editor's swatches, in toolbar order.
    public static let palette: [Self] = [.red, .orange, .yellow, .green, .blue, .white]
}

public struct AnnotationStyle: Equatable, Sendable, Codable {
    public var color: RGBAColor
    /// Pixel space.
    public var lineWidth: CGFloat
    public init(color: RGBAColor = .red, lineWidth: CGFloat = 6) { self.color = color; self.lineWidth = lineWidth }
    /// The editor's line-width choices in pixels, in toolbar order.
    public static let lineWidths: [CGFloat] = [3, 6, 12]
}

/// All geometry is in image pixel space with a top-left origin.
public enum ScreenshotAnnotation: Equatable, Sendable {
    case stroke([CGPoint], AnnotationStyle)
    case rectangle(CGRect, AnnotationStyle)
    case ellipse(CGRect, AnnotationStyle)
    case arrow(from: CGPoint, to: CGPoint, AnnotationStyle)
    case blur(CGRect)
}

public struct ScreenshotEditDocument: Equatable, Sendable {
    public static let minimumCropSide: CGFloat = 8

    public var pixelSize: CGSize
    /// Pixel space, top-left origin, in drawing order.
    public var annotations: [ScreenshotAnnotation]
    /// Pixel space, clamped to image bounds, at least 8×8; nil = uncropped.
    public var crop: CGRect?

    public init(pixelSize: CGSize, annotations: [ScreenshotAnnotation] = [], crop: CGRect? = nil) {
        self.pixelSize = pixelSize; self.annotations = annotations; self.crop = crop
    }

    public var bounds: CGRect { CGRect(origin: .zero, size: pixelSize) }

    /// Integral, inside the image, and at least `minimumCropSide` on each side (grown inside the image when
    /// smaller). Nil when the image is smaller than the minimum or the rect does not touch the image.
    public func clampedCrop(_ rect: CGRect) -> CGRect? {
        let side = Self.minimumCropSide
        guard pixelSize.width >= side, pixelSize.height >= side else { return nil }
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull else { return nil }
        var result = clipped.integral.intersection(bounds)
        if result.width < side { result.origin.x = min(result.minX, pixelSize.width - side); result.size.width = side }
        if result.height < side { result.origin.y = min(result.minY, pixelSize.height - side); result.size.height = side }
        return result
    }

    /// Integral and inside the image; nil when nothing is left.
    public func clampedRegion(_ rect: CGRect) -> CGRect? {
        let result = rect.standardized.intersection(bounds).integral.intersection(bounds)
        return result.isNull || result.isEmpty ? nil : result
    }
}
#endif
