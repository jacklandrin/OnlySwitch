//
//  FKeySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/3.
//

import Foundation

class FKeySwitch:SwitchProvider {
    
    static let shared = FKeySwitch()
    var type: SwitchType = .fkey
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        let mode = try? FKeyManager.getCurrentFKeyMode()
        return mode == .function
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        if isOn {
            try FKeyManager.setCurrentFKeyMode(.function)
        } else {
            try FKeyManager.setCurrentFKeyMode(.media)
        }
    }
    
    func isVisable() -> Bool {
        do {
            let connect = try FKeyManager.getServiceConnect()
            guard connect != .zero else {return false}
            return true
        } catch {
            return false
        }
    }
    
}

enum FKeyManager {
    typealias FKeyManagerResult = Result<FKeyMode, Error>
    
    enum FKeyMode:Int {
        case media = 0
        case function
    }
    
    enum FKeyManagerError: Error {
        case cannotCreateMasterPort
        case cannotOpenService
        case cannotSetParameter
        case cannotGetParameter
        
        case otherError
        
        var localizedDescription: String {
            switch self {
            case .cannotCreateMasterPort:
                return "Master port creation failed (E1)"
            case .cannotOpenService:
                return "Service opening failed (E2)"
            case .cannotSetParameter:
                return "Parameter set not possible (E3)"
            case .cannotGetParameter:
                return "Parameter read not possible (E4)"
            default:
                return "Unknown error (E99)"
            }
        }
    }
    
    static func setCurrentFKeyMode(_ mode: FKeyMode) throws {
        let connect = try FKeyManager.getServiceConnect()
        let value = mode.rawValue as CFNumber
        
        guard IOHIDSetCFTypeParameter(connect,
                                      kIOHIDFKeyModeKey as CFString,
                                      value) == KERN_SUCCESS else {
            throw FKeyManagerError.cannotSetParameter
        }
        
        IOServiceClose(connect)
    }
    
    static func getCurrentFKeyMode() throws -> FKeyMode {
        
        let ri = try self.getIORegistry()
        defer { IOObjectRelease(ri) }
        
        let entry = IORegistryEntryCreateCFProperty(ri,
                                                    "HIDParameters" as CFString,
                                                    kCFAllocatorDefault,
                                                    0)
            .autorelease()
        
        guard let dict = entry.takeUnretainedValue() as? NSDictionary,
              let mode = dict.value(forKey: "HIDFKeyMode") as? Int,
              let currentMode = FKeyMode(rawValue: mode) else {
            throw FKeyManagerError.cannotGetParameter
        }
        
        return currentMode
        
    }
    
    private static func getIORegistry() throws -> io_registry_entry_t {
        var masterPort: mach_port_t = .zero
        guard IOMainPort(bootstrap_port,
                         &masterPort) == KERN_SUCCESS else {
            throw FKeyManagerError.cannotCreateMasterPort
        }
        
        return IORegistryEntryFromPath(masterPort, "IOService:/IOResources/IOHIDSystem")
    }
    
    private static func getIOHandle() throws -> io_service_t {
        try self.getIORegistry() as io_service_t
    }
    
    static func getServiceConnect() throws -> io_connect_t {
        var service: io_connect_t = .zero
        let handle = try self.getIOHandle()
        defer { IOObjectRelease(handle) }
        
        guard IOServiceOpen(handle,
                            mach_task_self_,
                            UInt32(kIOHIDParamConnectType),
                            &service) == KERN_SUCCESS else {
            throw FKeyManagerError.cannotOpenService
        }
        
        return service
    }
}
