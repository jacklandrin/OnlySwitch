//
//  AdsModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/2.
//

import Foundation

struct AdsModel: Codable, Identifiable, Hashable {
    let imageURL: URL
    let link: URL
    let hint: String

    var id: String { link.absoluteString }

    private enum CodingKeys: String, CodingKey {
        case imageURL
        case link
        case hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        link = try container.decode(URL.self, forKey: .link)
        hint = try container.decode(String.self, forKey: .hint)

        guard imageURL.scheme == "https", link.scheme == "https" else {
            throw DecodingError.dataCorruptedError(
                forKey: .imageURL,
                in: container,
                debugDescription: "Ad image and destination URLs must use HTTPS."
            )
        }
    }

    static func decode(from data: Data) throws -> [AdsModel] {
        try JSONDecoder().decode([AdsModel].self, from: data)
    }

    static func loadBundledAds(bundle: Bundle = .main) -> [AdsModel] {
        guard let url = bundle.url(
            forResource: "AdsMarket",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url) else {
            return []
        }

        return (try? decode(from: data)) ?? []
    }
}

let Ads = AdsModel.loadBundledAds()
