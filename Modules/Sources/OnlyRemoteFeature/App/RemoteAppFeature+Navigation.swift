import ComposableArchitecture

extension RemoteAppFeature {
    func reduceRetryTapped(_ state: inout State) -> Effect<Action> {
        if let intent = state.pendingPersistenceIntent, state.isPersisting == false {
            state.isPersisting = true
            return persist(intent)
        }
        if state.rootIssue == .loadFailed {
            return .send(.task)
        }
        return .none
    }

    func reduceGlobalSettingsButtonTapped(_ state: inout State) -> Effect<Action> {
        guard state.requiredGlobalSettings == nil else { return .none }
        state.path.append(.globalSettings(.init(
            tabConfiguration: state.tabConfiguration,
            isKeepingScreenAwake: state.isKeepingScreenAwake,
            pairedMacs: state.pairedMacs,
            selectedMacID: state.selectedMacID,
            connectionStatuses: connectionStatuses(state)
        )))
        return .none
    }

    func reduceControlsConfigurationButtonTapped(_ state: inout State) -> Effect<Action> {
        guard state.requiredGlobalSettings == nil,
              state.selectedMacID != nil else { return .none }
        state.controlsConfiguration = .init(
            pairedMacs: state.pairedMacs,
            selectedMacID: state.selectedMacID,
            connectionStatuses: connectionStatuses(state)
        )
        return .none
    }

    func reduceScenePhaseChanged(_ state: inout State, foregrounded: Bool) -> Effect<Action> {
        state.isForegrounded = foregrounded
        state.lifecycleGeneration &+= 1
        let generation = state.lifecycleGeneration
        let keepScreenAwake = foregrounded && state.isKeepingScreenAwake
        var effects: [Effect<Action>] = state.path.ids.compactMap { id in
            switch state.path[id: id] {
            case .globalSettings:
                return .send(.path(.element(
                    id: id,
                    action: .globalSettings(.foregroundChanged(foregrounded))
                )))
            case .controlsConfiguration:
                return .send(.path(.element(
                    id: id,
                    action: .controlsConfiguration(.foregroundChanged(foregrounded))
                )))
            case .monitorConfiguration, nil:
                return nil
            }
        }
        if state.requiredGlobalSettings != nil {
            effects.append(.send(.requiredGlobalSettings(.foregroundChanged(foregrounded))))
        }
        if state.controlsConfiguration != nil {
            effects.append(.send(.controlsConfiguration(.presented(.foregroundChanged(foregrounded)))))
        }
        if foregrounded == false, state.systemMonitor.isVisible {
            effects.append(.send(.systemMonitor(.visibilityChanged(false))))
        } else if foregrounded, state.selectedPage == .systemMonitor {
            effects.append(.send(.systemMonitor(.visibilityChanged(true))))
        }
        effects.append(soundMixerVisibility(state: state))
        effects.append(brightnessVisibility(state: state))
        effects.append(screenshotsVisibility(state: state))
        effects.append(.send(.codexUsage(.visibilityChanged(foregrounded && state.selectedPage == .codexUsage))))
        effects.append(.send(.claudeUsage(.visibilityChanged(foregrounded && state.selectedPage == .claudeUsage))))
        effects.append(
            .run { [connection] send in
                await connection.setForegrounded(foregrounded)
                await send(.lifecycleResponse(generation))
            }
            .cancellable(id: CancelID.lifecycle, cancelInFlight: true)
        )
        effects.append(.run { [idleTimer] _ in
            await idleTimer.setIdleTimerDisabled(keepScreenAwake)
        })
        return .merge(effects)
    }

    func reducePageSelected(_ state: inout State, page: RemoteAppPage) -> Effect<Action> {
        guard state.tabConfiguration.isVisible(page), state.selectedPage != page else { return .none }
        state.selectedPage = page
        return .merge(
            .send(.systemMonitor(.visibilityChanged(page == .systemMonitor && state.isForegrounded))),
            soundMixerVisibility(state: state),
            brightnessVisibility(state: state),
            screenshotsVisibility(state: state),
            .send(.codexUsage(.visibilityChanged(page == .codexUsage && state.isForegrounded))), .send(.claudeUsage(.visibilityChanged(page == .claudeUsage && state.isForegrounded))),
            page.requiresPlus ? .send(.plusAccess(.refresh)) : .none
        )
    }

    func reducePlusAccessEntitlementChanged(_ state: inout State) -> Effect<Action> {
        let entitlement = state.plusAccess.entitlement
        state.paywall?.entitlement = entitlement
        if case .active = entitlement { state.paywall?.purchasePending = false }
        let canAccess = state.plusAccess.canAccess
        let soundMixerEntitlement: Effect<Action> = state.soundMixer.isEntitled == canAccess
            ? .none
            : .send(.soundMixer(.entitlementChanged(canAccess)))
        let brightnessEntitlement: Effect<Action> = state.brightness.isEntitled == canAccess
            ? .none
            : .send(.brightness(.entitlementChanged(canAccess)))
        let screenshotsEntitlement: Effect<Action> = state.screenshots.isEntitled == canAccess
            ? .none
            : .send(.screenshots(.entitlementChanged(canAccess)))
        guard state.paywall != nil else { return .merge(soundMixerEntitlement, brightnessEntitlement, screenshotsEntitlement) }
        return .merge(
            soundMixerEntitlement,
            brightnessEntitlement,
            screenshotsEntitlement,
            .send(.paywall(.presented(.authoritativeEntitlementUpdated(entitlement))))
        )
    }

    func reduceDashboardTask(_ state: inout State) -> Effect<Action> {
        let needsSynchronization = state.dashboard.pairedMacs != state.pairedMacs
            || state.dashboard.selectedMacID != state.selectedMacID
        state.dashboard.isActive = true
        guard needsSynchronization else { return .none }
        syncDashboardState(&state)
        return .send(.dashboard(.task))
    }

    func reduceTabConfigurationChanged(_ state: inout State, configuration: RemoteTabConfiguration) -> Effect<Action> {
        state.tabConfiguration = configuration
        state.requiredGlobalSettings?.tabConfiguration = configuration
        for id in state.path.ids {
            if case var .globalSettings(settings) = state.path[id: id] {
                settings.tabConfiguration = configuration
                state.path[id: id] = .globalSettings(settings)
            }
        }
        guard configuration.isVisible(state.selectedPage) == false else { return .none }
        return .send(.pageSelected(.controls))
    }

    func reduceGlobalSettingsAllMacsRemoved(_ state: inout State) -> Effect<Action> {
        state.pairedMacs.removeAll()
        state.connectedMacIDs.removeAll()
        state.selectedMacID = nil
        state.path.removeAll()
        state.requiredGlobalSettings = .init(isSetupRequired: true, tabConfiguration: state.tabConfiguration)
        state.hasCompletedInitialSetup = false
        invalidateMetadataRefresh(state: &state)
        return .merge(
            .cancel(id: CancelID.metadataRefresh),
            clearedSelection(state: &state)
        )
    }

    func reduceControlsConfigurationAllMacsRemoved(_ state: inout State) -> Effect<Action> {
        state.pairedMacs.removeAll()
        state.connectedMacIDs.removeAll()
        state.selectedMacID = nil
        state.path.removeAll()
        state.requiredGlobalSettings = .init(isSetupRequired: true, tabConfiguration: state.tabConfiguration)
        state.hasCompletedInitialSetup = false
        invalidateMetadataRefresh(state: &state)
        return .merge(
            .cancel(id: CancelID.metadataRefresh),
            clearedSelection(state: &state)
        )
    }
}
