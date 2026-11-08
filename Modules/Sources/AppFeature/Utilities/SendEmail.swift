//
//  SendEmail.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Foundation
import Cocoa

protocol EmailProvider {
    func sendEmail()
}

extension EmailProvider {
    func sendEmail() {
        let service = NSSharingService(named: NSSharingService.Name.composeEmail)!
        service.recipients = ["jacklandrin@outlook.com"]
        service.subject = "About Only Switch"

        service.perform(withItems: [""])
    }
}
