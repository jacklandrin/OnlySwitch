import ComposableArchitecture
import Foundation
import OnlyAgent
import Testing
@testable import AppFeature

@MainActor
struct OnlyAgentEvolutionTests {
    @Test
    func agentDraftBecomesActiveAppleScriptButtonWithoutPrivileges() {
        let id = UUID()
        let item = AgentEvolutionClient.makeEvolutionItem(
            AgentEvolutionDraft(name: "Night", command: "run script \"x\""),
            id: id
        )

        #expect(item.id == id)
        #expect(item.name == "Night")
        #expect(item.active)
        #expect(item.controlType == .Button)
        #expect(item.singleCommand?.executeType == .applescript)
        #expect(item.singleCommand?.commandType == .single)
        #expect(item.singleCommand?.commandString == "run script \"x\"")
        #expect(item.singleCommand?.debugStatus == .success)
        #expect(item.privilegedOperation == nil)
        #expect(EvolutionItem.trustedPrivilegedOperation(id: id, controlType: .Button, requestedOperation: nil) == nil)
    }

    @Test
    func openOnlyAgentUsesLauncherWhenAvailable() async {
        let opened = LockIsolated(0)
        var state = EvolutionReducer.State()
        state.isOnlyAgentAvailable = true
        let store = TestStore(initialState: state) {
            EvolutionReducer()
        } withDependencies: {
            $0.onlyAgentLauncher.open = { opened.withValue { $0 += 1 } }
        }

        await store.send(.openOnlyAgent)
        await store.finish()
        #expect(opened.value == 1)
    }

    @Test
    func openOnlyAgentIsIgnoredWhenUnavailable() async {
        let store = TestStore(initialState: EvolutionReducer.State()) {
            EvolutionReducer()
        }
        // `open` is unimplemented: calling it fails the test.
        await store.send(.openOnlyAgent)
    }
}

struct OnlyAgentAskpassInstallTests {
    @Test
    func installsPrivateExecutableAskpassHelper() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "askpass-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = try AgentEvolutionClient.installAskpass(in: directory)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let script = try String(contentsOfFile: path, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("with hidden answer"))
        // Installing again (e.g. a second saved button) overwrites cleanly.
        #expect(try AgentEvolutionClient.installAskpass(in: directory) == path)
    }
}
