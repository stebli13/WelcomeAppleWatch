import SwiftUI

struct ContentView: View {
    @StateObject private var model = PairingViewModel()
    @ObservedObject private var phone = PhoneSessionManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField("Indirizzo", text: $model.config.baseURL)
                    LabeledField("Token", text: $model.token, secure: true)
                    Button {
                        Task { await model.loadEntities() }
                    } label: {
                        HStack {
                            Label("Collega e carica entità", systemImage: "link")
                            if model.isLoadingEntities { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!model.hasConnection || model.isLoadingEntities)
                    if let status = model.entitiesStatus {
                        Text(status).font(.footnote)
                    }
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("Il token si crea in Home Assistant: Profilo → Sicurezza → Token di accesso di lunga durata. Vedi docs/home-assistant-setup.md.")
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
                            StationEditor(station: $station, model: model)
                        }
                    }
                    .onDelete(perform: model.deleteStations)
                    Button("Aggiungi posto esterno", systemImage: "plus", action: model.addStation)
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
                    Text("Il token resta nel Portachiavi e viene sincronizzato cifrato sul Watch.")
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
            Section("Entità Home Assistant") {
                LabeledField("Entity ID", text: $relay.entityID)
                NavigationLink("Scegli dall’elenco") {
                    EntityPicker(
                        title: "Entità",
                        entities: model.entities,
                        domains: ["button", "switch", "lock", "cover", "light",
                                  "script", "scene", "input_boolean", "automation"],
                        selection: $relay.entityID)
                }
                .disabled(model.entities.isEmpty)
                if model.entities.isEmpty {
                    Text("Tocca “Collega e carica entità” nella schermata principale per usare l’elenco.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                .disabled(!model.hasConnection || !relay.isComplete || model.testingRelayID != nil)

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
    @ObservedObject var model: PairingViewModel

    var body: some View {
        Form {
            Section("Posto esterno") {
                LabeledField("Nome", text: $station.name)
            }
            Section("Foto (opzionale)") {
                LabeledField("Entity ID", text: Binding(
                    get: { station.pictureEntityID ?? "" },
                    set: { station.pictureEntityID = $0.isEmpty ? nil : $0 }))
                NavigationLink("Scegli dall’elenco") {
                    EntityPicker(
                        title: "Telecamera",
                        entities: model.entities,
                        domains: ["camera", "image"],
                        selection: Binding(
                            get: { station.pictureEntityID ?? "" },
                            set: { station.pictureEntityID = $0.isEmpty ? nil : $0 }))
                }
                .disabled(model.entities.isEmpty)
            }
            Section("Relè mostrati su questo posto esterno") {
                ForEach(model.config.relays) { relay in
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

/// Searchable list of Home Assistant entities, limited to the given domains.
struct EntityPicker: View {
    let title: String
    let entities: [HAEntity]
    let domains: [String]
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var visible: [HAEntity] {
        entities.filter { entity in
            guard let domain = entity.entityID.split(separator: ".").first,
                  domains.contains(String(domain)) else { return false }
            return query.isEmpty
                || entity.name.localizedCaseInsensitiveContains(query)
                || entity.entityID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(visible) { entity in
            Button {
                selection = entity.entityID
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(entity.name)
                        Text(entity.entityID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entity.entityID == selection {
                        Image(systemName: "checkmark").foregroundStyle(.blue)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .searchable(text: $query, prompt: "Cerca (es. cancello)")
        .navigationTitle(title)
        .overlay {
            if visible.isEmpty { ContentUnavailableView.search }
        }
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
