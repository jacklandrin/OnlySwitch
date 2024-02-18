//
//  SmallWidget.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/2/5.
//

import Defines
import SwiftUI

struct SmallWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    var unitType: UnitType
    var id: String
    var title: String
    var image: NSImage?
    init(type: UnitType = .buildIn, id: String, title: String, image: NSImage? = nil) {
        self.unitType = type
        self.id = id
        self.title = title
        self.image = image
    }
    var body: some View {
        Link(destination: URL(string: "onlyswitch://performswitch?type=\(unitType.rawValue)&id=\(id)")!) {
            VStack {
                HStack {
                    Spacer()
                    Text("Only Switch")
                        .font(.none)
                        .opacity(0.8)
                }
                Spacer()
                Image(nsImage: image ?? NSImage(named: "logo")!)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
                Spacer()
                HStack(alignment: .bottom) {
                    Text(title)
                        .font(.system(size: 16))
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    Spacer()
                }
            }
        }
        .padding()
    }
}
