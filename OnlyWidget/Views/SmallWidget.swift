//
//  SmallWidget.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/2/5.
//

import Defines
import Extensions
import SwiftUI

struct SmallWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    private var unitType: UnitType
    private var id: String
    private var title: String
    private var image: NSImage?

    init(
        type: UnitType = .builtIn,
        id: String,
        title: String,
        image: NSImage? = nil
    ) {
        self.unitType = type
        self.id = id
        self.title = title
        self.image = image
    }
    
    var body: some View {
        Link(destination: URL(string: "onlyswitch://run?type=\(unitType.rawValue)&id=\(id)")!) {
            VStack {
                HStack {
                    Image(nsImage: image?.resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))! ?? NSImage(named: "logo")!)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: Layout.iconSize)
                    Spacer()
                    Text("Only Switch")
                        .font(.none)
                        .opacity(0.8)
                }
                .padding()
                Spacer()
                HStack(alignment: .bottom) {
                    Text(title.localized())
                        .font(.system(size: 16))
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .frame(height: 40, alignment: .bottom)
                    Spacer()
                }
                .padding()
            }
            .background(
                SpectrumView(unitType: unitType)
            )
        }

    }
}
