#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Screenshots

struct RGBA: Equatable { var r, g, b, a: UInt8 }

/// Decoded RGBA8 sRGB pixels; `pixel(x, y)` uses a top-left origin.
struct PixelBuffer {
    let width: Int, height: Int, bytes: [UInt8]
    init(_ image: CGImage) {
        width = image.width; height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }
    func pixel(_ x: Int, _ y: Int) -> RGBA {
        let i = (y * width + x) * 4
        return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }
}

let white = RGBA(r: 255, g: 255, b: 255, a: 255)

/// Draws with a top-left origin so fixtures read like the annotation coordinates.
func fixtureImage(width: Int = 100, height: Int = 80, _ draw: (CGContext) -> Void = { _ in }) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    draw(context)
    return try #require(context.makeImage())
}

func checkerboard() throws -> CGImage {
    try fixtureImage { context in
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for y in stride(from: 0, to: 80, by: 4) { for x in stride(from: 0, to: 100, by: 4) where (x / 4 + y / 4).isMultiple(of: 2) {
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
        } }
    }
}

struct ScreenshotRendererTests {
    let size = CGSize(width: 100, height: 80)
    let red = AnnotationStyle(color: RGBAColor(red: 1, green: 0, blue: 0), lineWidth: 4)

    @Test func emptyDocumentReturnsIdenticalPixels() throws {
        let source = try checkerboard()
        let output = try #require(ScreenshotRenderer.render(source, document: .init(pixelSize: size)))
        #expect(output.width == 100 && output.height == 80)
        #expect(PixelBuffer(output).bytes == PixelBuffer(source).bytes)
    }

    @Test func rectangleStrokePaintsEdgeNotInterior() throws {
        let document = ScreenshotEditDocument(pixelSize: size, annotations: [.rectangle(CGRect(x: 20, y: 20, width: 40, height: 30), red)])
        let output = PixelBuffer(try #require(ScreenshotRenderer.render(try fixtureImage(), document: document)))
        #expect(output.pixel(20, 35) == RGBA(r: 255, g: 0, b: 0, a: 255))
        #expect(output.pixel(40, 20) == RGBA(r: 255, g: 0, b: 0, a: 255))
        #expect(output.pixel(40, 35) == white)
        #expect(output.pixel(5, 5) == white)
    }

    @Test func blurChangesPixelsInsideRegionOnly() throws {
        let source = try checkerboard()
        let region = CGRect(x: 20, y: 20, width: 40, height: 30)
        let output = PixelBuffer(try #require(ScreenshotRenderer.render(source, document: .init(pixelSize: size, annotations: [.blur(region)]))))
        let original = PixelBuffer(source)
        for y in 0..<80 { for x in 0..<100 where !region.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
            #expect(output.pixel(x, y) == original.pixel(x, y), "outside pixel (\(x), \(y)) changed")
        } }
        // Well inside the region the 4px checkerboard is averaged into gray.
        for (x, y) in [(30, 30), (40, 35), (50, 40)] {
            let value = output.pixel(x, y).r
            #expect(value > 60 && value < 195, "pixel (\(x), \(y)) = \(value) is not blurred")
        }
    }

    @Test func blurSuppressesCoarseHighContrastContent() throws {
        let source = try fixtureImage(width: 800, height: 600) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            for x in stride(from: 0, to: 800, by: 128) {
                context.fill(CGRect(x: x, y: 0, width: 64, height: 600))
            }
        }
        let region = CGRect(x: 128, y: 128, width: 384, height: 256)
        let output = PixelBuffer(try #require(ScreenshotRenderer.render(source, document: .init(pixelSize: CGSize(width: 800, height: 600), annotations: [.blur(region)]))))
        let dark = Int(output.pixel(288, 300).r)
        let light = Int(output.pixel(352, 300).r)
        #expect(abs(light - dark) < 45, "64px details remain too legible: dark=\(dark), light=\(light)")
        #expect(output.pixel(32, 300) == PixelBuffer(source).pixel(32, 300))
    }

    @Test func cachedFullImageBlurMatchesSavedRegionPixels() throws {
        let source = try fixtureImage(width: 320, height: 240) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 20, y: 30, width: 160, height: 60))
            context.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
            context.fill(CGRect(x: 60, y: 150, width: 210, height: 70))
        }
        let region = CGRect(x: 40, y: 25, width: 180, height: 80)
        let cached = PixelBuffer(try #require(ScreenshotRenderer.blurredImage(source)))
        let saved = PixelBuffer(try #require(ScreenshotRenderer.render(source, document: .init(pixelSize: CGSize(width: 320, height: 240), annotations: [.blur(region)]))))
        #expect(cached.width == 320 && cached.height == 240)
        for y in 26..<104 { for x in 41..<219 {
            #expect(saved.pixel(x, y) == cached.pixel(x, y), "preview/save blur mismatch at (\(x),\(y))")
        } }
    }

    @Test func cropProducesCroppedSizeAndOrigin() throws {
        let source = try fixtureImage { context in
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 10, y: 20, width: 1, height: 1))
        }
        let output = try #require(ScreenshotRenderer.render(source, document: .init(pixelSize: size, crop: CGRect(x: 10, y: 20, width: 30, height: 40))))
        #expect(output.width == 30 && output.height == 40)
        let pixels = PixelBuffer(output)
        #expect(pixels.pixel(0, 0) == RGBA(r: 0, g: 255, b: 0, a: 255))
        #expect(pixels.pixel(1, 0) == white)
        #expect(pixels.pixel(0, 1) == white)
    }

    @Test func topLeftCoordinatesAreNotFlipped() throws {
        let document = ScreenshotEditDocument(pixelSize: size, annotations: [.stroke([CGPoint(x: 3, y: 5.5), CGPoint(x: 8, y: 5.5)], AnnotationStyle(color: RGBAColor(red: 1, green: 0, blue: 0), lineWidth: 1))])
        let output = PixelBuffer(try #require(ScreenshotRenderer.render(try fixtureImage(), document: document)))
        #expect(output.pixel(5, 5) == RGBA(r: 255, g: 0, b: 0, a: 255))
        #expect(output.pixel(5, 74) == white)
    }

    @Test func encodePreservesTypeForPNGAndJPEG() throws {
        let source = try checkerboard()
        for type in [UTType.png, .jpeg] {
            let data = try #require(ScreenshotRenderer.encode(source, as: type))
            let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(decoded) as String? == type.identifier)
            let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            #expect(image.width == 100 && image.height == 80)
        }
        #expect(ScreenshotRenderer.outputType(for: URL(fileURLWithPath: "/a/Shot.JPG")) == .jpeg)
        #expect(ScreenshotRenderer.outputType(for: URL(fileURLWithPath: "/a/Shot.png")) == .png)
        #expect(ScreenshotRenderer.outputType(for: URL(fileURLWithPath: "/a/Shot.txt")) == .png)
        #expect(ScreenshotRenderer.outputType(for: URL(fileURLWithPath: "/a/Shot")) == .png)
    }
}
#endif
