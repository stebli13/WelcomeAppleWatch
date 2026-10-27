import SwiftUI

struct ContentView: View {
    @StateObject private var model = PairingViewModel()
    @ObservedObject private var phone = PhoneSessionManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("ABB Welcome cloud endpoint") {
                    field("API base URL", $model.config.apiBase)
                    field("OAuth token URL", $model.config.oauthTokenURL)
                    field("Refresh URL", $model.config.refreshURL)
                    field("Client ID", $model.config.clientID)
                }
                Section("Door opener addressing") {
                    field("SmartAP UUID", $model.config.smartApUUID)
                    field("Device ID", $model.config.deviceID)
                    field("Channel ID", $model.config.channelID)
                    field("Datapoint ID", $model.config.datapointID)
                    field("Open value", $model.config.openValue)
                }
                Section("Session (from your capture)") {
                    secureField("Access token", $model.accessToken)
                    secureField("Refresh token", $model.refreshToken)
                    field("Expires in (sec)", $model.expiresInSeconds)
                }

                Section {
                    Button {
                        Task { await model.testOpen() }
                    } label: {
                        HStack {
                            Label("Test: open the door now", systemImage: "lock.open")
                            if model.isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!model.canSave || model.isTesting)

                    if let state = model.testState {
                        Text(state).font(.footnote)
                    }
                }

                Section {
                    Button {
                        model.sendToWatch()
                    } label: {
                        Label("Send to Watch", systemImage: "applewatch")
                    }
                    .disabled(!model.canSave)

                    if let err = phone.lastSyncError {
                        Text("Sync error: \(err)")
                            .font(.footnote).foregroundStyle(.red)
                    } else if phone.isWatchReachable {
                        Text("Watch reachable").font(.footnote).foregroundStyle(.green)
                    }
                } footer: {
                    Text("Values come from the one-time traffic capture — see docs/traffic-capture-playbook.md. Tokens are stored only in the Keychain and synced encrypted to your watch.")
                }
            }
            .navigationTitle("Welcome Gate")
        }
    }

    private func field(_ title: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            TextField(title, text: value)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func secureField(_ title: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            SecureField(title, text: value)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview { ContentView() }
