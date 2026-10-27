import SwiftUI

/// One relay (e.g. "Cancello-citofono"): a big button that fires it.
struct RelayDetailView: View {
    @EnvironmentObject private var store: WatchStore
    let relay: Relay

    var body: some View {
        let state = store.state(of: relay)
        VStack(spacing: 8) {
            Button {
                Task { await store.activate(relay) }
            } label: {
                ZStack {
                    Circle().fill(color(for: state).gradient)
                    glyph(for: state).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 104, height: 104)
            .disabled(state == .working)
            .accessibilityLabel("Apri \(relay.name)")

            caption(for: state)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .navigationTitle(relay.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(relay)
                } label: {
                    Image(systemName: store.isFavorite(relay) ? "star.fill" : "star")
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("Preferito")
            }
        }
        .containerBackground(Theme.background.gradient, for: .navigation)
    }

    private func color(for state: WatchStore.ActivationState) -> Color {
        switch state {
        case .success: return Theme.success
        case .failure: return Theme.failure
        default: return Theme.row
        }
    }

    @ViewBuilder
    private func glyph(for state: WatchStore.ActivationState) -> some View {
        switch state {
        case .working:
            ProgressView().tint(.white)
        case .success:
            Image(systemName: "checkmark").font(.title.bold())
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
        case .idle:
            VStack(spacing: 2) {
                Image(systemName: "lock.open.fill").font(.title2)
                Text("Apri").font(.headline)
            }
        }
    }

    @ViewBuilder
    private func caption(for state: WatchStore.ActivationState) -> some View {
        switch state {
        case .working: Text("Invio…").foregroundStyle(Theme.sectionText)
        case .success: Text("Comando inviato").foregroundStyle(Theme.success)
        case let .failure(message): Text(message).foregroundStyle(Theme.failure)
        case .idle: Text("Tocca per attivare").foregroundStyle(Theme.sectionText)
        }
    }
}
