//
//  GitHubReleaseModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/5.
//

import Foundation
struct ReleaseAssets:Decodable {
    let id:Int
    let label:String?
    let state:String
    let created_at:String
    let content_type:String
    let url:String
    let node_id:String
    let size:Int
    let updated_at:String
    let browser_download_url:String
    let name:String
    let download_count:Int
    
    enum CodingKeys:String, CodingKey {
        case id
        case label
        case state
        case created_at
        case content_type
        case url
        case node_id
        case size
        case updated_at
        case browser_download_url
        case name
        case download_count
    }
}

struct GitHubRelease:Decodable {
    let id:Int
    let draft:Bool
    let published_at:String
    let assets:[ReleaseAssets]
    let prerelease:Bool
    let created_at:String
    let zipball_url:String
    let url:String
    let node_id:String
    let body:String
    let target_commitish:String
    let tarball_url:String
    let assets_url:String
    let upload_url:String
    let tag_name:String
    let name:String
    
    enum CodingKeys:String, CodingKey {
        case id
        case draft
        case published_at
        case assets
        case prerelease
        case created_at
        case zipball_url
        case url
        case node_id
        case body
        case target_commitish
        case tarball_url
        case assets_url
        case upload_url
        case tag_name
        case name
    }
}

