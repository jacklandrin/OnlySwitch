//
//  AboutVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/5.
//

import Foundation
import Alamofire

class AboutVM:ObservableObject {
    @Published var downloadCount:Int = 0
    @Published var updateHistoryInfo:String = ""
    
    private var presenter = GitHubPresenter()
    
    func requestReleases() {
        presenter.requestReleases { [self] success in
            if success {
                downloadCount = presenter.downloadCount
                updateHistoryInfo = presenter.updateHistoryInfo
            }
        }
    }
    
}
