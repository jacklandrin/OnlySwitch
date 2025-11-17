//
//  RollingText.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI

public struct RollingText : View {
    public var text = ""
    public var font: NSFont
    public var leftFade: CGFloat
    public var rightFade: CGFloat
    public var startDelay: Double

    @State private var animate = false

    public var body : some View {
        let stringWidth = text.widthOfString(usingFont: font)
        let stringHeight = text.heightOfString(usingFont: font)
        return ZStack {
            GeometryReader { geometry in
                Group {
                    Text(self.text).lineLimit(1)
                        .font(.init(font))
                        .offset(x: self.animate ? CGFloat(-stringWidth - stringHeight * 2) : 0)
                        .animation(Animation.linear(duration: Double(stringWidth) / 30).delay(startDelay).repeatForever(autoreverses: false), value: self.animate)
                        .onAppear() {
                            print("\(geometry.size.width)  \(stringWidth)")
                            if geometry.size.width - leftFade - rightFade < stringWidth {
                                withAnimation() {
                                    self.animate = true
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        .onChange(of: self.text) { _ in
                            print("\(geometry.size.width)  \(stringWidth)")
                            if geometry.size.width - leftFade - rightFade < stringWidth {
                                withAnimation() {
                                    self.animate = true
                                }
                            }
                        }
                    
                        Text(self.text).lineLimit(1)
                            .font(.init(font))
                            .offset(x: self.animate ? 0 : stringWidth + stringHeight * 2)
                            .animation(Animation.linear(duration: Double(stringWidth) / 30).delay(startDelay).repeatForever(autoreverses: false), value: self.animate
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                            .opacity(self.animate ? 1 : 0)
                    
                }.offset(x: leftFade)
                .mask(
                    HStack(spacing:0) {
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                        LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0),
                                                                   Color.black]),
                                       startPoint: .leading,
                                       endPoint: .trailing)
                            .frame(width:leftFade)
                        LinearGradient(gradient: Gradient(colors: [Color.black,
                                                                   Color.black]),
                                       startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/,
                                       endPoint: .trailing)
                        LinearGradient(gradient: Gradient(colors: [Color.black,
                                                                   Color.black.opacity(0)]),
                                       startPoint: .leading,
                                       endPoint: .trailing)
                            .frame(width:rightFade)
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                    }).frame(width: geometry.size.width + leftFade).offset(x: leftFade * -1)
            }
        }.frame(height: stringHeight)
    }
    public init(text: String, font: NSFont = .systemFont(ofSize: 14), leftFade: CGFloat, rightFade: CGFloat, startDelay: Double) {
        self.text = text
        self.font = font
        self.leftFade = leftFade
        self.rightFade = rightFade
        self.startDelay = startDelay
    }
}

extension String {

    func widthOfString(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }

    func heightOfString(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.height
    }
}
