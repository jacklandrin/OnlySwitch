import Networking
import Testing

struct ProviderModelsCatalogTests {
    @Test func newerBundledModelsAreMergedWhenTheRemoteCatalogIsStale() {
        let remote = ProviderModelsCatalog(
            updatedAt: "2026-07-12",
            models: [.init(provider: "openai", family: "gpt", items: ["gpt-5.6"])]
        )
        let bundled = ProviderModelsCatalog(
            updatedAt: "2026-10-13",
            models: [.init(provider: "openai", family: "gpt", items: ["gpt-6.1-sol", "gpt-5.6"])]
        )

        let resolved = ProviderModelsCatalog.resolve(remote: remote, bundled: bundled)

        #expect(resolved.models(for: .openai).contains("gpt-6.1-sol"))
        #expect(resolved.models(for: .openai).contains("gpt-5.6"))
    }

    @Test func malformedOrUnsuccessfulRemoteResponsesFallBackToBundledCatalog() {
        let bundled = ProviderModelsCatalog(
            updatedAt: "2026-10-13",
            models: [.init(provider: "anthropic", family: "claude", items: ["claude-opus-5-5"])]
        )

        #expect(ProviderModelsCatalog.resolve(remote: nil, bundled: bundled) == bundled)
    }

    @Test func aSuccessfulRemoteCatalogRemainsUsableWhenTheBundleIsUnavailable() {
        let remote = ProviderModelsCatalog(
            updatedAt: "2026-10-13",
            models: [.init(provider: "openai", family: "gpt", items: ["gpt-6.1-sol"])]
        )

        #expect(ProviderModelsCatalog.resolve(remote: remote, bundled: nil) == remote)
    }
}
