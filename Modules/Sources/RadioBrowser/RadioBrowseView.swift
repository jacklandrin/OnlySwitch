import ComposableArchitecture
import SwiftUI

/// Search and filter radio-browser.info, audition stations and save them.
struct RadioBrowseView: View {
    @Bindable var store: StoreOf<RadioBrowseFeature>
    let addingStationIDs: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RadioSearchField(
                    prompt: RadioStrings.text("Radio Search Stations"),
                    text: $store.query.text.sending(\.searchTextChanged)
                )
                categoryMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            content
        }
        .task { await store.send(.task).finish() }
        // Auditions belong to this tab; switching tabs or closing Settings ends them.
        .onDisappear { store.send(.disappeared) }
    }

    private var categoryMenu: some View {
        Menu {
            Button(RadioStrings.text("Radio Popular"), systemImage: "flame") { store.send(.categorySelected(.popular)) }
            Button(RadioStrings.text("Radio Top Voted"), systemImage: "hand.thumbsup") { store.send(.categorySelected(.topVoted)) }
            if !store.countries.isEmpty {
                Menu(RadioStrings.text("Radio Country")) {
                    ForEach(store.countries) { country in
                        Button("\(flag(country.code)) \(country.name)") {
                            store.send(.categorySelected(.country(code: country.code, name: country.name)))
                        }
                    }
                }
            }
            if !store.tags.isEmpty {
                Menu(RadioStrings.text("Radio Tag")) {
                    ForEach(store.tags) { tag in
                        Button(tag.name) { store.send(.categorySelected(.tag(tag.name))) }
                    }
                }
            }
        } label: {
            Label(categoryTitle, systemImage: categoryIcon)
        }
        .fixedSize()
        .help(categoryTitle)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            ContentUnavailableView {
                Label(
                    RadioStrings.text(error == .serverUnavailable ? "Radio Browse Server Unavailable" : "Radio Browse Unavailable"),
                    systemImage: error == .serverUnavailable ? "exclamationmark.icloud" : "wifi.exclamationmark"
                )
            } actions: {
                Button(RadioStrings.text("Radio Retry")) { store.send(.retry) }
            }
            .frame(maxHeight: .infinity)
        case .loaded where store.stations.isEmpty:
            ContentUnavailableView {
                Label(RadioStrings.text("Radio No Results"), systemImage: "magnifyingglass")
            } description: {
                Text(RadioStrings.text("Radio No Results Message"))
            }
            .frame(maxHeight: .infinity)
        case .loaded:
            List {
                ForEach(store.stations) { station in
                    RadioBrowserRow(
                        station: station,
                        isFavorite: store.state.isFavorite(station),
                        isAdding: addingStationIDs.contains(station.id),
                        isPreviewing: store.previewingStationID == station.id,
                        send: { store.send($0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                    .onAppear {
                        if station.id == store.stations.last?.id { store.send(.loadMore) }
                    }
                }
                footer
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if store.isLoadingMore {
                ProgressView().controlSize(.small)
            } else if store.canLoadMore {
                Button(RadioStrings.text("Radio Load More")) { store.send(.loadMore) }
                    .buttonStyle(.borderless)
            }
            if let url = URL(string: "https://www.radio-browser.info") {
                Link(RadioStrings.text("Radio Powered By"), destination: url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var categoryTitle: String {
        switch store.query.category {
        case .popular: RadioStrings.text("Radio Popular")
        case .topVoted: RadioStrings.text("Radio Top Voted")
        case let .country(code, name): "\(flag(code)) \(name)"
        case let .tag(tag): tag
        }
    }

    private var categoryIcon: String {
        switch store.query.category {
        case .popular: "flame"
        case .topVoted: "hand.thumbsup"
        case .country: "globe"
        case .tag: "tag"
        }
    }

    private func flag(_ code: String) -> String {
        RadioBrowserStation.flag(code) ?? ""
    }
}

private struct RadioBrowserRow: View {
    let station: RadioBrowserStation
    let isFavorite: Bool
    let isAdding: Bool
    let isPreviewing: Bool
    let send: (RadioBrowseFeature.Action) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            RadioStationArtwork(name: station.name, url: station.favicon, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .lineLimit(1)
                Text(isPreviewing ? RadioStrings.text("Radio Previewing") : station.detail)
                    .font(.caption)
                    .foregroundStyle(isPreviewing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button(
                    RadioStrings.text(isPreviewing ? "Radio Stop Preview" : "Radio Preview"),
                    systemImage: isPreviewing ? "stop.circle.fill" : "play.circle"
                ) { send(.previewTapped(station)) }
                    .font(.title2)
                    .foregroundStyle(isPreviewing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .help(RadioStrings.text(isPreviewing ? "Radio Stop Preview" : "Radio Preview"))

                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28)
                } else if isFavorite {
                    Label(RadioStrings.text("Radio In Favorites"), systemImage: "star.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .frame(width: 28)
                        .help(RadioStrings.text("Radio In Favorites"))
                } else {
                    Button(RadioStrings.text("Radio Add To Favorites"), systemImage: "star") { send(.favoriteTapped(station)) }
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .help(RadioStrings.text("Radio Add To Favorites"))
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isPreviewing ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.05 : 0)))
        }
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(RadioStrings.text(isPreviewing ? "Radio Stop Preview" : "Radio Preview"), systemImage: "play.fill") { send(.previewTapped(station)) }
            if !isFavorite {
                Button(RadioStrings.text("Radio Add To Favorites"), systemImage: "star") { send(.favoriteTapped(station)) }
            }
            if let homepage = station.homepage {
                Link(destination: homepage) { Label(homepage.host() ?? homepage.absoluteString, systemImage: "safari") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: RadioStrings.text(isPreviewing ? "Radio Stop Preview" : "Radio Preview")) { send(.previewTapped(station)) }
        .accessibilityAction(named: RadioStrings.text("Radio Add To Favorites")) { send(.favoriteTapped(station)) }
    }
}
