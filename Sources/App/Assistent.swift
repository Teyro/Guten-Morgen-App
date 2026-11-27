import SwiftUI
import MorgenKern

/// Einrichtungs-Assistent: führt Schritt für Schritt durch Schule, Kürzel, Mensa, Untis und IServ.
/// Erscheint einmal für alle (neu oder schon eingerichtet – Vorhandenes ist vorausgefüllt) und lässt sich in den Einstellungen neu starten.
struct EinrichtungsAssistent: View {
    @Bindable var kern: Kern
    private enum Schritt: Int, CaseIterable { case willkommen, schule, kuerzel, essen, untis, iserv, fertig }
    @State private var schritt = Schritt.willkommen
    /// true = eingebaute Zugangsdaten der Schule, false = eigene eintragen
    @State private var schulDaten = true
    @State private var code = ""
    @State private var laedt = false
    @State private var meldung = ""
    @State private var geladen = false

    static let fertigSchluessel = "assistentFertig1"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressView(value: Double(schritt.rawValue), total: Double(Schritt.allCases.count - 1)).tint(.blue)
                        .listRowBackground(Color.clear)
                }
                inhalt
            }
            .navigationTitle(titel).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if schritt != .willkommen {
                    ToolbarItem(placement: .topBarLeading) { Button("Zurück") { withAnimation { schritt = Schritt(rawValue: schritt.rawValue - 1)! } } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Später") { beenden() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button { weiter() } label: {
                    Text(schritt == .fertig ? "Los geht’s" : schritt == .willkommen ? "Einrichten" : "Weiter")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
                .disabled(schritt == .schule && schulDaten && !geladen && kern.einstellungen.vertretungLink.isEmpty)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { if code.isEmpty { code = kern.schulOrdnerPasswort.isEmpty ? kern.freigabePasswort : kern.schulOrdnerPasswort } }
    }

    private var titel: String {
        switch schritt {
        case .willkommen: "Willkommen"; case .schule: "Schule"; case .kuerzel: "Dein Kürzel"; case .essen: "Mensa"
        case .untis: "WebUntis"; case .iserv: "IServ"; case .fertig: "Fertig"
        }
    }

    @ViewBuilder private var inhalt: some View {
        @Bindable var k = kern
        switch schritt {
        case .willkommen:
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(.blue)
                    Text("Willkommen in der \(Marke.name)").font(.title2.weight(.bold))
                    Text("In ein paar Schritten ist alles eingerichtet: Vertretungsplan, Stundenplan, Mensa, Abwesenheiten und Störungen. Was schon eingetragen ist, bleibt erhalten – du kannst es hier prüfen.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
        case .schule:
            Section {
                Picker("Zugangsdaten", selection: $schulDaten) {
                    Text("Von der Schule").tag(true)
                    Text("Eigene").tag(false)
                }.pickerStyle(.segmented)
            } footer: {
                Text(schulDaten ? "Die Zugänge der Schule (Vertretungsplan-Ordner, Mensa-Portal, Schulobst, Untis, IServ) sind eingebaut. Zum Freischalten brauchst du den Schul-Code – das Passwort des Schul-Ordners."
                     : "Du trägst die Adressen selbst ein – in diesem und den nächsten Schritten.")
            }
            if schulDaten {
                Section {
                    SecureField("Schul-Code", text: $code).textContentType(.password).onSubmit { Task { await laden() } }
                    Button { Task { await laden() } } label: {
                        HStack { Text(geladen ? "Freigeschaltet" : "Freischalten"); Spacer(); if laedt { ProgressView() } else if geladen { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                    }.disabled(code.isEmpty || laedt)
                } footer: { if !meldung.isEmpty { Text(meldung).foregroundStyle(geladen ? Color.secondary : Color.red) } }
            } else {
                Section("Vertretungsplan") {
                    TextField("Freigabe-Link des Ordners", text: $k.einstellungen.vertretungLink).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort der Freigabe", text: $k.freigabePasswort)
                    SecureField("Schul-Ordner-Passwort (Untis-Sicherung)", text: $k.schulOrdnerPasswort)
                }
            }
        case .kuerzel:
            Section {
                TextField("Kürzel, z. B. Sta", text: $k.einstellungen.kuerzel).textInputAutocapitalization(.words).autocorrectionDisabled()
                Toggle("Vertretungsplan zeigen", isOn: $k.einstellungen.vertretung)
            } footer: { Text("So stehst du im Vertretungsplan. Daran erkennt die App deine Vertretungen, Aufsichten und Begleitungen.") }
        case .essen:
            Section {
                Toggle("Ich esse in der Mensa", isOn: $k.einstellungen.mensa)
                if kern.einstellungen.mensa {
                    if !schulDaten { TextField("Adresse des Portals (https://…)", text: $k.einstellungen.mensaAdresse).keyboardType(.URL).textInputAutocapitalization(.never) }
                    TextField("Benutzer", text: $k.einstellungen.mensaBenutzer).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $k.mensaPasswort).textContentType(.password)
                }
            } footer: { Text("Deine Zugangsdaten fürs Kantinen-Portal – dieselben wie im Browser. Dann siehst du den Speiseplan und was du bestellt hast.") }
            Section { Toggle("Schulobst anzeigen", isOn: $k.einstellungen.obst) }
        case .untis:
            Section {
                Toggle("Ich nutze WebUntis", isOn: $k.einstellungen.untisAn)
                if kern.einstellungen.untisAn {
                    if !schulDaten {
                        TextField("Adresse (z. B. hh5586.webuntis.com)", text: $k.einstellungen.untisLink).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Schule", text: $k.einstellungen.untisSchule).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    TextField("Benutzer", text: $k.einstellungen.untisBenutzer).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $k.untisPasswort).textContentType(.password)
                    SecureField("Schlüssel (bei Zwei-Faktor, aus Untis Mobile)", text: $k.untisSchluessel)
                }
            } footer: { Text("Dein Stundenplan kommt dann aus WebUntis. Mit Zwei-Faktor-Anmeldung: in WebUntis Profil → Freigaben → Untis Mobile; den QR-Code kannst du auch später in den Einstellungen scannen.") }
        case .iserv:
            Section {
                Toggle("Ich nutze IServ", isOn: Binding(get: { kern.einstellungen.abwesenheiten || kern.einstellungen.stoerungen },
                                                        set: { kern.einstellungen.abwesenheiten = $0; kern.einstellungen.stoerungen = $0 }))
                if kern.einstellungen.abwesenheiten || kern.einstellungen.stoerungen {
                    if !schulDaten { TextField("Adresse (z. B. schule.de)", text: $k.einstellungen.iservServer).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    TextField("Benutzer (vorname.nachname)", text: $k.einstellungen.iservBenutzer).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $k.iservPasswort).textContentType(.password)
                    Toggle("Abwesenheiten", isOn: $k.einstellungen.abwesenheiten)
                    Toggle("Störungsmeldungen", isOn: $k.einstellungen.stoerungen)
                }
            } footer: { Text("Für fehlende Kinder und Störungsmeldungen. Edupool-Aufgaben verbindest du später in den Einstellungen.") }
        case .fertig:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text("Alles bereit").font(.title2.weight(.bold))
                    Text(zusammenfassung).foregroundStyle(.secondary)
                    Text("Alles lässt sich später unter Einstellungen ändern – dort kannst du den Assistenten auch neu starten.").font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
        }
    }

    private var zusammenfassung: String {
        let e = kern.einstellungen
        return [e.kuerzel.isEmpty ? "Ohne Kürzel" : "Kürzel \(e.kuerzel)", e.vertretung ? "Vertretungsplan" : nil, e.mensa ? "Mensa" : nil, e.obst ? "Schulobst" : nil,
                e.untisAn ? "WebUntis" : nil, e.abwesenheiten ? "Abwesenheiten" : nil, e.stoerungen ? "Störungen" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func laden() async {
        laedt = true; meldung = ""
        defer { laedt = false }
        do {
            let v = try await SchulVorgaben.laden(code: code)
            var e = kern.einstellungen
            let g = v.anwenden(&e)
            kern.einstellungen = e
            if !g.freigabe.isEmpty { kern.freigabePasswort = g.freigabe }
            if !g.schulOrdner.isEmpty { kern.schulOrdnerPasswort = g.schulOrdner }
            geladen = true; meldung = "Vertretungsplan, Mensa-Portal, Schulobst, Untis und IServ der Schule sind eingetragen."
        } catch {
            geladen = false; meldung = error.localizedDescription
        }
    }

    private func weiter() {
        if schritt == .fertig { beenden(); return }
        withAnimation { schritt = Schritt(rawValue: schritt.rawValue + 1)! }
        // Schul-Code schon bekannt (Bestandsinstallation): gleich freischalten
        if schritt == .schule, schulDaten, !geladen, !code.isEmpty { Task { await laden() } }
    }

    private func beenden() {
        UserDefaults.standard.set(true, forKey: Self.fertigSchluessel)
        kern.assistentOffen = false
        Task { await kern.aktualisieren() }
    }
}
