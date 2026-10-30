import Foundation
import Testing
@testable import OnlySwitchRemote

struct RemoteTabConfigurationTests {
    @Test func defaultsShowEveryTabInOrder() {
        #expect(RemoteTabConfiguration().visiblePages == [.controls, .systemMonitor, .soundMixer, .brightness, .codexUsage, .claudeUsage, .aphrodite])
        #expect(RemoteAppPage.allCases == RemoteTabConfiguration().visiblePages)
    }

    @Test func controlsCannotBeHidden() {
        var configuration = RemoteTabConfiguration()
        configuration.setVisibility(false, for: .controls)
        #expect(configuration.isVisible(.controls))
        #expect(configuration == RemoteTabConfiguration())
        #expect(RemoteAppPage.allCases.filter(\.isAlwaysVisible) == [.controls])
    }

    @Test func optionalTabsCanBeHidden() {
        var configuration = RemoteTabConfiguration()
        for page in RemoteAppPage.allCases where !page.isAlwaysVisible {
            configuration.setVisibility(false, for: page)
            #expect(configuration.isVisible(page) == false)
        }
        #expect(configuration.visiblePages == [.controls])
    }

    @Test func plusPages() {
        #expect(RemoteAppPage.allCases.filter(\.requiresPlus) == [.soundMixer, .brightness, .aphrodite])
    }

    @Test func everyPageHasExactlyOneTabIcon() {
        for page in RemoteAppPage.allCases {
            #expect((page.tabSymbol == nil) != (page.tabImageName == nil), "\(page)")
        }
    }

    @Test func preferencesRoundTripAndDefaultNewKeysToVisible() throws {
        let suite = "RemoteTabConfigurationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "tabs.showsCodexUsage")
        var seed = RemoteTabPreferencesClient.preferenceSeed(defaults: defaults)
        #expect(seed.showsSoundMixer && seed.showsBrightness && seed.showsAphrodite)
        #expect(seed.showsCodexUsage == false)
        seed.setVisibility(false, for: .brightness)
        seed.setVisibility(false, for: .soundMixer)
        seed.setVisibility(false, for: .aphrodite)
        RemoteTabPreferencesClient.save(seed, defaults: defaults)
        #expect(defaults.object(forKey: "tabs.showsBrightness") as? Bool == false)
        #expect(defaults.object(forKey: "tabs.showsSoundMixer") as? Bool == false)
        #expect(defaults.object(forKey: "tabs.showsAphrodite") as? Bool == false)
        #expect(RemoteTabPreferencesClient.preferenceSeed(defaults: defaults) == seed)
    }
}
