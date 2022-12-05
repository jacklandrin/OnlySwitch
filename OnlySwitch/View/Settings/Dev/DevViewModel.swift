//
//  DevViewModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/4.
//

import Foundation
import SwiftUIWebView

class DevViewModel:ObservableObject {
    @Published var action = WebViewAction.idle
    @Published var state = WebViewState.empty
    @Published var address = "https://www.google.com"
    
}
