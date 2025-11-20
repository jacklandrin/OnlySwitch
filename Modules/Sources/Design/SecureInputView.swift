//
//  SecureInputView.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import SwiftUI

public struct SecureInputView: View {
    @Binding private var text: String
    @State private var isSecured: Bool = true
    private var title: String
    
    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }
    
    public var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if isSecured {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }

            Button(action: {
                isSecured.toggle()
            }) {
                Image(systemName: self.isSecured ? "eye.slash" : "eye")
                    .accentColor(.gray)
            }
            .buttonStyle(.plain)
        }
    }
}
