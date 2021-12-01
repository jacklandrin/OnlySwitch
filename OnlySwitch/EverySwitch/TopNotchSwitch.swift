//
//  TopNotchSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Cocoa

class TopNotchSwitch:SwitchProtocal {
    static let shared = TopNotchSwitch()
    
    private var currentImageName = ""
    
    private var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
    
    func currentStatus() -> Bool {
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
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            return hiddenNotch()
        } else {
            return recoverNotch()
        }
    }
    
    var isNotchScreen:Bool {
        if #available(macOS 12, *) {
            guard let screen = getScreenWithMouse() else {return false}
            return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        } else {
            return false
        }
    }
    
    private func recoverNotch() -> Bool {
        let originalPath = myAppPath?.appending("/original/\(currentImageName)")
        guard let originalPath = originalPath else {return false}
        let success = setDesktopImageURL(url: URL(fileURLWithPath: originalPath))
        if success {
            let _ = currentStatus()
        }
        
        return success
    }
  
    private func hiddenNotch() -> Bool {
        let workspace = NSWorkspace.shared
        guard let screen = getScreenWithMouse() else {return false}
        guard let path = workspace.desktopImageURL(for: screen) else {return false}
        let success = hideSingleDesktopNotch(imagePath: path)
        let _ = currentStatus()
        return success
    }
    
    
    private func hideSingleDesktopNotch(imagePath:URL) -> Bool {
        print("original path:\(imagePath)")
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        if let myAppPath = myAppPath ,imagePath.absoluteString.contains("/\(appBundleID)/original") {
            currentImageName = URL(fileURLWithPath: imagePath.absoluteString).lastPathComponent
            let processdUrl = myAppPath.appendingPathComponent(string: "processed", currentImageName)
            if FileManager.default.fileExists(atPath: processdUrl) {
                return setDesktopImageURL(url: URL(fileURLWithPath: processdUrl))
            }
        }
        
        guard let currentWallpaperImage = NSImage(contentsOf: imagePath) else {
            return false
        }
        
        var screenSize:CGSize = .zero
        if let screen = getScreenWithMouse() {
            screenSize = screen.visibleFrame.size
            print("screenSize:\(screenSize)")
        }
        
        let nsscreenSize = NSSize(width: screenSize.width, height: screenSize.height)
        guard let resizeWallpaperImage = currentWallpaperImage.resizeMaintainingAspectRatio(withSize: nsscreenSize) else {return false}

        var imageRect = CGRect(origin: .zero, size: CGSize(width: resizeWallpaperImage.width, height: resizeWallpaperImage.height))
        guard let cgwallpaper = resizeWallpaperImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else {
            return false
        }
        guard let finalWallpaper = cgwallpaper.crop(toSize: screenSize) else {return false}
        let notchHeight = NSApplication.shared.mainMenu?.menuBarHeight //auxiliaryTopLeftArea is not equivalent to menubar's height

        guard let notchHeight = notchHeight else {return false}
        
        print("notchHeight\(notchHeight)")
        var finalCGImage:CGImage? = nil

        if let context = createContext(size: screenSize) {
            context.draw(finalWallpaper, in: CGRect(origin: .zero, size: screenSize))
            context.setFillColor(.black)
            context.fill(CGRect(origin: CGPoint(x: 0, y: screenSize.height - notchHeight), size: CGSize(width: screenSize.width, height: notchHeight)))
            finalCGImage = context.makeImage()
        }
        
        guard let finalCGImage = finalCGImage else {
            return false
        }

        let newWallpapaer = NSImage(cgImage: finalCGImage, size: screenSize)
        let imageName = UUID().uuidString
        guard let imageUrl = saveImage(image: newWallpapaer, isProcessed: true, imageName: imageName) else {return false}
        let _ = saveImage(image: currentWallpaperImage, isProcessed: false, imageName: imageName)
        
        return setDesktopImageURL(url:imageUrl)
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
    
    private func getScreenWithMouse() -> NSScreen? {
      let mouseLocation = NSEvent.mouseLocation
      let screens = NSScreen.screens
      let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
      return screenWithMouse
    }
    
    private func saveImage(image:NSImage, isProcessed:Bool, imageName:String) -> URL? {
        let imagePath = myAppPath?.appendingPathComponent(string: isProcessed ? "processed" : "original")
        guard let imagePath = imagePath else {return nil}
        if !FileManager.default.fileExists(atPath: imagePath) {
            do {
                try FileManager.default.createDirectory(atPath: imagePath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return nil
            }
        }
        let destinationPath = imagePath.appendingPathComponent(string: "\(imageName).jpg")
        let destinationURL = URL(fileURLWithPath: destinationPath)
        if image.jpgWrite(to: destinationURL, options: .withoutOverwriting) {
            print("destinationURL:\(destinationURL)")
            return destinationURL
        }
        return nil
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
    
    func clearCache() {
        guard let myAppPath = myAppPath else {
            return
        }

        let processedPath = myAppPath.appendingPathComponent(string: "processed")
        let originalPath = myAppPath.appendingPathComponent(string: "original")
        var currentNames = [String]()
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            if let path = workspace.desktopImageURL(for: screen){
                currentNames.append(path.lastPathComponent)
            }
        }
        
         let processedUrl = URL(fileURLWithPath: processedPath)
         let originalUrl = URL(fileURLWithPath: originalPath)
        
        removeAllFile(url: processedUrl, ignore: currentNames)
        removeAllFile(url: originalUrl, ignore: currentNames)
        
    }
    
    private func removeAllFile(url:URL, ignore:[String]) {
        do {
            let fileUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for fileUrl in fileUrls {
                if !ignore.contains(fileUrl.lastPathComponent) {
                    try FileManager.default.removeItem(at: fileUrl)
                }
            }
        } catch {
            
        }
    }
}
