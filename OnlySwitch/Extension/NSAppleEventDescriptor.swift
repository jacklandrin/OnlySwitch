//
//  NSAppleEventDescriptor.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation
extension NSAppleEventDescriptor {

    func toDicArray() -> [Any] {
        guard let listDescriptor = self.coerce(toDescriptorType: typeAEList) else {
            return []
        }

        return (1...listDescriptor.numberOfItems)
           .compactMap { listDescriptor.atIndex($0)?.toDic }
    }
    
    func toDic() -> [String:Any] {
        guard let dicDescriptor = self.coerce(toDescriptorType: typeAERecord) else  {
            return ["":""]
        }
        
        return dicDescriptor.dictionaryWithValues(forKeys: ["ID"])
    }
    
    
    
}
