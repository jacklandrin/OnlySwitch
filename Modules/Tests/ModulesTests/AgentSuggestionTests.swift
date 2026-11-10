import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyAgent

struct AgentSuggestionTests {
    @Test
    func darkModeSuggestsLightModeAndOppositeStates() {
        let info = AgentSystemInfo(
            osVersion: "26.1.0",
            isDarkMode: true,
            showsHiddenFiles: true,
            dockAutohides: true,
            homebrewPath: nil
        )
        #expect(AgentSuggestion.make(for: info) == [.turnOnLightMode, .alwaysShowDock, .hideHiddenFiles])
    }

    @Test
    func lightModeSuggestsDarkModeAndHomebrewWhenInstalled() {
        let info = AgentSystemInfo(
            osVersion: "26.1.0",
            isDarkMode: false,
            showsHiddenFiles: false,
            dockAutohides: false,
            homebrewPath: "/opt/homebrew/bin/brew"
        )
        #expect(AgentSuggestion.make(for: info) == [.turnOnDarkMode, .upgradeHomebrew, .autoHideDock, .showHiddenFiles])
    }

    @Test
    func unknownStatesFallBackToMacOSDefaults() {
        #expect(AgentSuggestion.make(for: AgentSystemInfo()) == [.turnOnDarkMode, .autoHideDock, .showHiddenFiles])
    }

    @Test
    func preferenceBooleanParsing() {
        let cases: [(Any?, Bool?)] = [
            (nil, nil), (true, true), (false, false),
            ("YES", true), ("TRUE", true), ("1", true), ("NO", false),
            (1, true), (0, false),
        ]
        for (raw, expected) in cases {
            #expect(AgentSystemInfo.preferenceBool(raw) == expected, "\(String(describing: raw))")
        }
    }

    @Test
    func newStateIsDescribedToTheModel() {
        let description = AgentSystemInfo(
            osVersion: "26.1.0",
            showsHiddenFiles: false,
            dockAutohides: true,
            homebrewPath: "/opt/homebrew/bin/brew"
        ).promptDescription
        #expect(description.contains("- Finder shows hidden files: No"))
        #expect(description.contains("- Dock auto-hide: On"))
        #expect(description.contains("- Homebrew: /opt/homebrew/bin/brew"))
    }
}

@MainActor
struct AgentSuggestionReducerTests {
    @Test
    func appearLoadsSuggestionsFromCurrentState() async {
        var info = AgentSystemInfo.fixture
        info.isDarkMode = true
        let store = TestStore(initialState: .fixture()) {
            AgentConversationReducer()
        } withDependencies: { [info] in
            $0.agentConversationClient.availableModels = { [:] }
            $0.agentConversationClient.systemInfo = { info }
        }
        store.exhaustivity = .off

        #expect(store.state.suggestions.isEmpty)
        await store.send(.appear)
        await store.receive(\.systemInfoLoaded) {
            $0.suggestions = AgentSuggestion.make(for: info)
        }
        #expect(store.state.suggestions.first == .turnOnLightMode)
    }

    @Test
    func newConversationRefreshesSuggestions() async {
        let dark = LockIsolated(false)
        let store = TestStore(initialState: .fixture(messages: [
            AgentMessage(id: UUID(100), role: .user, content: .text("Turn on dark mode")),
        ])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.systemInfo = {
                AgentSystemInfo(osVersion: "26", isDarkMode: dark.value)
            }
        }
        store.exhaustivity = .off

        dark.setValue(true)
        await store.send(.newConversation)
        await store.receive(\.systemInfoLoaded)
        #expect(store.state.suggestions.first == .turnOnLightMode)
    }
}
