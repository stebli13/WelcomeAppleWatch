import SwiftUI

/// Home: the "Posto esterno" tile as on iPhone, plus "Preferiti" — relays you
/// starred, opened with a single tap.
struct HomeView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Preferiti")
                if store.favoriteRelays.isEmpty {
                    Text("Scorri un relè verso destra in Controllo accessi, o tocca ☆, per aggiungerlo qui.")
                        .font(.caption2)
                        .foregroundStyle(Theme.sectionText)
                } else {
                    ForEach(store.favoriteRelays) { RelayButton(relay: $0) }
                }

                SectionHeader(title: "Posto esterno")
                    .padding(.top, 6)
                ForEach(store.stations) { station in
                    NavigationLink(value: station) {
                        StationTile(station: station)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Home")
        .task { await store.refreshSnapshots() }
        .containerBackground(Theme.background.gradient, for: .tabView)
    }
}
