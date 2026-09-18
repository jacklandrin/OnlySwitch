//
//  main.swift
//  OnlySwitchPrivilegedHelper
//

import Foundation

private let helperMachService = "com.jacklandrin.OnlySwitch.PrivilegedHelper"
private let permittedCallerRequirement = "identifier \"jacklandrin.OnlySwitch\" and anchor apple generic and certificate leaf[subject.OU] = \"B22726TNGH\""

final class PrivilegedHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let executor = PrivilegedHelperExecutor()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // This requirement is evaluated by XPC using the connecting process's audit
        // token before it can deliver a request to this exported object.
        connection.setCodeSigningRequirement(permittedCallerRequirement)
        connection.exportedInterface = NSXPCInterface(with: PrivilegedOperationXPC.self)
        connection.exportedObject = PrivilegedHelperService(executor: executor)
        connection.resume()
        return true
    }
}

private final class PrivilegedHelperService: NSObject, PrivilegedOperationXPC {
    private let executor: PrivilegedHelperExecutor

    init(executor: PrivilegedHelperExecutor) {
        self.executor = executor
    }

    func setOperation(_ name: String, enabled: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        let request: PrivilegedOperationRequest
        do {
            request = try .init(requestName: name, enabled: enabled)
        } catch let error as PrivilegedOperationError {
            reply(error.nsError)
            return
        } catch {
            reply(PrivilegedOperationError.unsupportedOperation.nsError)
            return
        }

        do {
            try executor.executeSynchronously(request.operation, enabled: request.enabled)
            reply(nil)
        } catch {
            reply(NSError(domain: "com.jacklandrin.OnlySwitch.PrivilegedHelper", code: 2))
        }
    }
}

let listener = NSXPCListener(machServiceName: helperMachService)
let delegate = PrivilegedHelperDelegate()
listener.delegate = delegate
listener.setConnectionCodeSigningRequirement(permittedCallerRequirement)
listener.resume()
RunLoop.current.run()
