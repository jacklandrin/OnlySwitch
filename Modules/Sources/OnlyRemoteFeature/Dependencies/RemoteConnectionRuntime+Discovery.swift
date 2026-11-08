import Foundation
import Network
import RemoteCore

extension RemoteConnectionRuntime {
    func updateDiscovery(
        _ results: Set<NWBrowser.Result>,
        generation expectedGeneration: UInt64
    ) async {
        guard foregrounded,
              browser != nil,
              browserGeneration == expectedGeneration else { return }
        var candidates: [DiscoveredMac] = []
        for result in results {
            guard case let .bonjour(txtRecord) = result.metadata,
                  let idString = txtRecord["id"],
                  let id = UUID(uuidString: idString),
                  let majorString = txtRecord["version"],
                  let major = UInt16(majorString) else { continue }
            let minor = txtRecord["minor"].flatMap(UInt16.init) ?? 0
            let name: String
            if case let .service(serviceName, _, _, _) = result.endpoint { name = serviceName }
            else { name = id.uuidString }
            let mac = DiscoveredMac(
                id: id,
                displayName: name,
                endpoint: result.endpoint,
                protocolVersion: .init(major: major, minor: minor)
            )
            candidates.append(mac)
        }
        let preferred = selected.flatMap { selected in
            selected.lastEndpointDescription.map { [selected.id: $0] }
        } ?? [:]
        let updated = Self.boundedCandidates(
            candidates,
            preferredEndpoints: preferred,
            selectedMacID: selected?.id
        )
        for (id, candidates) in updated {
            let primary = candidates.values.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }.first
            let oldPrimary = discovered[id]?.values.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }.first
            if let primary, primary != oldPrimary { discoveryHub.yield(.added(primary)) }
        }
        for id in discovered.keys where updated[id] == nil { discoveryHub.yield(.removed(id)) }
        let selectedCandidatesChanged = selected.map {
            Self.candidateSetChanged(
                previous: discovered[$0.id] ?? [:],
                updated: updated[$0.id] ?? [:]
            )
        } ?? false
        discovered = updated
        if selectedCandidatesChanged, let selected, updated[selected.id]?.isEmpty == false, session == nil {
            await select(selected)
        }
    }

    func browserBecameReady(generation expectedGeneration: UInt64) {
        guard foregrounded,
              browser != nil,
              browserGeneration == expectedGeneration else { return }
        browserFailureCount = 0
        browserRetryTask?.cancel()
        browserRetryTask = nil
    }

    func publishWaiting(_ error: NWError, generation expectedGeneration: UInt64) {
        guard foregrounded,
              browser != nil,
              browserGeneration == expectedGeneration else { return }
        let failure = Self.discoveryFailure(for: error)
        discoveryHub.yield(.waiting(failure))
        if Self.shouldRestartBrowser(after: failure, failureCount: browserFailureCount) {
            scheduleBrowserRestart(generation: expectedGeneration)
        }
    }

    func publishFailureAndRestart(_ error: NWError, generation expectedGeneration: UInt64) {
        guard foregrounded,
              browser != nil,
              browserGeneration == expectedGeneration else { return }
        discoveryHub.yield(.failed(Self.discoveryFailure(for: error)))
        scheduleBrowserRestart(generation: expectedGeneration)
    }

    func stopDiscoveryIfUnused() {
        guard Self.needsDiscovery(
            subscriberCount: discoveryHub.subscriberCount,
            selectedMacID: selected?.id
        ) == false else { return }
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserRetryTask = nil
        browserGeneration &+= 1
        discovered.removeAll()
    }

    private func scheduleBrowserRestart(generation expectedGeneration: UInt64) {
        guard foregrounded,
              browser != nil,
              browserGeneration == expectedGeneration else { return }
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserGeneration &+= 1
        let expectedGeneration = browserGeneration
        guard foregrounded else { return }
        let delay = Self.browserRetryDelay(failureCount: browserFailureCount)
        browserFailureCount = min(browserFailureCount + 1, 4)
        browserRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            await self?.restartBrowser(generation: expectedGeneration)
        }
    }

    private func restartBrowser(generation expectedGeneration: UInt64) {
        guard foregrounded, browserGeneration == expectedGeneration else { return }
        browserRetryTask = nil
        startDiscovery()
    }
}
