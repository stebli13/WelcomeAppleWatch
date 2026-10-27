import SwiftUI

/// One outdoor station: its latest picture and a button for each relay it
/// controls, so you can see who is there and open from the same screen.
struct StationDetailView: View {
    @EnvironmentObject private var store: WatchStore
    let station: OutdoorStation

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                StationPicture(data: store.snapshots[station.id])
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                ForEach(store.relays(for: station)) { relay in
                    RelayButton(relay: relay)
                }
            }
        }
        .navigationTitle(station.name)
        .task { await store.refreshSnapshot(of: station) }
        .containerBackground(Theme.background.gradient, for: .navigation)
    }
}

/// Full-width "open" button for a relay, used on the station and Home screens.
struct RelayButton: View {
    @EnvironmentObject private var store: WatchStore
    let relay: Relay

    var body: some View {
        let state = store.state(of: relay)
        Button {
            Task { await store.activate(relay) }
        } label: {
            HStack(spacing: 8) {
                RelayStateBox(state: state)
                Text(relay.name)
                    .font(.footnote)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "lock.open.fill").font(.footnote)
            }
            .foregroundStyle(Theme.rowText)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.row))
        }
        .buttonStyle(.plain)
        .disabled(state == .working)
        .accessibilityLabel("Apri \(relay.name)")
    }
}
