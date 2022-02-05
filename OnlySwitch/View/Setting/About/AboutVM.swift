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
    
    func requestDownloadCount() {
        let request = AF.request("https://api.github.com/repos/jacklandrin/OnlySwitch/releases")
        request.responseDecodable(of:[GitHubRelease].self) { response in
            guard let releases = response.value else {
                return
            }
            var count:Int = 0
            for release in releases {
                if let assert = release.assets.first {
                    count += assert.download_count
                }
            }
            self.downloadCount = count
        }
    }
    
}
