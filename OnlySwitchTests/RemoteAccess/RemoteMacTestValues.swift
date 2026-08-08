import Foundation
import RemoteCore
import Switches
@testable import OnlySwitch

final class FakeSwitch: SwitchProvider, @unchecked Sendable {
    let type: SwitchType
    weak var delegate: SwitchDelegate?
    let visible: Bool
    var status = false
    var info = ""
    var operationCount = 0

    init(type: SwitchType, visible: Bool) {
        self.type = type
        self.visible = visible
    }

    func currentStatus() async -> Bool { status }
    func currentInfo() async -> String { info }

    func operateSwitch(isOn: Bool) async throws {
        operationCount += 1
        status = isOn
    }

    func isVisible() -> Bool { visible }
}

extension Array where Element == RemoteControlDescriptor {
    subscript(id id: RemoteControlID) -> RemoteControlDescriptor? {
        first { $0.id == id }
    }
}

extension RemoteActionResult {
    var error: RemoteProtocolError? {
        guard case let .failure(error) = result else { return nil }
        return error
    }
}
