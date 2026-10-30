import ComposableArchitecture
import SwiftUI

/// The user's saved stations.
struct RadioFavoritesView: View {
    @Bindable var store: StoreOf<RadioFavoritesFeature>
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RadioSearchField(prompt: RadioStrings.text("Radio Search Favorites"), text: $store.filterText)
                Button(RadioStrings.text("Radio Add Manually"), systemImage: "plus") { store.send(.addTapped) }
                    .help(RadioStrings.text("Radio Add Manually"))
                Menu {
                    Button(RadioStrings.text("Radio Import"), systemImage: "square.and.arrow.down") { store.send(.importTapped) }
                    Button(RadioStrings.text("Radio Export"), systemImage: "square.and.arrow.up") { store.send(.exportTapped) }
                    Divider()
                    Text(RadioStrings.text("Radio Import Export Help"))
                } label: {
                    Label(RadioStrings.text("Radio More"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(RadioStrings.text("Radio More"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.favorites.isEmpty {
            ContentUnavailableView {
                Label(RadioStrings.text("Radio No Favorites"), systemImage: "radio")
            } description: {
                Text(RadioStrings.text("Radio No Favorites Message"))
            } actions: {
                Button(RadioStrings.text("Radio Browse Stations"), action: onBrowse)
                    .buttonStyle(.borderedProminent)
                Button(RadioStrings.text("Radio Add Manually")) { store.send(.addTapped) }
            }
            .frame(maxHeight: .infinity)
        } else if store.visibleFavorites.isEmpty {
            ContentUnavailableView.search(text: store.filterText)
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(store.visibleFavorites) { favorite in
                    RadioFavoriteRow(
                        favorite: favorite,
                        isCurrent: store.state.isCurrent(favorite.id),
                        isPlaying: store.state.isPlaying(favorite.id),
                        send: { store.send($0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct RadioFavoriteRow: View {
    let favorite: RadioFavorite
    let isCurrent: Bool
    let isPlaying: Bool
    let send: (RadioFavoritesFeature.Action) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RadioStationArtwork(name: favorite.name, url: favorite.favicon, size: 40)
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .bold))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.tint, in: .circle)
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if isCurrent {
                        Text(RadioStrings.text("Radio Now Playing"))
                            .foregroundStyle(.tint)
                        Text(verbatim: "·")
                    }
                    Text(favorite.host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if isHovering {
                    Button(RadioStrings.text("Radio Edit"), systemImage: "pencil") { send(.editTapped(favorite.id)) }
                        .help(RadioStrings.text("Radio Edit"))
                    Button(RadioStrings.text("Radio Delete"), systemImage: "trash") { send(.deleteTapped(favorite.id)) }
                        .help(RadioStrings.text("Radio Delete"))
                }
                Button(
                    RadioStrings.text(isPlaying ? "Radio Stop" : "Radio Play"),
                    systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill"
                ) { send(.playTapped(favorite.id)) }
                    .font(.title2)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .opacity(isHovering || isCurrent ? 1 : 0.55)
                    .help(RadioStrings.text(isPlaying ? "Radio Stop" : "Radio Play"))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.05 : 0)))
        }
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { send(.playTapped(favorite.id)) }
        .contextMenu {
            Button(RadioStrings.text(isPlaying ? "Radio Stop" : "Radio Play"), systemImage: isPlaying ? "stop.fill" : "play.fill") { send(.playTapped(favorite.id)) }
            Button(RadioStrings.text("Radio Edit"), systemImage: "pencil") { send(.editTapped(favorite.id)) }
            Button(RadioStrings.text("Radio Copy URL"), systemImage: "doc.on.doc") { send(.copyURLTapped(favorite.id)) }
            Divider()
            Button(RadioStrings.text("Radio Delete"), systemImage: "trash", role: .destructive) { send(.deleteTapped(favorite.id)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityAction(named: RadioStrings.text(isPlaying ? "Radio Stop" : "Radio Play")) { send(.playTapped(favorite.id)) }
        .accessibilityAction(named: RadioStrings.text("Radio Edit")) { send(.editTapped(favorite.id)) }
        .accessibilityAction(named: RadioStrings.text("Radio Delete")) { send(.deleteTapped(favorite.id)) }
    }
}
