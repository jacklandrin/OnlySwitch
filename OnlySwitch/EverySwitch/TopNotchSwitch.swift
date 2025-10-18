//
//  TopNotchSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Cocoa
import UniformTypeIdentifiers
import AVFoundation
import Switches
import Defines
import OSLog

final class TopNotchSwitch: SwitchProvider, CurrentScreen {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .topNotch
    // MARK: - private properties
    
    private var currentImageName = ""
    private var notchHeight:CGFloat = 0
    
    // MARK:- SwitchProvider functions

    @MainActor
    func currentStatus() async -> Bool {
        let workspace = NSWorkspace.shared
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        guard let screen = getScreenWithMouse() else {return false}
        guard let path = workspace.desktopImageURL(for: screen) else {return false}
    
        if path.absoluteString.contains("/\(appBundleID)/processed") {
            currentImageName = path.lastPathComponent
            return true
        } else {
            return false
        }
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        var success = false
        if isOn {
            success = await hiddenNotch()
        } else {
            success = await recoverNotch()
        }
        if !success {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return self.isNotchScreen
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }
    
    // MARK: - private functions
    
    private var isNotchScreen: Bool {
        if #available(macOS 12, *) {
            guard let screen = getScreenWithMouse() else { return false }
            guard let topLeftArea = screen.auxiliaryTopLeftArea, let _ = screen.auxiliaryTopRightArea else {return false}
            
            notchHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? (topLeftArea.height + 5) //auxiliaryTopLeftArea is not equivalent to menubar's height
            Logger.internalSwitch.debug("get notchHeight:\(self.notchHeight)")
            return true
        } else {
            return false
        }
    }
    
    private var myAppPath: String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }

    @MainActor
    private func recoverNotch() async -> Bool {
        let originalPath = myAppPath?.appendingPathComponent(string: "original", currentImageName)
        guard let originalPath = originalPath else {return false}
        let success = setDesktopImageURL(url: URL(fileURLWithPath: originalPath))
        if success {
            _ = await currentStatus()
        }
        
        return success
    }
  
    @MainActor private func hiddenNotch() async -> Bool {
        let workspace = NSWorkspace.shared
        guard let screen = getScreenWithMouse() else {return false}
        guard let path = workspace.desktopImageURL(for: screen) else {return false}
        if let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as? String,
           let myAppPath,
           path.absoluteString.contains("/\(appBundleID)/original") {
            currentImageName = URL(fileURLWithPath: path.absoluteString).lastPathComponent
            let processdUrl = myAppPath.appendingPathComponent(string: "processed", currentImageName)
            if FileManager.default.fileExists(atPath: processdUrl) {
                return setDesktopImageURL(url: URL(fileURLWithPath: processdUrl))
            }
        }
        Logger.internalSwitch.debug("original path:\(path)")
        guard let currentWallpaperImage = NSImage(contentsOf: path) else {
            return false
        }
        if path.pathExtension == "heic" {
            var metaDataTag:HeicMetaDataTag?
            do {
                let imagaDate = try Data(contentsOf: path)
                metaDataTag = try extractMetaData(imageData: imagaDate)
            } catch {
                return false
            }

            guard let metaDataTag = metaDataTag else {
                return false
            }

            let success = hideHeicDesktopNotch(image: currentWallpaperImage, metaDataTag: metaDataTag)
            _ = await currentStatus()
            return success
        } else {
            let success = hideSingleDesktopNotch(image: currentWallpaperImage)
            _ = await currentStatus()
            return success
        }
    }
    
    private func extractMetaData(imageData:Data) throws -> HeicMetaDataTag{
        let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)
        guard let imageSourceValue = imageSource else {
            throw MetadataExtractorError.imageSourceNotCreated
        }
        
        let imageMetadata = CGImageSourceCopyMetadataAtIndex(imageSourceValue, 0, nil)
        guard let imageMetadataValue = imageMetadata else {
            throw MetadataExtractorError.imageMetadataNotCreated
        }
        var tagType:String = ""
        var plist:String = ""
        CGImageMetadataEnumerateTagsUsingBlock(imageMetadataValue, nil, nil) { (value, metadataTag) -> Bool in

            let valueString = value as String
            Logger.internalSwitch.debug("---------------------------------------------------")
            Logger.internalSwitch.debug("Metadata key: \(valueString)")

            let tag = CGImageMetadataTagCopyValue(metadataTag)
            
            guard let valueTag = tag as? String else {
                print("\tError during convert tag into string")
                return true
            }
            print(valueTag)
            if valueString.starts(with: "apple_desktop:solar") {
                tagType = "solar"
                plist = valueTag
            } else if valueString.starts(with: "apple_desktop:h24") {
                tagType = "h24"
                plist = valueTag
            } else if valueString.starts(with: "apple_desktop:apr") {
                tagType = "apr"
                plist = valueTag
            }
            return true
        }
        return HeicMetaDataTag(type: tagType, plist: plist)
    }
    
    private func hideHeicDesktopNotch(image:NSImage, metaDataTag:HeicMetaDataTag) -> Bool {
        let imageReps = image.representations
        if imageReps.count == 1 && metaDataTag.type == "" {
            return hideSingleDesktopNotch(image: image)
        }
        
        var imageData: Data? = nil
        let destinationData = NSMutableData()
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9]
        
        guard let imageDestination = CGImageDestinationCreateWithData(destinationData, AVFileType.heic as CFString, imageReps.count, nil) else {return false}
        
        for index in 0..<imageReps.count {
            if let imageRep = imageReps[index] as? NSBitmapImageRep {
                let nsImage = NSImage()
                nsImage.addRepresentation(imageRep)
                if let processedImage = hideNotchForEachImageOfHeic(image:nsImage) {
                    if index == 0 {
                        let imageMetaData = CGImageMetadataCreateMutable()
                        let imageMetaDataTag = CGImageMetadataTagCreate("http://ns.apple.com/namespace/1.0/" as CFString,
                                                                        "apple_desktop" as CFString,
                                                                        metaDataTag.type as CFString,
                                                                        CGImageMetadataType.string,
                                                                        metaDataTag.plist as CFTypeRef)
                        let success = CGImageMetadataSetTagWithPath(imageMetaData, nil, "xmp:\(metaDataTag.type)" as CFString, imageMetaDataTag!)
                        if !success {
                            return false
                        }
                        
                        CGImageDestinationAddImageAndMetadata(imageDestination, processedImage, imageMetaData, options as CFDictionary)
                    } else {
                        CGImageDestinationAddImage(imageDestination, processedImage, options as CFDictionary)
                    }
                }
            }
        }
        
        CGImageDestinationFinalize(imageDestination)
        imageData = destinationData as Data
        let imageName = UUID().uuidString
        guard let url = saveHeicData(data:imageData, isProcessed: true, imageName: imageName) else {return false}
        let _ = saveHeicData(image: image, isProcessed: false, imageName: imageName)
        let success = setDesktopImageURL(url: url)
        return success
    }
    
    private func hideNotchForEachImageOfHeic(image:NSImage) -> CGImage? {
        guard let finalCGImage = addBlackRect(on: image) else {return nil}
        return finalCGImage
    }
    
    
    
    private func hideSingleDesktopNotch(image:NSImage) -> Bool {
        
        let finalCGImage = addBlackRect(on: image)
        
        guard let finalCGImage = finalCGImage else {
            return false
        }

        let imageName = UUID().uuidString
        guard let imageUrl = saveCGImage(finalCGImage, isProcessed: true, imageName: imageName) else {return false}
        let _ = saveImage(image, isProcessed: false, imageName: imageName)
        
        return setDesktopImageURL(url:imageUrl)
    }
    
    
    private func addBlackRect(on image:NSImage) -> CGImage? {
        var screenSize:CGSize = .zero
        if let screen = getScreenWithMouse() {
            screenSize = screen.visibleFrame.size
            Logger.internalSwitch.debug("screenSize:\(screenSize.width) * \(screenSize.height)")
        }
        
        let nsscreenSize = NSSize(width: screenSize.width,
                                  height: screenSize.height)
        guard let resizeWallpaperImage = image
            .resizeMaintainingAspectRatio(withSize: nsscreenSize) else { return nil }

        var imageRect = CGRect(origin: .zero,
                               size: CGSize(width: resizeWallpaperImage.width,
                                            height: resizeWallpaperImage.height))
        guard let cgwallpaper = resizeWallpaperImage
            .cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else {
            return nil
        }
        
        guard let finalWallpaper = cgwallpaper.crop(toSize: screenSize) else { return nil }

        Logger.internalSwitch.debug("notchHeight\(self.notchHeight)")
        var finalCGImage:CGImage? = nil

        if let context = createContext(size: screenSize) {
            context.draw(finalWallpaper, in: CGRect(origin: .zero, size: screenSize))
            context.setFillColor(.black)
            context.fill(CGRect(origin: CGPoint(x: 0, y: screenSize.height - notchHeight), size: CGSize(width: screenSize.width, height: notchHeight)))
            finalCGImage = context.makeImage()
        }
        return finalCGImage
    }
    
    private func setDesktopImageURL(url:URL) -> Bool {
        do {
            let workspace = NSWorkspace.shared
            guard let screen = getScreenWithMouse() else {return false}
            try workspace.setDesktopImageURL(url, for: screen, options: [:])
        } catch {
            return false
        }
        return true
    }
        
    private func saveImage(_ image:NSImage, isProcessed:Bool, imageName:String) -> URL? {
        guard let destinationURL = saveDestination(isProcessed: isProcessed, imageName: imageName, type: "jpg") else {
            return nil
        }
        if image.jpgWrite(to: destinationURL, options: .withoutOverwriting) {
            Logger.internalSwitch.debug("destinationURL:\(destinationURL)")
            return destinationURL
        }
        return nil
    }
    
    private func saveCGImage(_ image: CGImage, isProcessed:Bool, imageName:String) -> URL? {
        guard let destinationURL = saveDestination(isProcessed: isProcessed, imageName: imageName, type: "jpg") else {
            return nil
        }
        let cfdestinationURL = destinationURL as CFURL
        let destination = CGImageDestinationCreateWithURL(cfdestinationURL,  UTType.jpeg.identifier as CFString as CFString, 1, nil)
        guard let destination = destination else {return nil}
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            return nil
        }
        return destinationURL as URL
    }
    
    
    private func saveHeicData(image:NSImage, isProcessed:Bool, imageName:String) -> URL? {
        guard let destinationURL = saveDestination(isProcessed: isProcessed, imageName: imageName, type: "heic") else {
            return nil
        }
        if image.heicWrite(to: destinationURL, options: .withoutOverwriting) {
            Logger.internalSwitch.debug("destinationURL:\(destinationURL)")
            return destinationURL
        }
        return nil
    }
    
    private func saveHeicData(data:Data?, isProcessed:Bool, imageName:String) -> URL? {
        guard let destinationURL = saveDestination(isProcessed: isProcessed, imageName: imageName, type: "heic") else {
            return nil
        }
        do {
            try data?.write(to: destinationURL, options: .withoutOverwriting)
            Logger.internalSwitch.debug("destinationURL:\(destinationURL)")
            return destinationURL
        } catch {
            return nil
        }
        
    }
    
    private func saveDestination(isProcessed:Bool, imageName:String, type:String) -> URL? {
        let imagePath = myAppPath?.appendingPathComponent(string: isProcessed ? "processed" : "original")
        guard let imagePath = imagePath else {return nil}
        if !FileManager.default.fileExists(atPath: imagePath) {
            do {
                try FileManager.default.createDirectory(atPath: imagePath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return nil
            }
        }
        let destinationPath = imagePath.appendingPathComponent(string: "\(imageName).\(type)")
        let destinationURL = URL(fileURLWithPath: destinationPath)
        return destinationURL
    }
    
    private func createContext(size: CGSize) -> CGContext? {
        return CGContext(data: nil,
                         width: Int(size.width),
                         height: Int(size.height),
                         bitsPerComponent: 8,
                         bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }
}

struct HeicMetaDataTag {
    let type:String // solor, h24, apr
    let plist:String //base64 Property List
}
