#if DEBUG
import SwiftUI

/// Hosts a screen the way RootView does (vertical page + navigation), so the
/// canvas shows the real background and titles.
private struct Host<Content: View>: View {
    let store: WatchStore
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            TabView { content }
                .tabViewStyle(.verticalPage)
        }
        .environmentObject(store)
        .tint(Theme.rowText)
    }
}

#Preview("Controllo accessi") {
    Host(store: .preview(favoriteNames: ["Cancello-citofono"])) { AccessControlView() }
}

#Preview("Controllo accessi · in corso") {
    Host(store: .preview(states: ["Cancello-citofono": .working])) { AccessControlView() }
}

#Preview("Controllo accessi · aperto") {
    Host(store: .preview(states: ["Cancello-citofono": .success])) { AccessControlView() }
}

#Preview("Dispositivi") {
    Host(store: .preview()) { DevicesView() }
}

#Preview("Home · preferiti") {
    Host(store: .preview(favoriteNames: ["Cancello-citofono", "Basculante-citofono"])) { HomeView() }
}

#Preview("Home · vuota") {
    Host(store: .preview()) { HomeView() }
}

#Preview("Relè") {
    let store = WatchStore.preview()
    return NavigationStack { RelayDetailView(relay: store.relays[0]) }
        .environmentObject(store)
}

#Preview("Relè · aperto") {
    let store = WatchStore.preview(states: ["Cancello-citofono": .success])
    return NavigationStack { RelayDetailView(relay: store.relays[0]) }
        .environmentObject(store)
}

#Preview("Relè · errore") {
    let store = WatchStore.preview(states: [
        "Cancello-citofono": .failure("Token non valido. Creane uno nuovo in Home Assistant.")])
    return NavigationStack { RelayDetailView(relay: store.relays[0]) }
        .environmentObject(store)
}

#Preview("Posto esterno") {
    let store = WatchStore.preview()
    return NavigationStack { StationDetailView(station: store.stations[0]) }
        .environmentObject(store)
}

#Preview("Non abbinato") {
    NotPairedView()
}
#endif
