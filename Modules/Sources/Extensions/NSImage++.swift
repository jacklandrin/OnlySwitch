//
//  NSImage++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Cocoa
import AppKit

public extension NSImage {
    var jpgData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [:])
    }
    func jpgWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try jpgData?.write(to: url, options: options)
            return true
        } catch {
            print(error)
            return false
        }
    }
    
    
}

public extension NSImage {

    /// The height of the image.
    var height: CGFloat {
        return size.height
    }

    /// The width of the image.
    var width: CGFloat {
        return size.width
    }

    /// A PNG representation of the image.
    var PNGRepresentation: Data? {
        if let tiff = self.tiffRepresentation, let tiffData = NSBitmapImageRep(data: tiff) {
            return tiffData.representation(using: .png, properties: [:])
        }

        return nil
    }

    // MARK: Resizing
    /// Resize the image to the given size.
    ///
    /// - Parameter size: The size to resize the image to.
    /// - Returns: The resized image.
    func resize(withSize targetSize: NSSize) -> NSImage? {
        let frame = NSRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        guard let representation = self.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }
        let image = NSImage(size: targetSize, flipped: false, drawingHandler: { (_) -> Bool in
            return representation.draw(in: frame)
        })

        return image
    }

    /// Copy the image and resize it to the supplied size, while maintaining it's
    /// original aspect ratio.
    ///
    /// - Parameter size: The target size of the image.
    /// - Returns: The resized image.
    func resizeMaintainingAspectRatio(withSize targetSize: NSSize) -> NSImage? {
        let newSize: NSSize
        let widthRatio  = targetSize.width / self.width
        let heightRatio = targetSize.height / self.height

        if widthRatio > heightRatio {
            newSize = NSSize(width: floor(self.width * widthRatio),
                             height: floor(self.height * widthRatio))
        } else {
            newSize = NSSize(width: floor(self.width * heightRatio),
                             height: floor(self.height * heightRatio))
        }
        return self.resize(withSize: newSize)
    }

    // MARK: Cropping
    /// Resize the image, to nearly fit the supplied cropping size
    /// and return a cropped copy the image.
    ///
    /// - Parameter size: The size of the new image.
    /// - Returns: The cropped image.
    func crop(toSize targetSize: NSSize) -> NSImage? {
        guard let resizedImage = self.resizeMaintainingAspectRatio(withSize: targetSize) else {
            return nil
        }
        let x     = floor((resizedImage.width - targetSize.width) / 2)
        let y     = floor((resizedImage.height - targetSize.height) / 2)
        let frame = NSRect(x: x, y: y, width: targetSize.width, height: targetSize.height)

        guard let representation = resizedImage.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        let image = NSImage(size: targetSize,
                            flipped: false,
                            drawingHandler: { (destinationRect: NSRect) -> Bool in
            return representation.draw(in: destinationRect)
        })

        return image
    }

    // MARK: Saving
    /// Save the images PNG representation the the supplied file URL:
    ///
    /// - Parameter url: The file URL to save the png file to.
    /// - Throws: An unwrappingPNGRepresentationFailed when the image has no png representation.
    func savePngTo(url: URL) throws {
        if let png = self.PNGRepresentation {
            try png.write(to: url, options: .atomicWrite)
        } else {
            throw NSImageExtensionError.unwrappingPNGRepresentationFailed
        }
    }
}


/// Exceptions for the image extension class.
///
/// - creatingPngRepresentationFailed: Is thrown when the creation of the png representation failed.
public enum NSImageExtensionError: Error {
    case unwrappingPNGRepresentationFailed
}

public extension NSImage {
    var heic: Data? {
        return NSBitmapImageRep.representationOfImageReps(in: self.representations, using: .tiff, properties: [:])
    }
    
    func heicWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try heic?.write(to: url, options: options)
            return true
        } catch {
            print(error)
            return false
        }
    }
}
