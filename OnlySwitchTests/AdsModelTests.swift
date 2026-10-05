//
//  AdsModelTests.swift
//  OnlySwitchTests
//

import Foundation
import Testing
@testable import OnlySwitch

struct AdsModelTests {
    @Test("Decodes ad records from the market JSON format")
    func decodesAdsMarketJSON() throws {
        let data = Data("""
        [
          {
            "imageURL": "https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/Resource/Ads/OnlyRemote.png",
            "link": "https://apps.apple.com/app/id6793657946",
            "hint": "Download OnlyRemote on the App Store"
          }
        ]
        """.utf8)

        let ads = try AdsModel.decode(from: data)
        let ad = try #require(ads.first)

        #expect(ad.id == "https://apps.apple.com/app/id6793657946")
        #expect(ad.imageURL.absoluteString.hasSuffix("Ads/OnlyRemote.png"))
        #expect(ad.hint == "Download OnlyRemote on the App Store")
        #expect(ad.qrcode == nil)
    }

    @Test("Prefers a QR code destination when present")
    func decodesQRCodeDestinationWithoutLink() throws {
        let data = Data("""
        [{
          "imageURL": "https://example.com/ad.png",
          "qrcode": "https://example.com/qr.png",
          "hint": "Scan me"
        }]
        """.utf8)
        let ad = try #require(AdsModel.decode(from: data).first)
        #expect(ad.link == nil)
        #expect(ad.qrcode?.absoluteString == "https://example.com/qr.png")
    }

    @Test("Rejects ad records without a valid image URL")
    func rejectsInvalidImageURL() {
        let data = Data("""
        [
          {
            "imageURL": "not a URL",
            "link": "https://apps.apple.com/app/id6793657946",
            "hint": "Download OnlyRemote on the App Store"
          }
        ]
        """.utf8)

        #expect(throws: DecodingError.self) {
            try AdsModel.decode(from: data)
        }
    }
}
