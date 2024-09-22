//
//  AboutVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/5.
//

import Foundation
import Alamofire

class AboutVM:ObservableObject {
    @Published var downloadCount: Int = 0
    @Published var updateHistoryInfo: String = ""
    @Published var updateHistoryList = [String]()
    
    private var presenter = GitHubPresenter()
    
    func requestReleases() {
        presenter.requestReleases { [self] result in
            switch result {
            case .success:
                self.downloadCount = presenter.downloadCount
                self.updateHistoryInfo = presenter.updateHistoryInfo
                self.updateHistoryList = presenter.updateHistoryList
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
}
