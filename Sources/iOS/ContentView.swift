import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PairingViewModel()
    @ObservedObject private var phone = PhoneSessionManager.shared

    @State private var showImporter = false
    @State private var pendingFile: URL?
    @State private var passphrase = ""

    var body: some View {
        NavigationStack {
            Form {
                accountSection

                if model.isImported {
                    Section("Relè") {
                        ForEach($model.config.relays) { $relay in
                            NavigationLink {
                                RelayEditor(relay: $relay, model: model)
                            } label: {
                                RelayListRow(relay: relay, model: model)
                            }
                        }
                        .onDelete(perform: model.deleteRelays)
                        Button("Aggiungi relè", systemImage: "plus", action: model.addRelay)
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
                        Text("Al Watch vanno solo i nomi. Certificato e password restano nel Portachiavi dell’iPhone: quando tocchi Apri sul Watch, è l’iPhone a mandare il comando al server ABB, da casa o da fuori.")
                    }
                }
            }
            .navigationTitle("Welcome Gate")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.data, .json]) { result in
                if case let .success(url) = result {
                    passphrase = ""
                    pendingFile = url
                }
            }
            .alert("Passphrase del file",
                   isPresented: Binding(get: { pendingFile != nil },
                                        set: { if !$0 { pendingFile = nil } })) {
                SecureField("Passphrase", text: $passphrase)
                Button("Importa") {
                    if let url = pendingFile { model.importFile(at: url, passphrase: passphrase) }
                    passphrase = ""
                    pendingFile = nil
                }
                Button("Annulla", role: .cancel) {
                    passphrase = ""
                    pendingFile = nil
                }
            } message: {
                Text("Quella scelta sul Mac con “abb_probe.py export”.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            if let account = model.account {
                LabeledContent("Server", value: "\(account.cloudHost):\(account.cloudPort)")
                LabeledContent("Utente SIP", value: account.sipUsername)
                LabeledContent("Sistema", value: account.sipDomain)
            }
            Button {
                showImporter = true
            } label: {
                Label(model.isImported ? "Importa di nuovo" : "Importa file dal Mac",
                      systemImage: "square.and.arrow.down")
            }
            if let status = model.importStatus {
                Text(status).font(.footnote)
            }
            if model.isImported {
                Button("Dimentica abbinamento", role: .destructive, action: model.forget)
            }
        } header: {
            Text("Abbinamento ABB-Welcome")
        } footer: {
            if !model.isImported {
                Text("Sul Mac: “abb_probe.py export”, poi AirDrop del file su iPhone (Salva in File) e importalo qui. Vedi docs/direct-gateway.md.")
            }
        }
    }
}

struct RelayListRow: View {
    let relay: Relay
    @ObservedObject var model: PairingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(relay.name)
                Spacer()
                if model.testingRelayID == relay.id { ProgressView() }
            }
            Text("\(relay.body)\(relay.inCall ? " · in chiamata" : "")")
                .font(.caption).foregroundStyle(.secondary)
            if let result = model.testResults[relay.id] {
                Text(result).font(.caption)
            }
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
            Section {
                LabeledField("Comando", text: $relay.body)
                LabeledField("Posto esterno", text: $relay.stationID)
                Toggle("Apri chiamata prima", isOn: $relay.inCall)
            } header: {
                Text("Comando SIP")
            } footer: {
                Text("Relè all’indirizzo N: “b:N”, senza chiamata. Portoncino: “1”, in chiamata.")
            }
            Section {
                Button {
                    Task { await model.test(relay) }
                } label: {
                    HStack {
                        Label("Prova: apri ora", systemImage: "lock.open")
                        if model.testingRelayID == relay.id { Spacer(); ProgressView() }
                    }
                }
                .disabled(!relay.isComplete || model.testingRelayID != nil)

                if let result = model.testResults[relay.id] {
                    Text(result).font(.footnote)
                }
            } footer: {
                Text("Apre davvero: provalo solo quando è sicuro.")
            }
        }
        .navigationTitle(relay.name)
    }
}

/// Title on the left, editable value on the right.
struct LabeledField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview { ContentView() }
