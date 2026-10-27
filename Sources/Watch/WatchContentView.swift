import SwiftUI

struct WatchContentView: View {
    @StateObject private var model = WatchGateViewModel()
    @ObservedObject private var session = WatchSessionManager.shared

    var body: some View {
        VStack(spacing: 10) {
            if session.isPaired {
                openButton
                statusLine
            } else {
                notPaired
            }
        }
        .padding()
    }

    private var openButton: some View {
        Button {
            Task { await model.openDoor() }
        } label: {
            ZStack {
                Circle().fill(buttonColor.gradient)
                Group {
                    switch model.state {
                    case .opening:
                        ProgressView().tint(.white)
                    case .success:
                        Image(systemName: "checkmark")
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                    case .idle:
                        VStack(spacing: 2) {
                            Image(systemName: "lock.open.fill").font(.title2)
                            Text("Open").font(.headline)
                        }
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 110)
        .disabled(model.state == .opening)
    }

    private var statusLine: some View {
        Group {
            if case let .failure(message) = model.state {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if case .success = model.state {
                Text("Door opened").font(.caption2).foregroundStyle(.green)
            } else {
                Text("Tap to open").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var notPaired: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("Open the Welcome Gate app on your iPhone and tap “Send to Watch”.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonColor: Color {
        switch model.state {
        case .success: return .green
        case .failure: return .red
        default: return .blue
        }
    }
}

#Preview { WatchContentView() }
