//
//  SendEmail.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Foundation
import Cocoa

class SendEmail {
    static func send() {
        let service = NSSharingService(named: NSSharingService.Name.composeEmail)!
        service.recipients = ["jacklandrin@hotmail.com"]
        service.subject = "About Only Switch"

        service.perform(withItems: [""])
    
    }
}
