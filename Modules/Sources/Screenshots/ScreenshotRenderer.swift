#if os(macOS)
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pure, stateless flattening of an edit document onto its source image. Order: base image → blur regions →
/// vector annotations → crop. Pixels outside blur regions never pass through Core Image, so they are unchanged.
public enum ScreenshotRenderer {
    public static func render(_ image: CGImage, document: ScreenshotEditDocument) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let space = image.colorSpace.flatMap { $0.supportsOutput && $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .none
        context.draw(image, in: full)

        let pixelDocument = ScreenshotEditDocument(pixelSize: CGSize(width: width, height: height))
        let blurRegions = document.annotations.compactMap { annotation -> CGRect? in
            if case let .blur(rect) = annotation { return pixelDocument.clampedRegion(rect) }
            return nil
        }
        if !blurRegions.isEmpty {
            guard let blurred = blurredImage(image) else { return nil }
            context.saveGState()
            context.beginPath()
            for region in blurRegions {
                // Annotation coordinates are top-left; the unflipped bitmap context is bottom-left.
                let target = CGRect(x: region.minX, y: CGFloat(height) - region.maxY, width: region.width, height: region.height)
                context.addRect(target)
            }
            context.clip()
            context.draw(blurred, in: full)
            context.restoreGState()
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .default
        for annotation in document.annotations { draw(annotation, in: context) }

        guard let flattened = context.makeImage() else { return nil }
        guard let crop = document.crop, let rect = pixelDocument.clampedCrop(crop), rect != full else { return flattened }
        // CGImage cropping uses the image's top-left pixel origin.
        return flattened.cropping(to: rect)
    }

    public static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let lossy = type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
        let options: [CFString: Any] = lossy ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The original file's type from its extension when ImageIO can write it, otherwise PNG.
    public static func outputType(for url: URL) -> UTType {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()), type.conforms(to: .image) else { return .png }
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return writable.contains(type.identifier) ? type : .png
    }

    /// Full-resolution decode for editing; nil when the file is missing or not an image.
    public static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// One full-resolution Gaussian image shared by saved output and the editor's cached preview.
    public static func blurredImage(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let source = CIImage(cgImage: image)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        let filter = CIFilter.gaussianBlur()
        filter.radius = Float(blurRadius(for: CGSize(width: image.width, height: image.height)))
        filter.inputImage = source.clampedToExtent()
        guard let output = filter.outputImage else { return nil }
        let space = image.colorSpace.flatMap { $0.supportsOutput && $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: space)
    }

    static func blurRadius(for size: CGSize) -> CGFloat { max(64, 0.08 * min(size.width, size.height)) }
    static func arrowHeadLength(for lineWidth: CGFloat) -> CGFloat { max(12, lineWidth * 4) }

    /// Expects a top-left-origin (flipped) context.
    static func draw(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.setLineCap(.round); context.setLineJoin(.round)
        switch annotation {
        case let .stroke(points, style):
            guard let first = points.first else { return }
            apply(style, to: context)
            context.beginPath(); context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            if points.count == 1 { context.addLine(to: first) }
            context.strokePath()
        case let .rectangle(rect, style):
            apply(style, to: context); context.setLineJoin(.miter)
            context.stroke(rect.standardized)
        case let .ellipse(rect, style):
            apply(style, to: context)
            context.strokeEllipse(in: rect.standardized)
        case let .arrow(from, to, style):
            apply(style, to: context)
            let head = arrowHead(from: from, to: to, lineWidth: style.lineWidth)
            context.beginPath(); context.move(to: from); context.addLine(to: head.base); context.strokePath()
            context.beginPath(); context.move(to: to); context.addLine(to: head.left); context.addLine(to: head.right); context.closePath()
            context.fillPath()
        case .blur:
            return
        }
    }

    /// Head triangle (tip at `to`) and the point where the shaft meets it.
    static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (left: CGPoint, right: CGPoint, base: CGPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let length = min(arrowHeadLength(for: lineWidth), hypot(to.x - from.x, to.y - from.y))
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: to.x - length * cos(angle - spread), y: to.y - length * sin(angle - spread))
        let right = CGPoint(x: to.x - length * cos(angle + spread), y: to.y - length * sin(angle + spread))
        let base = CGPoint(x: to.x - length * cos(spread) * cos(angle), y: to.y - length * cos(spread) * sin(angle))
        return (left, right, base)
    }

    private static func apply(_ style: AnnotationStyle, to context: CGContext) {
        context.setStrokeColor(style.color.cgColor); context.setFillColor(style.color.cgColor)
        context.setLineWidth(max(1, style.lineWidth))
    }
}
#endif
