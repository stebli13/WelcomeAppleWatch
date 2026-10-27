import SwiftUI

/// "Controllo accessi": the Relè list and the Posto esterno, as on iPhone.
/// Tap a relay to open its screen; swipe a relay left to activate it straight
/// from the list.
struct AccessControlView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        List {
            Section {
                ForEach(store.relays) { relay in
                    NavigationLink(value: relay) {
                        RelayRow(relay: relay)
                    }
                    .listRowBackground(rowBackground)
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await store.activate(relay) }
                        } label: {
                            Label("Apri", systemImage: "lock.open.fill")
                        }
                        .tint(Theme.accent)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            store.toggleFavorite(relay)
                        } label: {
                            Label("Preferito", systemImage: store.isFavorite(relay) ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                SectionHeader(title: "Relè")
            }

            Section {
                ForEach(store.stations) { station in
                    NavigationLink(value: station) {
                        HStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .foregroundStyle(Theme.rowText)
                            Text(station.name)
                                .font(.footnote)
                                .foregroundStyle(Theme.rowText)
                                .lineLimit(2)
                        }
                    }
                    .listRowBackground(rowBackground)
                }
            } header: {
                SectionHeader(title: "Posto esterno")
            }
        }
        .navigationTitle("Controllo accessi")
        .containerBackground(Theme.background.gradient, for: .tabView)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12).fill(Theme.row)
    }
}

struct RelayRow: View {
    @EnvironmentObject private var store: WatchStore
    let relay: Relay

    var body: some View {
        HStack(spacing: 8) {
            RelayStateBox(state: store.state(of: relay))
            Text(relay.name)
                .font(.footnote)
                .foregroundStyle(Theme.rowText)
                .lineLimit(2)
            Spacer(minLength: 0)
            if store.isFavorite(relay) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }
}
