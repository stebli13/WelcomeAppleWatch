import SwiftUI

struct ContentView: View {
    @StateObject private var model = PairingViewModel()
    @ObservedObject private var phone = PhoneSessionManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud ABB Welcome") {
                    LabeledField("API base URL", text: $model.config.apiBase)
                    LabeledField("OAuth token URL", text: $model.config.oauthTokenURL)
                    LabeledField("Refresh URL", text: $model.config.refreshURL)
                    LabeledField("Client ID", text: $model.config.clientID)
                    LabeledField("SmartAP UUID", text: $model.config.smartApUUID)
                }

                Section("Relè") {
                    ForEach($model.config.relays) { $relay in
                        NavigationLink {
                            RelayEditor(relay: $relay, model: model)
                        } label: {
                            HStack {
                                Text(relay.name)
                                Spacer()
                                if !relay.isComplete {
                                    Text("da completare").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .onDelete(perform: model.deleteRelays)
                    Button("Aggiungi relè", systemImage: "plus", action: model.addRelay)
                }

                Section("Posto esterno") {
                    ForEach($model.config.stations) { $station in
                        NavigationLink(station.name) {
                            StationEditor(station: $station, relays: model.config.relays)
                        }
                    }
                    .onDelete(perform: model.deleteStations)
                    Button("Aggiungi posto esterno", systemImage: "plus", action: model.addStation)
                }

                Section("Sessione (dalla cattura)") {
                    LabeledField("Access token", text: $model.accessToken, secure: true)
                    LabeledField("Refresh token", text: $model.refreshToken, secure: true)
                    LabeledField("Scade tra (sec)", text: $model.expiresInSeconds)
                }

                Section {
                    Button {
                        model.sendToWatch()
                    } label: {
                        Label("Invia al Watch", systemImage: "applewatch")
                    }
                    .disabled(!model.canSave)

                    if let err = phone.lastSyncError {
                        Text("Errore di sincronizzazione: \(err)")
                            .font(.footnote).foregroundStyle(.red)
                    } else if phone.isWatchReachable {
                        Text("Watch raggiungibile").font(.footnote).foregroundStyle(.green)
                    }
                } footer: {
                    Text("I valori arrivano dalla cattura una tantum: vedi docs/traffic-capture-playbook.md. I token restano nel Portachiavi e vengono sincronizzati cifrati sul Watch.")
                }
            }
            .navigationTitle("Welcome Gate")
        }
    }
}

struct RelayEditor: View {
    @Binding var relay: Relay
    @ObservedObject var model: PairingViewModel

    var body: some View {
        Form {
            Section("Relè") {
                LabeledField("Nome", text: $relay.name)
            }
            Section("Indirizzo (dalla cattura)") {
                LabeledField("Device ID", text: $relay.deviceID)
                LabeledField("Channel ID", text: $relay.channelID)
                LabeledField("Datapoint ID", text: $relay.datapointID)
                LabeledField("Valore apertura", text: $relay.openValue)
            }
            Section {
                Button {
                    Task { await model.test(relay) }
                } label: {
                    HStack {
                        Label("Prova: attiva ora", systemImage: "lock.open")
                        if model.testingRelayID == relay.id { Spacer(); ProgressView() }
                    }
                }
                .disabled(!model.canSave || model.testingRelayID != nil)

                if let result = model.testResults[relay.id] {
                    Text(result).font(.footnote)
                }
            }
        }
        .navigationTitle(relay.name)
    }
}

struct StationEditor: View {
    @Binding var station: OutdoorStation
    let relays: [Relay]

    var body: some View {
        Form {
            Section("Posto esterno") {
                LabeledField("Nome", text: $station.name)
                LabeledField("Percorso foto", text: Binding(
                    get: { station.snapshotPath ?? "" },
                    set: { station.snapshotPath = $0.isEmpty ? nil : $0 }))
            }
            Section("Relè mostrati su questo posto esterno") {
                ForEach(relays) { relay in
                    Toggle(relay.name, isOn: Binding(
                        get: { station.relayIDs.contains(relay.id) },
                        set: { isOn in
                            station.relayIDs.removeAll { $0 == relay.id }
                            if isOn { station.relayIDs.append(relay.id) }
                        }))
                }
            }
        }
        .navigationTitle(station.name)
    }
}

/// Title on the left, editable value on the right.
struct LabeledField: View {
    let title: String
    @Binding var text: String
    var secure = false

    init(_ title: String, text: Binding<String>, secure: Bool = false) {
        self.title = title
        self._text = text
        self.secure = secure
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }
}

#Preview { ContentView() }
