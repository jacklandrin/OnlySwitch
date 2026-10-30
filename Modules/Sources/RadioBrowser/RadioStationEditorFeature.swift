import ComposableArchitecture
import Foundation

/// The add/edit sheet for entering a station by hand.
@Reducer
public struct RadioStationEditorFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Mode: Equatable, Sendable {
            case add
            case edit(RadioFavorite)
        }

        public var mode: Mode
        public var name: String
        public var streamURL: String
        public var existing: [RadioFavorite]
        public var nameEdited = false
        public var attemptedSave = false

        public init(mode: Mode, existing: [RadioFavorite]) {
            self.mode = mode
            self.existing = existing
            switch mode {
            case .add:
                name = ""
                streamURL = ""
            case let .edit(favorite):
                name = favorite.name
                streamURL = favorite.streamURL
            }
        }

        public var editingID: UUID? {
            if case let .edit(favorite) = mode { favorite.id } else { nil }
        }

        public var validation: Result<RadioFavoriteDraft.Valid, RadioFavoriteDraft.Issue> {
            RadioFavoriteDraft(name: name, streamURL: streamURL).validate(existing: existing, editingID: editingID)
        }

        public var canSave: Bool {
            if case .success = validation { true } else { false }
        }

        /// Only issues the user can act on now: URL problems once a URL was typed,
        /// a missing name once the name was touched, and everything after a save attempt.
        public var visibleIssue: RadioFavoriteDraft.Issue? {
            guard case let .failure(issue) = validation else { return nil }
            if attemptedSave { return issue }
            switch issue {
            case .emptyName:
                return nameEdited ? issue : urlIssue
            case .invalidURL, .duplicateURL:
                return streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : issue
            }
        }

        private var urlIssue: RadioFavoriteDraft.Issue? {
            guard !streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if case let .failure(issue) = RadioFavoriteDraft(name: "-", streamURL: streamURL).validate(existing: existing, editingID: editingID) {
                return issue
            }
            return nil
        }
    }

    public enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case saveTapped
        case cancelTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable {
            case save(RadioFavoriteDraft.Valid, editingID: UUID?)
        }
    }

    @Dependency(\.dismiss) private var dismiss

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.name):
                state.nameEdited = true
                return .none
            case .binding, .delegate:
                return .none
            case .saveTapped:
                switch state.validation {
                case let .success(valid):
                    return .send(.delegate(.save(valid, editingID: state.editingID)))
                case .failure:
                    state.attemptedSave = true
                    return .none
                }
            case .cancelTapped:
                return .run { [dismiss] _ in await dismiss() }
            }
        }
    }
}
