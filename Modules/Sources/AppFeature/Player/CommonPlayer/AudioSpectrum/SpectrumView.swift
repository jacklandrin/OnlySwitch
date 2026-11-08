//
// AudioSpectrum02
// A demo project for blog: https://juejin.im/post/5c1bbec66fb9a049cb18b64c
// Created by: potato04 on 2019/1/30
//

import AppKit

class SpectrumView: NSView {
    
    var barWidth: CGFloat = 3.0
    var space: CGFloat = 1.0
    

    var leftColors = [NSColor(red: 253/255, green: 229/255, blue: 241/255, alpha: 0.7).cgColor,
                      NSColor(red: 235/255, green: 2/255, blue: 119/255, alpha: 0.8).cgColor]
    var rightColors = [NSColor(red: 253/255, green: 229/255, blue: 241/255, alpha: 0.7).cgColor,
                       NSColor(red: 86/255, green: 40/255, blue: 123/255, alpha: 0.8).cgColor]
                       
    
    private let bottomSpace: CGFloat = 0.0
    private let topSpace: CGFloat = 0.0
    
    var leftGradientLayer = CAGradientLayer()
    var rightGradientLayer = CAGradientLayer()

    
    var spectra:[[Float]]? {
        didSet {
            if let spectra = spectra {
                // left channel
                let leftPath = NSBezierPath()
                for (i, amplitude) in spectra[0].enumerated() {
                    let x = CGFloat(i) * (barWidth + space) + space
                    let y = translateAmplitudeToYPosition(amplitude: amplitude)
                    let bar = NSBezierPath(rect: CGRect(x: x, y: y, width: barWidth, height: bounds.height - bottomSpace - y))
                    leftPath.append(bar)
                }
                
                let leftMaskLayer = CAShapeLayer()
                leftMaskLayer.path = leftPath.cgPath
                 
                leftGradientLayer.frame = CGRect(x: 0, y: topSpace, width: bounds.width, height: bounds.height - topSpace - bottomSpace)
                leftGradientLayer.mask = leftMaskLayer
                leftGradientLayer.shouldRasterize = true
                leftGradientLayer.drawsAsynchronously = true
                leftGradientLayer.isOpaque = true
                
                // right channel
                if spectra.count >= 2 {
                    let rightPath = NSBezierPath()
                    for (i, amplitude) in spectra[1].enumerated() {
                        let x = CGFloat(spectra[1].count - 1 - i) * (barWidth + space) + space
                        let y = translateAmplitudeToYPosition(amplitude: amplitude)
                        let bar = NSBezierPath(rect: CGRect(x: x, y: y, width: barWidth, height: bounds.height - bottomSpace - y))
                        rightPath.append(bar)
                    }
                    let rightMaskLayer = CAShapeLayer()
                    rightMaskLayer.path = rightPath.cgPath
                 
                    rightGradientLayer.frame = CGRect(x: 0, y: topSpace, width: bounds.width, height: bounds.height - topSpace - bottomSpace)
                    rightGradientLayer.mask = rightMaskLayer
                    rightGradientLayer.shouldRasterize = true
                    rightGradientLayer.drawsAsynchronously = true
                    rightGradientLayer.isOpaque = true
                }
            }
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
//        setupView()
//        self.wantsUpdateLayer = true
        self.layerContentsRedrawPolicy = NSView.LayerContentsRedrawPolicy.onSetNeedsDisplay
    
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private func setupView() {
        self.layer?.contentsScale = 1
        
        leftGradientLayer.colors = leftColors
        leftGradientLayer.locations = [0.6, 1.0]

        self.layer?.addSublayer(leftGradientLayer)
        
        rightGradientLayer.colors = rightColors
        rightGradientLayer.locations = [0.7, 1.0]
        self.layer?.addSublayer(rightGradientLayer)
        
        layer?.shouldRasterize = true
        layer?.rasterizationScale = 1
        layer?.isOpaque = true
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    override func updateLayer() {
        setupView()
    }
    
    private func translateAmplitudeToYPosition(amplitude: Float) -> CGFloat {
        let barHeight: CGFloat = CGFloat(amplitude) * (bounds.height - bottomSpace - topSpace)
        return bounds.height - bottomSpace - barHeight
    }
}
