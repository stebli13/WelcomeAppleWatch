import SwiftUI

/// The iPhone app's bottom tab bar (Home · Dispositivi · Controllo accessi)
/// becomes vertically paged tabs: turn the Digital Crown to switch screens.
struct RootView: View {
    enum Page: Hashable { case home, devices, access }

    @StateObject private var store = WatchStore()
    @ObservedObject private var session = WatchSessionManager.shared
    // Start on "Controllo accessi": opening the gate is the main job.
    @State private var page: Page = .access

    var body: some View {
        Group {
            if session.isPaired {
                NavigationStack {
                    TabView(selection: $page) {
                        HomeView().tag(Page.home)
                        DevicesView().tag(Page.devices)
                        AccessControlView().tag(Page.access)
                    }
                    .tabViewStyle(.verticalPage)
                    .navigationDestination(for: Relay.self) { RelayDetailView(relay: $0) }
                    .navigationDestination(for: OutdoorStation.self) { StationDetailView(station: $0) }
                }
                .environmentObject(store)
            } else {
                NotPairedView()
            }
        }
        .tint(Theme.rowText)
        .onChange(of: session.revision) { store.reload() }
    }
}

struct NotPairedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.largeTitle).foregroundStyle(Theme.rowText)
            Text("Apri Welcome Gate sull’iPhone e tocca “Invia al Watch”.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.sectionText)
        }
        .padding()
        .containerBackground(Theme.background.gradient, for: .navigation)
    }
}
