//
//  IOService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/3.
//

import Foundation

enum IOService {
    enum IOError:Error {
        case cannotCreateMasterPort
        case cannotOpenService
    }
    
    static func getServiceConnect(handle:io_service_t, type:UInt32) throws -> io_connect_t {
        var service: io_connect_t = .zero
        defer { IOObjectRelease(handle) }
        
        guard IOServiceOpen(handle,
                            mach_task_self_,
                            type,
                            &service) == KERN_SUCCESS else {
            throw IOError.cannotOpenService
        }
        
        return service
    }
    
    static func getServiceConnect(by key:String) throws -> io_connect_t {
        return try getServiceConnect(handle: IOService.getIOHandle(by: key), type: 0)
    }
    
    static func getIOHandle(by key:String) -> io_service_t {
        let serviceObject = IOServiceGetMatchingService(kIOMainPortDefault,
                                                                IOServiceMatching(key))
        return serviceObject
    }
    
}
