import ComposableArchitecture
import CoreGraphics
import Foundation

@Reducer
struct DockPreviewFeature {
    @ObservableState
    struct State: Equatable {
        enum Status: Equatable {
            case idle
            case requestingPermission
            case permissionRequired
            case loading
            case captureFailed
            case activationFailed
        }

        struct Preview: Equatable {
            var generation: UInt64
            var appName: String
            var itemFrame: CGRect
            var screenFrame: CGRect
            var windows: [DockPreviewWindow]
            var mediaPlayer: DockPreviewMediaPlayer? = nil
            var isMediaPlaying = false
        }

        var isEnabled = false
        var authorization = DockPreviewAuthorization.unknown
        var isObserving = false
        var hoverGeneration: UInt64 = 0
        var hover: DockHoverEvent?
        var preview: Preview?
        var status: Status = .idle
        var showPermissionHelp = false
    }

    enum Action: Equatable {
        case startup(isEnabled: Bool)
        case enabledChanged(Bool)
        case authorizationChanged(DockPreviewAuthorization, requested: Bool)
        case hovered(DockHoverEvent?)
        case windowsLoaded(generation: UInt64, hover: DockHoverEvent, result: Result<[DockPreviewWindow], DockPreviewFailure>)
        case thumbnailLoaded(generation: UInt64, windowID: CGWindowID, result: Result<Data, DockPreviewFailure>)
        case windowTapped(CGWindowID)
        case activationFinished(succeeded: Bool)
        case mediaPlaybackLoaded(generation: UInt64, isPlaying: Bool)
        case mediaCommandTapped(DockPreviewMediaCommand)
        case permissionHelpPresented
        case escapePressed
        case pointerExited
        case previewFrameChanged(CGRect?)
        case stop
    }

    private enum CancelID: Hashable {
        case hover
        case catalog
        case captures
        case activation
        case media
    }

    @Dependency(\.dockPreview) var client
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .startup(isEnabled):
                state.isEnabled = isEnabled
                guard isEnabled else { return .none }
                return .run { send in
                    await send(.authorizationChanged(client.authorizationStatus(), requested: false))
                }

            case let .enabledChanged(isEnabled):
                guard isEnabled else {
                    clear(&state)
                    return stopEffects()
                }
                state.isEnabled = true
                state.status = .requestingPermission
                return .run { send in
                    await send(.authorizationChanged(client.requestAuthorization(), requested: true))
                }

            case let .authorizationChanged(authorization, requested):
                state.authorization = authorization
                guard authorization.isAuthorized else {
                    let wasEnabled = state.isEnabled
                    state.isEnabled = false
                    state.isObserving = false
                    state.hover = nil
                    state.preview = nil
                    state.status = .permissionRequired
                    state.showPermissionHelp = requested
                    return .merge(
                        stopEffects(),
                        wasEnabled ? .run { _ in await client.persistEnabled(false) } : .none
                    )
                }
                guard state.isEnabled else { return .none }
                return startObservation(&state)

            case let .hovered(hover):
                guard state.isEnabled, state.isObserving, state.authorization.isAuthorized else {
                    return .none
                }
                if let hover, hover.pid == state.hover?.pid {
                    state.hover = hover
                    state.preview?.itemFrame = hover.itemFrame
                    state.preview?.screenFrame = hover.screenFrame
                    return .none
                }
                state.hoverGeneration &+= 1
                state.hover = hover
                state.preview = nil
                guard let hover else {
                    state.status = .idle
                    return cancelPreviewEffects()
                }
                let generation = state.hoverGeneration
                state.status = .loading
                return .run { send in
                    do {
                        let windows = try await client.windows(hover.pid)
                        await send(.windowsLoaded(generation: generation, hover: hover, result: .success(windows)))
                    } catch is CancellationError {
                        return
                    } catch {
                        let authorization = await client.authorizationStatus()
                        if !authorization.isAuthorized {
                            await send(.authorizationChanged(authorization, requested: false))
                        } else {
                            await send(.windowsLoaded(generation: generation, hover: hover, result: .failure(.windowListing)))
                        }
                    }
                }
                .cancellable(id: CancelID.catalog, cancelInFlight: true)

            case let .windowsLoaded(generation, hover, result):
                guard state.isEnabled, state.isObserving,
                      generation == state.hoverGeneration else { return .none }
                let currentHover = state.hover ?? hover
                switch result {
                case let .success(windows) where !windows.isEmpty:
                    state.preview = .init(
                        generation: generation,
                        appName: currentHover.appName,
                        itemFrame: currentHover.itemFrame,
                        screenFrame: currentHover.screenFrame,
                        windows: windows,
                        mediaPlayer: currentHover.mediaPlayer
                    )
                    state.status = .idle
                    let captures: Effect<Action> = .run { send in
                        for window in windows {
                            try Task.checkCancellation()
                            do {
                                let data = try await client.capture(window)
                                await send(.thumbnailLoaded(generation: generation, windowID: window.id, result: .success(data)))
                            } catch is CancellationError {
                                return
                            } catch {
                                let authorization = await client.authorizationStatus()
                                if !authorization.isAuthorized {
                                    await send(.authorizationChanged(authorization, requested: false))
                                    return
                                }
                                await send(.thumbnailLoaded(generation: generation, windowID: window.id, result: .failure(.capture)))
                            }
                        }
                    }
                    .cancellable(id: CancelID.captures, cancelInFlight: true)
                    return .merge(captures, loadMediaPlayback(state.preview))

                case .success:
                    // Media players keep their controls even with every window closed.
                    guard let mediaPlayer = currentHover.mediaPlayer else {
                        state.preview = nil
                        state.status = .idle
                        return .none
                    }
                    state.preview = .init(
                        generation: generation,
                        appName: currentHover.appName,
                        itemFrame: currentHover.itemFrame,
                        screenFrame: currentHover.screenFrame,
                        windows: [],
                        mediaPlayer: mediaPlayer
                    )
                    state.status = .idle
                    return loadMediaPlayback(state.preview)

                case .failure:
                    state.preview = .init(
                        generation: generation,
                        appName: currentHover.appName,
                        itemFrame: currentHover.itemFrame,
                        screenFrame: currentHover.screenFrame,
                        windows: [],
                        mediaPlayer: currentHover.mediaPlayer
                    )
                    state.status = .captureFailed
                    return loadMediaPlayback(state.preview)
                }

            case let .thumbnailLoaded(generation, windowID, result):
                guard state.isEnabled, state.isObserving,
                      generation == state.hoverGeneration,
                      let index = state.preview?.windows.firstIndex(where: { $0.id == windowID })
                else { return .none }
                if case let .success(data) = result {
                    state.preview?.windows[index].thumbnailData = data
                }
                return .none

            case let .windowTapped(windowID):
                guard let window = state.preview?.windows.first(where: { $0.id == windowID }),
                      window.isActivatable
                else { return .none }
                return .run { send in
                    do {
                        try await client.activate(window)
                        await send(.activationFinished(succeeded: true))
                    } catch {
                        await send(.activationFinished(succeeded: false))
                    }
                }
                .cancellable(id: CancelID.activation, cancelInFlight: true)

            case let .activationFinished(succeeded):
                if succeeded { state.preview = nil }
                state.status = succeeded ? .idle : .activationFailed
                return .none

            case let .mediaPlaybackLoaded(generation, isPlaying):
                guard state.preview?.generation == generation else { return .none }
                state.preview?.isMediaPlaying = isPlaying
                return .none

            case let .mediaCommandTapped(command):
                guard let preview = state.preview,
                      let mediaPlayer = preview.mediaPlayer
                else { return .none }
                if command == .playPause {
                    state.preview?.isMediaPlaying.toggle()
                }
                let generation = preview.generation
                return .run { send in
                    await client.sendMediaCommand(mediaPlayer, command)
                    // Players publish their new state asynchronously after a command.
                    try await clock.sleep(for: .milliseconds(300))
                    let isPlaying = await client.isMediaPlaying(mediaPlayer)
                    await send(.mediaPlaybackLoaded(generation: generation, isPlaying: isPlaying))
                }
                .cancellable(id: CancelID.media, cancelInFlight: true)

            case .permissionHelpPresented:
                state.showPermissionHelp = false
                return .none

            case .escapePressed:
                state.hoverGeneration &+= 1
                state.preview = nil
                state.status = .idle
                return cancelPreviewEffects()

            case .pointerExited:
                state.hoverGeneration &+= 1
                state.hover = nil
                state.preview = nil
                state.status = .idle
                return cancelPreviewEffects()

            case let .previewFrameChanged(frame):
                return .run { _ in await client.updatePreviewFrame(frame) }

            case .stop:
                clear(&state)
                return stopEffects()
            }
        }
    }

    private func startObservation(_ state: inout State) -> Effect<Action> {
        guard !state.isObserving else { return .none }
        state.isObserving = true
        state.status = .idle
        state.showPermissionHelp = false
        return .run { send in
            let events = await client.hoverEvents()
            for await event in events {
                try Task.checkCancellation()
                await send(.hovered(event))
            }
        }
        .cancellable(id: CancelID.hover, cancelInFlight: true)
    }

    private func stopEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.hover),
            .cancel(id: CancelID.catalog),
            .cancel(id: CancelID.captures),
            .cancel(id: CancelID.activation),
            .cancel(id: CancelID.media),
            .run { _ in await client.stop() }
        )
    }

    private func cancelPreviewEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.catalog),
            .cancel(id: CancelID.captures),
            .cancel(id: CancelID.media)
        )
    }

    private func loadMediaPlayback(_ preview: State.Preview?) -> Effect<Action> {
        guard let preview, let mediaPlayer = preview.mediaPlayer else { return .none }
        let generation = preview.generation
        return .run { send in
            let isPlaying = await client.isMediaPlaying(mediaPlayer)
            await send(.mediaPlaybackLoaded(generation: generation, isPlaying: isPlaying))
        }
        .cancellable(id: CancelID.media, cancelInFlight: true)
    }

    private func clear(_ state: inout State) {
        state.isEnabled = false
        state.authorization = .unknown
        state.isObserving = false
        state.hoverGeneration &+= 1
        state.hover = nil
        state.preview = nil
        state.status = .idle
    }
}

enum DockPreviewFailure: Error, Equatable, Sendable {
    case windowListing
    case capture
    case activation
}

