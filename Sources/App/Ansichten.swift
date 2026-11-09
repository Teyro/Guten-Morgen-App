import SwiftUI
import UniformTypeIdentifiers
import MorgenKern

struct HauptAnsicht: View {
    @Bindable var kern: Kern
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    kopf
                    WeckerKarte(kern: kern)
                    if let w = kern.wetter { WetterKarte(wetter: w) }
                    if kern.einstellungen.termine { TermineKarte(termine: kern.termine.filter { Zeit.kalender.isDateInToday($0.start) }, erinnerungen: kern.erinnerungen) }
                    if !kern.post.isEmpty { Karte(symbol: "shippingbox.fill", farbe: .blue, titel: "Post & Pakete") { Text(kern.post) } }
                    if kern.einstellungen.vertretung, kern.vertretung != nil || !kern.vertretungFehler.isEmpty { VertretungKarte(plan: kern.vertretung, fehler: kern.vertretungFehler) }
                    knoepfe
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Hintergrund())
            .refreshable { await kern.aktualisieren() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { kern.einstellungenOffen = true } label: { Label("Einstellungen", systemImage: "gearshape") }
                }
            }
            .sheet(isPresented: $kern.einstellungenOffen) { NavigationStack { EinstellungenAnsicht(kern: kern) } }
            .fullScreenCover(isPresented: $kern.nachtOffen) { NachtAnsicht(kern: kern, musik: kern.musik) }
            .overlay(alignment: .bottom) {
                if !kern.meldung.isEmpty {
                    Text(kern.meldung).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 20)
                        .task(id: kern.meldung) { try? await Task.sleep(nanoseconds: 3_500_000_000); kern.meldung = "" }
                }
            }
        }
        .task { await kern.aktualisieren() }
        .onChange(of: phase) { _, neu in if neu == .active { Task { await kern.aktualisieren() } } }
    }

    private var kopf: some View {
        let jetzt = Date()
        let h = Zeit.kalender.component(.hour, from: jetzt)
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM"
        return VStack(alignment: .leading, spacing: 4) {
            Text(h < 11 ? "Guten Morgen" : h < 18 ? "Hallo" : "Guten Abend").font(.largeTitle.weight(.bold))
            HStack(spacing: 6) {
                Text(f.string(from: jetzt))
                if let frei = kern.freiHeute { Text("· \(frei.name)").foregroundStyle(.orange) }
                if kern.laedt { ProgressView().controlSize(.small) }
            }
            .font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var knoepfe: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { Task { await kern.briefingVorlesen() } } label: { GrosserKnopf(symbol: "sun.max.fill", titel: "Vorlesen", farbe: .orange) }
                Button { Task { await kern.guteNacht() } } label: { GrosserKnopf(symbol: "moon.stars.fill", titel: "Gute Nacht", farbe: .indigo) }
            }
            Button { Task { await kern.nachtVorbereiten(); kern.nachtOffen = true } } label: {
                Label(kern.musik.quelle == .aus ? "Nachtmodus" : "Nachtmodus · \(kern.musik.titel)", systemImage: "bed.double.fill")
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.3).gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

struct Hintergrund: View {
    @Environment(\.colorScheme) private var schema
    var body: some View {
        LinearGradient(colors: schema == .dark ? [Color(red: 0.07, green: 0.08, blue: 0.16), Color(red: 0.12, green: 0.1, blue: 0.2)]
                                               : [Color(red: 1, green: 0.95, blue: 0.88), Color(red: 0.93, green: 0.95, blue: 1)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct Karte<Inhalt: View>: View {
    let symbol: String
    let farbe: Color
    let titel: String
    @ViewBuilder var inhalt: Inhalt
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(titel, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(farbe)
            inhalt
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct GrosserKnopf: View {
    let symbol: String
    let titel: String
    let farbe: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
            Text(titel).font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(farbe.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct WeckerKarte: View {
    let kern: Kern
    var body: some View {
        let w = kern.naechsterWecker
        Karte(symbol: "alarm.fill", farbe: .orange, titel: Zeit.kalender.isDateInToday(w.tag) ? "Wecker heute" : "Wecker \(Zeit.wochentag(w.tag))") {
            HStack(alignment: .firstTextBaseline) {
                Text(w.minuten.map(Zeit.hhmm) ?? "frei").font(.system(size: 52, weight: .bold, design: .rounded))
                Spacer()
                if Wecker.verfuegbar {
                    Button(w.minuten == nil ? "Kein Wecker" : "Stellen") { Task { await kern.weckerStellen() } }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
            if !w.grund.isEmpty { Text(w.grund).font(.callout).foregroundStyle(.secondary) }
            if !kern.weckerText.isEmpty { Text(kern.weckerText).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct WetterKarte: View {
    let wetter: Wetter
    var body: some View {
        Karte(symbol: "cloud.sun.fill", farbe: .teal, titel: "Wetter") {
            HStack(spacing: 14) {
                Image(systemName: Wetter.symbol(wetter.jetztCode ?? wetter.heute?.code ?? 3)).symbolRenderingMode(.multicolor).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    if let j = wetter.jetzt { Text("\(Int(j.rounded()))°").font(.system(size: 34, weight: .bold, design: .rounded)) }
                    if let t = wetter.heute {
                        Text("\(Int(t.min.rounded()))° bis \(Int(t.max.rounded()))° · Regen \(t.regen) %").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Text(wetter.satz()).font(.callout)
        }
    }
}

struct TermineKarte: View {
    let termine: [Termin]
    let erinnerungen: [String]
    var body: some View {
        Karte(symbol: "calendar", farbe: .red, titel: "Heute") {
            if termine.isEmpty && erinnerungen.isEmpty { Text("Keine Termine.").foregroundStyle(.secondary) }
            ForEach(termine.sorted { $0.start < $1.start }, id: \.self) { t in
                HStack {
                    Text(t.ganztags ? "ganztägig" : t.start.uhrzeit).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
                    Text(t.titel)
                }
            }
            ForEach(erinnerungen, id: \.self) { e in Label(e, systemImage: "checklist").font(.callout) }
        }
    }
}

struct VertretungKarte: View {
    let plan: VertretungsPlan?
    let fehler: String
    var body: some View {
        Karte(symbol: "person.2.fill", farbe: .purple, titel: "Vertretung") {
            if let p = plan {
                if p.fehlt { Text("Du bist als fehlend eingetragen").foregroundStyle(.red) }
                if p.stunden.isEmpty && p.pausen.isEmpty { Text("Keine Vertretung für dich.") }
                ForEach(p.stunden, id: \.self) { s in Text("\(Int(s.stunde) != nil ? "\(s.stunde). Stunde" : s.stunde) · \(s.klasse)").font(.body.weight(.semibold)) }
                ForEach(p.pausen, id: \.self) { s in Label("\(s.pause): \(s.ort)", systemImage: "figure.walk") }
                if !p.datei.isEmpty { Text(p.datei.replacingOccurrences(of: ".docx", with: "")).font(.caption).foregroundStyle(.secondary) }
            } else { Text(fehler).foregroundStyle(.secondary) }
        }
    }
}

struct EinstellungenAnsicht: View {
    @Bindable var kern: Kern
    @Environment(\.dismiss) private var schliessen
    private let tage = [(2, "Montag"), (3, "Dienstag"), (4, "Mittwoch"), (5, "Donnerstag"), (6, "Freitag"), (7, "Samstag"), (1, "Sonntag")]

    var body: some View {
        @Bindable var k = kern
        Form {
            Section {
                ForEach(tage, id: \.0) { t in
                    HStack {
                        Text(t.1)
                        Spacer()
                        TextField("aus", text: Binding(get: { kern.einstellungen.weckzeiten[t.0] ?? "" }, set: { kern.einstellungen.weckzeiten[t.0] = $0 }))
                            .multilineTextAlignment(.trailing).frame(width: 80).keyboardType(.numbersAndPunctuation)
                    }
                }
                Stepper("Vor dem ersten Termin: \(kern.einstellungen.vorlauf) min", value: $k.einstellungen.vorlauf, in: 15...180, step: 5)
                HStack { Text("Frühestens"); Spacer(); TextField("05:00", text: $k.einstellungen.fruehestens).multilineTextAlignment(.trailing).frame(width: 80) }
                Toggle("In den Ferien kein Wecker", isOn: $k.einstellungen.ferienFrei)
                Toggle("An Feiertagen kein Wecker", isOn: $k.einstellungen.feiertagFrei)
                Toggle("Wecker automatisch stellen", isOn: $k.einstellungen.weckerAutomatisch)
                Picker("Bundesland", selection: $k.einstellungen.bundesland) {
                    ForEach(["BW", "BY", "BE", "BB", "HB", "HH", "HE", "MV", "NI", "NW", "RP", "SL", "SN", "ST", "SH", "TH"], id: \.self) { Text($0) }
                }
            } header: { Text("Wecker") } footer: { Text("Uhrzeit je Tag (z. B. 06:15), leer = kein Wecker. Steht früh ein Termin im Kalender, weckt die App rechtzeitig vorher.") }

            Section("Wetter") {
                TextField("Ort", text: $k.einstellungen.ortName)
                HStack {
                    TextField("Breite", value: $k.einstellungen.lat, format: .number.precision(.fractionLength(4))).keyboardType(.decimalPad)
                    TextField("Länge", value: $k.einstellungen.lon, format: .number.precision(.fractionLength(4))).keyboardType(.decimalPad)
                }
            }

            Section {
                TextField("https://homeassistant.local:8123", text: $k.einstellungen.haAdresse).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Langlebiges Zugriffstoken", text: $k.token)
                Toggle("Post und Pakete vorlesen", isOn: $k.einstellungen.post)
                ForEach($k.einstellungen.nacht) { $a in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $a.name)
                        HStack { TextField("light.turn_off", text: $a.dienst); TextField("all", text: $a.ziel) }.font(.caption).textInputAutocapitalization(.never)
                    }
                }
                .onDelete { k.einstellungen.nacht.remove(atOffsets: $0) }
                Button("Aktion für „Gute Nacht“ hinzufügen") { k.einstellungen.nacht.append(HAAktion(name: "Neue Aktion", dienst: "light.turn_off", ziel: "all")) }
            } header: { Text("Home Assistant") } footer: { Text("Token: in Home Assistant unten links auf deinen Namen → Sicherheit → Langlebige Zugriffstoken. Post kommt aus der Integration „Briefankündigung“.") }

            Section {
                Toggle("Vertretung vorlesen", isOn: $k.einstellungen.vertretung)
                TextField("Freigabe-Link (https://…/s/…)", text: $k.einstellungen.vertretungLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Kürzel, z. B. Sta", text: $k.einstellungen.kuerzel).textInputAutocapitalization(.never)
            } header: { Text("Schule") } footer: { Text("Cloud-Ordner mit dem Vertretungsplan (Word-Dateien). Gelesen wird nur, was für dein Kürzel drinsteht.") }

            WeckmusikAbschnitt(musik: kern.musik)

            Section("Kalender") {
                Toggle("Termine", isOn: $k.einstellungen.termine)
                Toggle("Erinnerungen", isOn: $k.einstellungen.erinnerungen)
            }

            Section {
                Button("Widget verbinden") { Task { await kern.widgetUebergeben(erzwingen: true) } }
            } header: { Text("Widget") } footer: { Text("Gibt dem Widget Einstellungen und Zugang (kurz erscheint eine Live-Aktivität). Passiert beim Öffnen der App auch von selbst.") }

            Section("Über") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("Guten Morgen auf GitHub", destination: URL(string: "https://github.com/Teyro/Guten-Morgen-App")!)
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen(); Task { await kern.aktualisieren() } } } }
    }
}

struct WeckmusikAbschnitt: View {
    @Bindable var musik: Weckmusik
    @State private var mediathek = false
    @State private var datei = false

    var body: some View {
        Section {
            Picker("Weckmusik", selection: $musik.quelle) {
                Text("Weckton").tag(Weckmusik.Quelle.aus)
                Text("Apple Music").tag(Weckmusik.Quelle.apple)
                Text("Eigene Datei").tag(Weckmusik.Quelle.datei)
            }
            if musik.quelle != .aus && !musik.titel.isEmpty { LabeledContent("Titel", value: musik.titel) }
            Button("Titel aus der Mediathek wählen …") { mediathek = true }
            Button("Musikdatei wählen …") { datei = true }
            Stepper("Einblenden: \(musik.einblendenSek) s", value: $musik.einblendenSek, in: 10...300, step: 10)
            HStack { Image(systemName: "speaker.fill"); Slider(value: $musik.zielLautstaerke, in: 0.2...1); Image(systemName: "speaker.wave.3.fill") }
        } header: { Text("Weckmusik (Nachtmodus)") } footer: {
            Text("Im Nachtmodus bleibt die App auf dem Nachttisch offen (am besten am Ladekabel) und spielt zur Weckzeit die Musik – leise beginnend. Der normale Wecker klingelt zur Sicherheit 5 Minuten später. Spotify lässt sich von anderen Apps nicht starten: dafür in der Kurzbefehle-App eine Automation „Wecker → Wenn er klingelt“ mit „Spotify: Abspielen“ anlegen.")
        }
        .sheet(isPresented: $mediathek) { MediathekWahl { musik.appleGewaehlt($0) }.ignoresSafeArea() }
        .fileImporter(isPresented: $datei, allowedContentTypes: [.audio]) { erg in
            if case .success(let url) = erg { _ = musik.dateiGewaehlt(url) }
        }
    }
}
