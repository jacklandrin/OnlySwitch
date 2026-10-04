import Defines
import Extensions
import Foundation
import Switches

final class ReverseScrollDirectionSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .reverseScrollDirection

    private let readStatus: @MainActor @Sendable () async throws -> Bool
    private let writeStatus: @MainActor @Sendable (Bool) async throws -> Void

    init(
        readStatus: @escaping @MainActor @Sendable () async throws -> Bool = {
            let result = try await ReverseScrollDirectionCMD.status.runAppleScript(isShellCMD: true)
            return !(result as NSString).boolValue
        },
        writeStatus: @escaping @MainActor @Sendable (Bool) async throws -> Void = { isOn in
            let command = isOn ? ReverseScrollDirectionCMD.on : ReverseScrollDirectionCMD.off
            _ = try await command.runAppleScript(isShellCMD: true)
        }
    ) {
        self.readStatus = readStatus
        self.writeStatus = writeStatus
    }

    @MainActor
    func currentStatus() async -> Bool {
        (try? await readStatus()) ?? false
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            try await writeStatus(isOn)
        } catch {
            throw SwitchError.OperationFailed
        }
    }

    func isVisible() -> Bool {
        true
    }
}
