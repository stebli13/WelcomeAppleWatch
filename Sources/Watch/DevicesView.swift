import SwiftUI

/// "Dispositivi": the outdoor-station tiles with their camera picture and the
/// globe badge (connected through the cloud), plus a refresh button.
struct DevicesView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Posto esterno")
                ForEach(store.stations) { station in
                    NavigationLink(value: station) {
                        StationTile(station: station)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Dispositivi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshSnapshots() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Aggiorna")
            }
        }
        .task { await store.refreshSnapshots() }
        .containerBackground(Theme.background.gradient, for: .tabView)
    }
}

/// Picture with the name bar underneath, like the iPhone tile.
struct StationTile: View {
    @EnvironmentObject private var store: WatchStore
    let station: OutdoorStation

    var body: some View {
        VStack(spacing: 0) {
            StationPicture(data: store.snapshots[station.id])
                .frame(height: 80)
            HStack(spacing: 4) {
                Text(station.name)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "globe.europe.africa.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.header)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
