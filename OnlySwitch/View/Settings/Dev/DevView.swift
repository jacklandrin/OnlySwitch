//
//  DevView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/4.
//

import SwiftUI
import SwiftUIWebView

struct DevView: View {
    @StateObject var viewModel = DevViewModel()
    
    var body: some View {
        VStack {
            navigationToolbar
            errorView
            Divider()
            WebView(action: $viewModel.action,
                    state: $viewModel.state,
                    restrictedPages: ["apple.com"])
            Spacer()
        }
    }
    
    private var navigationToolbar: some View {
        HStack(spacing: 10) {
            TextField("Address", text: $viewModel.address)
            if viewModel.state.isLoading {
                if #available(iOS 14, macOS 10.15, *) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Text("Loading")
                }
            }
            Spacer()
            Button("Go") {
                if let url = URL(string: viewModel.address) {
                    viewModel.action = .load(URLRequest(url: url))
                }
            }
            Button(action: {
                viewModel.action = .reload
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .imageScale(.large)
            }
            if viewModel.state.canGoBack {
                Button(action: {
                    viewModel.action = .goBack
                }) {
                    Image(systemName: "chevron.left")
                        .imageScale(.large)
                }
            }
            if viewModel.state.canGoForward {
                Button(action: {
                    viewModel.action = .goForward
                }) {
                    Image(systemName: "chevron.right")
                        .imageScale(.large)
                    
                }
            }
        }.padding()
    }
    
    private var errorView: some View {
        Group {
            if let error = viewModel.state.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
            }
        }
    }
}

#if DEBUG
struct DevView_Previews: PreviewProvider {
    static var previews: some View {
        DevView()
    }
}
#endif
