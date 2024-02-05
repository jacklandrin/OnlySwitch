//
//  SmallWidget.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/2/5.
//

import SwiftUI

public struct SmallWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    public init() {}
    public var body: some View {
        Link(destination: URL(string: "onlyswitch://performswitch")!) {
            VStack {
                HStack {
                    Spacer()
                    Text("Only Switch")
                        .font(.none)
                        .opacity(0.8)
                }
                Spacer()
                Image("darkmode")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
                Spacer()
                HStack {
                    Text("Dark Mode")
                        .font(.title)
                    Spacer()
                }
            }
        }
    }
}
