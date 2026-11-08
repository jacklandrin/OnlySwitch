import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    func setForegrounded(_ value: Bool) async {
        foregroundLifecycleGeneration &+= 1
        let lifecycleGeneration = foregroundLifecycleGeneration
        foregrounded = value
        guard value else {
            if finalizingTransactionID != nil {
                generation &+= 1
                connectionTask?.cancel()
                connectionTask = nil
                stopBrowsingForBackground()
                await closeSessionForBackground()
                return
            }
            await abortPairing(nil)
            generation &+= 1
            connectionTask?.cancel()
            connectionTask = nil
            stopBrowsingForBackground()
            if backgroundHold != nil { return }
            if activeBackgroundTransfers > 0, session != nil {
                // Keep the session for the transfers; nothing reconnects while backgrounded.
                await beginBackgroundHold()
                return
            }
            await closeSessionForBackground()
            guard foregroundLifecycleGeneration == lifecycleGeneration else { return }
            return
        }
        // The held session is still open, so the reconnect below is skipped for it.
        await cancelBackgroundHold()
        startDiscovery()
        guard foregroundLifecycleGeneration == lifecycleGeneration, foregrounded else { return }
        if let selected, session == nil { await select(selected) }
    }

    func withBackgroundTransferHold(_ transfer: @escaping @Sendable () async throws -> URL) async throws -> URL {
        activeBackgroundTransfers += 1
        do {
            let url = try await transfer()
            await backgroundTransferEnded()
            return url
        } catch {
            await backgroundTransferEnded()
            throw error
        }
    }

    private func backgroundTransferEnded() async {
        activeBackgroundTransfers -= 1
        guard activeBackgroundTransfers == 0, let id = backgroundHold?.id else { return }
        await endBackgroundHold(id)
    }

    private func beginBackgroundHold() async {
        let id = UUID()
        let gracePeriod = backgroundTransferGracePeriod
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: gracePeriod) } catch { return }
            await self?.endBackgroundHold(id)
        }
        backgroundHold = BackgroundHold(id: id, timeout: timeout)
        let task = await backgroundTasks.begin("OnlyRemote screenshot transfer") { [weak self] in
            Task { await self?.endBackgroundHold(id) }
        }
        // The hold may have ended or been cancelled while the system granted the time.
        if backgroundHold?.id == id {
            backgroundHold?.task = task
        } else if let task {
            await backgroundTasks.end(task)
        }
    }

    /// Ends a hold: closes the session as backgrounding normally does, then gives the time back.
    private func endBackgroundHold(_ id: UUID) async {
        guard let hold = backgroundHold, hold.id == id else { return }
        backgroundHold = nil
        hold.timeout.cancel()
        if foregrounded == false { await closeSessionForBackground() }
        if let task = hold.task { await backgroundTasks.end(task) }
    }

    /// Foregrounding keeps the held session as the live one.
    private func cancelBackgroundHold() async {
        guard let hold = backgroundHold else { return }
        backgroundHold = nil
        hold.timeout.cancel()
        if let task = hold.task { await backgroundTasks.end(task) }
    }

    private func stopBrowsingForBackground() {
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserRetryTask = nil
        browserGeneration &+= 1
        discovered.removeAll()
    }

    private func closeSessionForBackground() async {
        let detachedSession = session
        session = nil
        sessionToken = nil
        if let detachedSession {
            try? await detachedSession.setSystemMonitorStreaming(false)
            await closeSession(detachedSession)
        }
        await backgroundCleanup()
    }
}
