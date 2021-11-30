//
//  CGImage++.swift.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

extension CGImage {
    func crop(toSize targetSize: CGSize) -> CGImage? {
        let x     = floor(CGFloat(self.width) / 2 - targetSize.width)
        let y     = floor(CGFloat(self.height) / 2 - targetSize.height)
        let frame = CGRect(x: x, y: y, width: targetSize.width * 2, height: targetSize.height * 2)

        let image = self.cropping(to: frame)
        return image
    }
}
