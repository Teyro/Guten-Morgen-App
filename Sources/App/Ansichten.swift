import SwiftUI
import UniformTypeIdentifiers
import MorgenKern

struct HauptAnsicht: View {
    @Bindable var kern: Kern
    @Environment(\.scenePhase) private var phase
    @State private var pfad: [Bereich] = []
    @State private var code = ""

    var body: some View {
        NavigationStack(path: $pfad) {
            ScrollView {
                VStack(spacing: 14) {
                    kopf
                    WeckerKarte(kern: kern)
                    // In der Schule: Schule zuerst; zu Hause und am Wochenende: Termine und Post zuerst
                    if kern.kontext == .schule {
                        if zeigeSchule { SchuleKarte(kern: kern) { pfad = [$0] } }
                        if let w = kern.wetter { WetterKarte(wetter: w) }
                        termineUndPost
                    } else {
                        termineUndPost
                        if let w = kern.wetter { WetterKarte(wetter: w) }
                        if zeigeSchule { SchuleKarte(kern: kern) { pfad = [$0] } }
                    }
                    knoepfe
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Hintergrund(farbton: kern.farbton))
            .tint(kern.farbton.akzent)
            .refreshable { await kern.aktualisieren() }
            .toolbar {
                // Menü (drei Striche): alle Bereiche als eigene Seiten
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { pfad = [.stundenplan] } label: { Label("Stundenplan", systemImage: "calendar.day.timeline.left") }
                        Button { pfad = [.vertretung] } label: { Label("Vertretung", systemImage: "arrow.triangle.swap") }
                        Button { pfad = [.mensa] } label: { Label("Speiseplan", systemImage: "fork.knife") }
                        Button { pfad = [.post] } label: { Label("Post & Pakete", systemImage: "shippingbox.fill") }
                        Divider()
                        Button { pfad = [.stoerungen] } label: { Label("Störungen", systemImage: "wrench.and.screwdriver.fill") }
                        Button { pfad = [.aufgaben] } label: { Label("Aufgaben", systemImage: "checklist") }
                        Button { pfad = [.abwesend] } label: { Label("Abwesenheiten", systemImage: "person.crop.circle.badge.xmark") }
                        Divider()
                        Button { kern.einstellungenOffen = true } label: { Label("Einstellungen", systemImage: "gearshape") }
                    } label: { Label("Menü", systemImage: "line.3.horizontal") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { kern.einstellungenOffen = true } label: { Label("Einstellungen", systemImage: "gearshape") }
                }
            }
            .navigationDestination(for: Bereich.self) { b in
                switch b {
                case .stundenplan: StundenplanWoche(kern: kern)
                case .post: PostAnsicht(kern: kern)
                case .mensa: MensaAnsicht(kern: kern)
                case .abwesend: AbwesendAnsicht(kern: kern)
                case .stoerungen: StoerungenAnsicht(kern: kern)
                case .aufgaben: AufgabenAnsicht(kern: kern)
                default: VertretungAnsicht(kern: kern)
                }
            }
            .sheet(isPresented: $kern.einstellungenOffen) { NavigationStack { EinstellungenAnsicht(kern: kern) } }
            .alert("Aus Mein Tag übernehmen?", isPresented: Binding(get: { kern.importAnfrage != nil }, set: { if !$0 { kern.importAnfrage = nil } })) {
                Button("Übernehmen") { if let i = kern.importAnfrage { kern.importAnfrage = nil; Task { await kern.importieren(i) } } }
                Button("Abbrechen", role: .cancel) { kern.importAnfrage = nil }
            } message: { Text((kern.importAnfrage?.zusammenfassung ?? []).joined(separator: ", ") + ". Vorhandene Einstellungen werden ersetzt.") }
            .alert("Zwei-Faktor-Code", isPresented: Binding(get: { kern.codeHinweis != nil }, set: { if !$0 && kern.codeHinweis != nil { kern.codeEingegeben(nil) } })) {
                TextField("123456", text: $code).keyboardType(.numberPad)
                Button("Anmelden") { kern.codeEingegeben(code); code = "" }
                Button("Abbrechen", role: .cancel) { kern.codeEingegeben(nil); code = "" }
            } message: { Text(kern.codeHinweis ?? "") }
            .alert("Anmeldung über \(kern.hostFrage ?? "")?", isPresented: Binding(get: { kern.hostFrage != nil }, set: { if !$0 { kern.hostFrage = nil } })) {
                Button("Ja, erlauben") { if let h = kern.hostFrage { Task { await kern.hostErlauben(h) } } }
                Button("Abbrechen", role: .cancel) { kern.hostFrage = nil }
            } message: { Text("IServ schickt die Anmeldung weiter an \(kern.hostFrage ?? ""). Nur bestätigen, wenn das eure bekannte Anmeldeseite ist (z. B. Schuldock).") }
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
        // Sprung aus dem Widget: Speiseplan oder Vertretung gleich öffnen
        .onChange(of: kern.bereich) { _, b in
            guard let b else { return }
            if [.mensa, .vertretung, .abwesend, .stoerungen, .aufgaben, .stundenplan, .post].contains(b) { pfad = [b] } else { pfad = [] }
            kern.bereich = nil
        }
        .onChange(of: phase) { _, neu in if neu == .active { Task { await kern.aktualisieren() } } }
    }

    @ViewBuilder private var termineUndPost: some View {
        if kern.einstellungen.termine {
            // zu Hause und am Wochenende auch die nächsten Tage
            let k = Zeit.kalender
            let bis = k.date(byAdding: .day, value: kern.kontext == .schule ? 1 : 3, to: k.startOfDay(for: Date())) ?? Date()
            TermineKarte(termine: kern.termine.filter { $0.start < bis && ($0.ganztags || $0.start > Date().addingTimeInterval(-1800)) },
                         erinnerungen: kern.erinnerungen, mehrereTage: kern.kontext != .schule)
        }
        if !kern.post.isEmpty { Karte(symbol: "shippingbox.fill", farbe: .blue, titel: "Post & Pakete") { Text(kern.post) } }
    }

    /// Schul-Karte nur, wenn etwas davon eingerichtet ist
    private var zeigeSchule: Bool {
        let e = kern.einstellungen
        return (e.vertretung && !e.vertretungLink.isEmpty) || e.mensa || e.obstBereit || e.abwesenheiten || e.stoerungen || e.aufgaben
    }

    private var kopf: some View {
        let jetzt = Date()
        let h = Zeit.kalender.component(.hour, from: jetzt)
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM"
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(h < 11 ? "Guten Morgen" : h < 18 ? "Hallo" : "Guten Abend").font(.system(.largeTitle, design: .rounded).weight(.bold))
                HStack(spacing: 6) {
                    Text(f.string(from: jetzt))
                    if let frei = kern.freiHeute { Text("· \(frei.name)").foregroundStyle(kern.farbton.akzent) }
                    if kern.laedt { ProgressView().controlSize(.small) }
                }
                .font(.headline).foregroundStyle(.secondary)
            }
            Spacer()
            if let w = kern.wetter {
                VStack(spacing: 0) {
                    Image(systemName: Wetter.symbol(w.jetztCode ?? w.heute?.code ?? 3)).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    if let j = w.jetzt { Text("\(Int(j.rounded()))°").font(.system(.title2, design: .rounded).weight(.semibold)) }
                }
            }
        }
        .padding(.top, 8)
    }

    private var knoepfe: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { Task { await kern.briefingVorlesen() } } label: { GrosserKnopf(symbol: "sun.max.fill", titel: "Vorlesen", farbe: .orange) }
                Button { Task { await kern.guteNacht() } } label: { GrosserKnopf(symbol: "moon.stars.fill", titel: "Gute Nacht", farbe: .indigo) }
            }
            Button { Task { await kern.nachtVorbereiten(); kern.nachtOffen = true } } label: {
                Label(kern.musik.quelle == .aus ? "Nachtmodus" : "Nachtmodus · \(kern.musik.anzeige)", systemImage: "bed.double.fill")
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                    .glasKnopf(Color(red: 0.2, green: 0.2, blue: 0.42), 16)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

struct Hintergrund: View {
    var farbton: Farbton = Farbton.alle[0]
    @Environment(\.colorScheme) private var schema
    var body: some View {
        LinearGradient(colors: schema == .dark ? farbton.dunkel : farbton.hell, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct Karte<Inhalt: View>: View {
    let symbol: String
    let farbe: Color
    let titel: String
    @ViewBuilder var inhalt: Inhalt
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(farbe.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(titel).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            inhalt
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glas(22)
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
        .glasKnopf(farbe)
    }
}

struct WeckerKarte: View {
    let kern: Kern
    var body: some View {
        let w = kern.naechsterWecker
        Karte(symbol: "alarm.fill", farbe: kern.farbton.akzent, titel: Zeit.kalender.isDateInToday(w.tag) ? "Wecker heute" : "Wecker \(Zeit.wochentag(w.tag))") {
            HStack(alignment: .firstTextBaseline) {
                Text(w.minuten.map(Zeit.hhmm) ?? "frei").font(.system(size: 52, weight: .bold, design: .rounded))
                Spacer()
                if Wecker.verfuegbar {
                    Button(w.minuten == nil ? "Kein Wecker" : "Stellen") { Task { await kern.weckerStellen() } }
                        .buttonStyle(.borderedProminent).tint(kern.farbton.akzent)
                }
            }
            if !w.grund.isEmpty { Text(w.grund).font(.callout).foregroundStyle(.secondary) }
            if let s = kern.schlaf { Label("Geschlafen: \(Gesundheit.text(s))", systemImage: "bed.double.fill").font(.callout).foregroundStyle(.secondary) }
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
    var mehrereTage = false
    var body: some View {
        Karte(symbol: "calendar", farbe: .red, titel: mehrereTage ? "Termine" : "Heute") {
            if termine.isEmpty && erinnerungen.isEmpty { Text("Keine Termine.").foregroundStyle(.secondary) }
            ForEach(termine.sorted { $0.start < $1.start }, id: \.self) { t in
                HStack {
                    Text(t.ganztags ? "ganztägig" : t.start.uhrzeit).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
                    Text(t.titel)
                    Spacer(minLength: 0)
                    if mehrereTage && !Zeit.kalender.isDateInToday(t.start) { Text(Tagwahl.name(t.start)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(erinnerungen, id: \.self) { e in Label(e, systemImage: "checklist").font(.callout) }
        }
    }
}

/// Alles zur Schule heute: wo muss ich rein, Aufsicht, Schulobst, Mensa – wie die Übersicht in Mein Tag
struct SchuleKarte: View {
    let kern: Kern
    let oeffne: (Bereich) -> Void
    @Environment(\.openURL) private var oeffneURL

    var body: some View {
        let e = kern.einstellungen
        Karte(symbol: "graduationcap.fill", farbe: .purple, titel: "Schule " + kern.schulTagName) {
            if !kern.anfahrtText.isEmpty {
                Label(kern.anfahrtText, systemImage: e.fahrtArt == "oepnv" ? "tram.fill" : e.fahrtArt == "fuss" ? "figure.walk" : "car.fill").font(.callout.weight(.medium))
            }
            // eigene Stunden (Vertretungen und Aufsichten stehen darunter beim Vertretungsplan)
            ForEach(kern.schultag.filter { $0.art == .unterricht }, id: \.von) { b in
                Zeile(marke: b.marke, farbe: .blue, titel: b.text, unter: Zeit.uhrzeit(b.von) + "–" + Zeit.uhrzeit(b.bis))
            }
            if e.vertretung && !e.vertretungLink.isEmpty {
                Button { oeffne(.vertretung) } label: { VStack(alignment: .leading, spacing: 8) { vertretung(e) } }.buttonStyle(.plain)
            }
            if e.obstBereit && kern.obstHeute {
                Zeile(marke: "🍎", farbe: .green, titel: kern.schulTagName == "heute" ? "Heute kommt Schulobst" : "Schulobst kommt", unter: nil)
            }
            if e.mensa {
                Button { oeffne(.mensa) } label: { mensa(e) }.buttonStyle(.plain)
            }
            // Kinder, Störungen, Aufgaben: Zahlen-Kacheln, antippen öffnet die Liste
            let kacheln: [(Bereich, String, String, String, Color)] = [
                e.abwesenheiten ? (.abwesend, "person.crop.circle.badge.xmark", kern.abwesend.map { "\(Abwesenheiten.amTag($0.eintraege, ziel: kern.schulTag, klassen: e.klassenListe).count)" } ?? (kern.abwesendFehler.isEmpty ? "…" : "!"), "Kinder fehlen", Color.red) : nil,
                e.stoerungen ? (.stoerungen, "wrench.and.screwdriver.fill", kern.stoerungen.map { "\($0.offen.count)" } ?? (kern.stoerungenFehler.isEmpty ? "…" : "!"), "Störungen", Color.orange) : nil,
                e.aufgaben ? (.aufgaben, "checklist", kern.aufgaben.map { "\($0.offen.count)" } ?? (kern.aufgabenFehler.isEmpty ? "…" : "!"), "Aufgaben", Color.teal) : nil,
            ].compactMap { $0 }
            if !kacheln.isEmpty {
                HStack(spacing: 8) {
                    ForEach(kacheln, id: \.0) { k in
                        Button { oeffne(k.0) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) { Image(systemName: k.1).foregroundStyle(k.4); Text(k.2).font(.title3.weight(.bold).monospacedDigit()) }
                                Text(k.3).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10).glas(14)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private func vertretung(_ e: MorgenEinstellungen) -> some View {
                if let p = kern.vertretung {
                    if p.fehlt { Hinweis(text: "Du bist als fehlend eingetragen", farbe: .red) }
                    if p.ausserHaus { Hinweis(text: "Du bist außer Haus eingetragen", farbe: .orange) }
                    if p.stunden.isEmpty && p.pausen.isEmpty && !p.fehlt {
                        Label("Keine Vertretung für dich", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.body.weight(.medium))
                    }
                    ForEach(p.stunden, id: \.self) { s in
                        let haus = Vertretung.haus(s.klasse, e.haeuser)
                        Zeile(marke: Int(s.stunde) != nil ? "\(s.stunde)." : String(s.stunde.prefix(4)), farbe: .purple,
                              titel: "Vertretung \(s.klasse)", unter: haus.isEmpty ? (Int(s.stunde) != nil ? "\(s.stunde). Stunde" : s.stunde) : "\(Int(s.stunde) != nil ? "\(s.stunde). Stunde" : s.stunde) · \(haus)")
                    }
                    ForEach(p.pausen, id: \.self) { a in
                        Zeile(marke: String(a.pause.prefix(1)) + ". P", farbe: .orange,
                              titel: a.reserve ? "Aufsicht (Reserve)" : "Hofaufsicht", unter: "\(a.pause) · \(a.ort)")
                    }
                    ForEach(p.hinweise, id: \.self) { h in Label(h, systemImage: "exclamationmark.bubble.fill").font(.callout).foregroundStyle(.secondary) }
                    if !p.fehlen.isEmpty { Text("Es fehlen: " + p.fehlen.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                } else if !kern.vertretungFehler.isEmpty {
                    Label(kern.vertretungFehler, systemImage: "wifi.exclamationmark").font(.callout).foregroundStyle(.secondary)
                }
    }

    @ViewBuilder private func mensa(_ e: MorgenEinstellungen) -> some View {
        if let m = kern.mensa {
            if let f = m.frei {
                Zeile(marke: "🍽", farbe: .gray, titel: "Mensa geschlossen", unter: f.isEmpty ? nil : f)
            } else if let h = m.haupt(favoriten: e.favoriten, meiden: e.meiden, gut: e.lieblingsGerichte, schlecht: e.nichtLecker) {
                Zeile(marke: "🍽", farbe: .teal, titel: h.text, unter: (h.bestellt ? "Bestellt · " : "") + h.menue + " · Speiseplan ›")
            }
        } else if !kern.mensaFehler.isEmpty {
            Zeile(marke: "🍽", farbe: .gray, titel: "Speiseplan", unter: kern.mensaFehler)
        }
    }
}

/// Eine Zeile mit farbiger Marke links („2.“, „1. P“, 🍎)
struct Zeile: View {
    let marke: String
    let farbe: Color
    let titel: String
    let unter: String?
    var body: some View {
        HStack(spacing: 12) {
            Text(marke).font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(farbe)
                .frame(width: 40, height: 40).background(farbe.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(titel).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                if let u = unter { Text(u).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct Hinweis: View {
    let text: String
    let farbe: Color
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout.weight(.semibold)).foregroundStyle(farbe)
    }
}

struct EinstellungenAnsicht: View {
    @Bindable var kern: Kern
    @Environment(\.dismiss) private var schliessen
    @State private var haeuserText = ""
    @State private var scannen = false
    @Environment(\.openURL) private var oeffneURL
    private let tage = [(2, "Montag"), (3, "Dienstag"), (4, "Mittwoch"), (5, "Donnerstag"), (6, "Freitag"), (7, "Samstag"), (1, "Sonntag")]

    var body: some View {
        @Bindable var k = kern
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Farbton.alle) { f in
                            Button { k.einstellungen.farbton = f.id } label: {
                                VStack(spacing: 6) {
                                    LinearGradient(colors: f.widget, startPoint: .top, endPoint: .bottom)
                                        .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(f.id == kern.einstellungen.farbton ? Color.primary : .clear, lineWidth: 3))
                                        .overlay { if f.id == kern.einstellungen.farbton { Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white) } }
                                    Text(f.name).font(.caption).foregroundStyle(.primary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 6)
                }
            } header: { Text("Aussehen") } footer: { Text("Farbton für App und Widget.") }

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
                Stepper(kern.einstellungen.glaetteFrueher == 0 ? "Bei Glätte/Schnee: nicht früher" : "Bei Glätte/Schnee: \(kern.einstellungen.glaetteFrueher) min früher",
                        value: $k.einstellungen.glaetteFrueher, in: 0...60, step: 5)
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
                Toggle("Vertretungsplan", isOn: $k.einstellungen.vertretung)
                TextField("Freigabe-Link (https://…/s/…)", text: $k.einstellungen.vertretungLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Freigabe-Passwort (falls gesetzt)", text: $k.freigabePasswort)
                TextField("Kürzel, z. B. Sta", text: $k.einstellungen.kuerzel).textInputAutocapitalization(.never)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Häuser der Klassen").font(.subheadline)
                    TextEditor(text: $haeuserText).frame(minHeight: 80).font(.callout.monospaced()).textInputAutocapitalization(.never)
                        .onChange(of: haeuserText) { _, neu in k.einstellungen.haeuser = Vertretung.haeuser(text: neu) }
                }
            } header: { Text("Vertretung") } footer: { Text("Cloud-Ordner mit dem Vertretungsplan (Word-Dateien). Gelesen wird nur, was für dein Kürzel drinsteht – Stunden, Hofaufsicht und Hinweise. Häuser je Zeile, z. B. „Haus 1: 1a, 1b, 2a“: dann steht dabei, wohin du musst.") }

            Section {
                NavigationLink {
                    StundenplanAnsicht(kern: kern)
                } label: {
                    LabeledContent("Mein Stundenplan", value: kern.einstellungen.unterricht.isEmpty ? "leer" : "\(kern.einstellungen.unterricht.count) Stunden")
                }
                Toggle("5 Minuten vor einer Hofaufsicht erinnern", isOn: $k.einstellungen.aufsichtErinnern)
                Toggle("Live-Aktivität im Schulalltag", isOn: $k.einstellungen.schulAktivitaet)
            } header: { Text("Schultag") } footer: { Text("Deine Stunden stehen im Briefing, im Widget „Schultag“ und – als Live-Aktivität – auf dem Sperrbildschirm, in der Dynamic Island und auf der Apple Watch: was gerade läuft, wie lange noch, was danach kommt. Vertretungen und Aufsichten aus dem Vertretungsplan kommen von selbst dazu.") }

            Section {
                Toggle("WebUntis verbinden", isOn: $k.einstellungen.untisAn)
                if kern.einstellungen.untisAn {
                    if QRScanner.verfuegbar { Button { scannen = true } label: { Label("QR-Code „Untis Mobile“ scannen", systemImage: "qrcode.viewfinder") } }
                    TextField("Adresse der Anmeldeseite oder untis://…", text: $k.einstellungen.untisLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Benutzername", text: $k.einstellungen.untisBenutzer).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Schlüssel aus „Untis Mobile“ (bei zweitem Faktor)", text: $k.untisSchluessel)
                    SecureField("Passwort (nur ohne zweiten Faktor)", text: $k.untisPasswort)
                    Toggle("Als „Mein Stundenplan“ übernehmen", isOn: $k.einstellungen.untisUebernehmen)
                    Button("Jetzt laden") { Task { await kern.untisLaden(erzwingen: true); kern.meldung = kern.untisFehler.isEmpty ? "Stundenplan aus WebUntis geladen" : kern.untisFehler } }
                    if !kern.untisFehler.isEmpty { Text(kern.untisFehler).font(.footnote).foregroundStyle(.orange) }
                }
            } header: { Text("WebUntis") } footer: { Text("Mit zweitem Faktor: in WebUntis am Computer auf deinen Namen → Freigaben → „Untis Mobile“ → Anzeigen. Den QR-Code hier scannen – dann meldet sich die App wie die Untis-App an und braucht dein Passwort nicht. Ohne zweiten Faktor reichen Adresse, Benutzer und Passwort. Geladen werden deine Stunden und die Pläne deiner Klassen (für „wer ist noch in der Klasse“).") }
            .sheet(isPresented: $scannen) {
                QRScanner { text in
                    scannen = false
                    if let q = Untis.qr(text) {
                        k.einstellungen.untisLink = text.components(separatedBy: "&key=").first ?? text
                        k.einstellungen.untisBenutzer = q.benutzer
                        k.untisSchluessel = q.schluessel
                        k.einstellungen.untisAn = true
                        Task { await kern.untisLaden(erzwingen: true); kern.meldung = kern.untisFehler.isEmpty ? "WebUntis verbunden" : kern.untisFehler }
                    } else { kern.meldung = "Das ist kein „Untis Mobile“-QR-Code." }
                }
                .ignoresSafeArea()
            }

            Section {
                Toggle("Unterwegs anders schlafen gehen", isOn: $k.einstellungen.unterwegsAn)
                if kern.einstellungen.unterwegsAn {
                    Stepper("Unterwegs ab \(kern.einstellungen.zuhauseRadius) m von Zuhause", value: $k.einstellungen.zuhauseRadius, in: 300...20000, step: 100)
                    ForEach($k.einstellungen.unterwegsAktionen) { $a in
                        VStack(alignment: .leading) {
                            TextField("Name", text: $a.name)
                            HStack { TextField("script.turn_on", text: $a.dienst); TextField("script.urlaubsmodus", text: $a.ziel) }.font(.caption).textInputAutocapitalization(.never)
                        }
                    }
                    .onDelete { k.einstellungen.unterwegsAktionen.remove(atOffsets: $0) }
                    Button("Aktion für unterwegs hinzufügen") { k.einstellungen.unterwegsAktionen.append(HAAktion(name: "Urlaubsmodus", dienst: "script.turn_on", ziel: "")) }
                    if kern.einstellungen.zuhauseOrt == nil { Text("Bitte unten bei „Orte“ Zuhause speichern.").font(.footnote).foregroundStyle(.orange) }
                    if kern.unterwegs { Label("Gerade unterwegs", systemImage: "car.fill").foregroundStyle(.orange) }
                }
            } header: { Text("Unterwegs") } footer: { Text("Bist du weiter als die eingestellte Entfernung von Zuhause weg (z. B. bei Verwandten), macht „Gute Nacht“ nicht „Alle Lichter aus“, sondern startet diese Aktionen – etwa deine Urlaubs-Automation. Die Morgenroutine zu Hause läuft dann nicht. Der Wecker klingelt wie immer.") }

            Section {
                Toggle("Fahrzeit berücksichtigen", isOn: $k.einstellungen.fahrt)
                if kern.einstellungen.fahrt {
                    Picker("Unterwegs", selection: $k.einstellungen.fahrtArt) {
                        Text("Auto").tag("auto"); Text("Bus und Bahn").tag("oepnv"); Text("zu Fuß").tag("fuss")
                    }
                    Stepper("Fertigmachen: \(kern.einstellungen.fertig) min", value: $k.einstellungen.fertig, in: 10...120, step: 5)
                    Stepper("Vor der ersten Stunde da: \(kern.einstellungen.puffer) min", value: $k.einstellungen.puffer, in: 0...60, step: 5)
                    if kern.einstellungen.schulOrt == nil { Text("Bitte unten bei „Orte“ die Schule speichern.").font(.footnote).foregroundStyle(.orange) }
                    if let f = kern.fahrt { LabeledContent("Zuletzt berechnet", value: "\(f.minuten) min") }
                }
            } header: { Text("Anfahrt") } footer: { Text("Rechnet über Apple Karten, wie lange du zur ersten Stunde brauchst (Auto mit Verkehrsprognose, Bus und Bahn nach Fahrplan). Wird es mit der normalen Weckzeit knapp, klingelt der Wecker früher; morgens sagt das Briefing, wann du losfahren musst. Start ist „Zuhause“ (sonst der aktuelle Ort).") }

            Section {
                ForEach($k.einstellungen.routine) { $s in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name, z. B. Bad heizen", text: $s.name)
                        HStack { TextField("script.turn_on", text: $s.dienst); TextField("script.bad_heizen", text: $s.ziel) }.font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Stepper(s.minuten < 0 ? "\(-s.minuten) min vor dem Wecker" : s.minuten == 0 ? "beim Wecken" : "\(s.minuten) min nach dem Wecker", value: $s.minuten, in: -120...60, step: 5)
                        if s.dienst == "light.turn_on" {
                            Stepper(s.langsam == 0 ? "Licht sofort an" : "Licht langsam heller: \(s.langsam / 60) min", value: $s.langsam, in: 0...1800, step: 60)
                        }
                    }
                }
                .onDelete { k.einstellungen.routine.remove(atOffsets: $0) }
                Button("Schritt hinzufügen") { k.einstellungen.routine.append(RoutinenSchritt(name: "Bad heizen", dienst: "script.turn_on", ziel: "", minuten: -20)) }
                Button("Licht langsam an (Vorlage)") { k.einstellungen.routine.append(RoutinenSchritt(name: "Licht langsam an", dienst: "light.turn_on", ziel: "light.schlafzimmer", minuten: -10, langsam: 600)) }
                Button(kern.einstellungen.routine.isEmpty ? "Morgenroutine aus Home Assistant entfernen" : "In Home Assistant einrichten") { Task { await kern.routineEinrichten() } }
                if !kern.routineMeldung.isEmpty { Text(kern.routineMeldung).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Morgenroutine (Home Assistant)") } footer: { Text("Die App legt in Home Assistant die Automation „Guten Morgen – Morgenroutine“ an und meldet die Weckzeit als sensor.guten_morgen_wecker. Home Assistant führt die Schritte dann selbst aus – auch wenn das iPhone schläft. Nach Änderungen hier noch einmal „einrichten“ tippen. Braucht einen Zugang mit Admin-Rechten.") }

            Section {
                Text("1. iPhone-Einstellungen → Fokus → „+“ → Eigener Fokus „Schule“.\n2. Dort „Zeitplan hinzufügen“ → Ort → Schule: dann schaltet iOS den Fokus an, sobald du dort bist.\n3. Unten bei „Fokus-Filter“ → Guten Morgen → „Schul-Infos zuerst“ einschalten.").font(.footnote)
                Button("iPhone-Einstellungen öffnen") { if let u = URL(string: UIApplication.openSettingsURLString) { oeffneURL(u) } }
            } header: { Text("Fokus „Schule“") } footer: { Text("Den Fokus selbst darf eine App nicht einschalten – iOS macht das aber zuverlässig nach Ort. Guten Morgen zeigt im Fokus die Schul-Infos zuerst.") }

            Section {
                Text("Die Apple-Watch-App steckt in der Datei „GutenMorgen-iOS-mit-Uhr“ im Release. Damit installiert, erscheint sie auf der Uhr (Watch-App auf dem iPhone → Verfügbare Apps). Sie zeigt Wecker, was gerade läuft und den Tagesablauf. Die Live-Aktivität erscheint außerdem im Smart Stack der Uhr, und der Wecker klingelt auch dort.").font(.footnote)
            } header: { Text("Apple Watch") }

            Section {
                Toggle("Speiseplan zeigen", isOn: $k.einstellungen.mensa)
                if kern.einstellungen.mensa {
                    TextField("Adresse des Kantinen-Portals (https://…)", text: $k.einstellungen.mensaAdresse).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Benutzername", text: $k.einstellungen.mensaBenutzer).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $k.mensaPasswort)
                }
            } header: { Text("Mensa") } footer: { Text("Das Essen des Tages aus dem Kantinen-Portal (PCA) – dieselben Zugangsdaten wie im Browser. Bestellte Gerichte stehen vorne.") }

            Section {
                Toggle("Schulobst-Tage zeigen", isOn: $k.einstellungen.obst)
                if kern.einstellungen.obst {
                    TextField("Kalender-Link (…/calendar.ics)", text: $k.einstellungen.obstKalender).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            } header: { Text("Schulobst") } footer: { Text("Öffentlicher IServ-Kalender mit den Liefertagen (Kalender → Teilen → öffentlicher Link).") }

            WeckmusikAbschnitt(musik: kern.musik)

            Section {
                Toggle("Mitteilungen bei neuen Störungen und Aufgaben", isOn: $k.einstellungen.mitteilungen)
                    .onChange(of: kern.einstellungen.mitteilungen) { _, an in if an { Task { _ = await Melder.erlauben(); await kern.widgetUebergeben(erzwingen: true) } } }
            } header: { Text("Mitteilungen") } footer: { Text("Geprüft wird, wenn sich das Widget aktualisiert (mehrmals am Tag, morgens alle 10 Minuten) – dafür muss das Widget auf dem Home-Bildschirm liegen.") }

            Section {
                LabeledContent("Schule", value: kern.einstellungen.schulOrt == nil ? "nicht gesetzt" : "gespeichert")
                Button("Aktueller Standort ist die Schule") { Task { await kern.ortMerken(schule: true) } }
                LabeledContent("Zuhause", value: kern.einstellungen.zuhauseOrt == nil ? "nicht gesetzt" : "gespeichert")
                Button("Aktueller Standort ist Zuhause") { Task { await kern.ortMerken(schule: false) } }
                if kern.einstellungen.schulOrt != nil || kern.einstellungen.zuhauseOrt != nil {
                    Button("Orte vergessen", role: .destructive) { k.einstellungen.schulOrt = nil; k.einstellungen.zuhauseOrt = nil }
                }
            } header: { Text("Orte") } footer: { Text("In der Schule stehen Vertretung, Aufsicht und Mensa oben, zu Hause und am Wochenende Termine und Post & Pakete. Ohne Orte entscheidet die Uhrzeit. Fürs Widget: Ortungsdienste → Guten Morgen → „Beim Verwenden der App oder von Widgets“.") }

            Section {
                Toggle("Schlaf aus Apple Health", isOn: $k.einstellungen.gesundheit)
                    .onChange(of: kern.einstellungen.gesundheit) { _, an in if an { Task { _ = await Gesundheit.erlauben(); await kern.aktualisieren() } } }
            } header: { Text("Apple Health") } footer: { Text("Zeigt morgens, wie lange du geschlafen hast, und trägt den Nachtmodus als Schlaf („im Bett“) in Health ein.") }

            Section {
                Toggle("Abwesenheiten (Kinder)", isOn: $k.einstellungen.abwesenheiten)
                Toggle("Störungsmeldungen", isOn: $k.einstellungen.stoerungen)
                if kern.einstellungen.abwesenheiten || kern.einstellungen.stoerungen {
                    TextField("IServ-Adresse, z. B. schule.de", text: $k.einstellungen.iservServer).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Benutzername", text: $k.einstellungen.iservBenutzer).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $k.iservPasswort)
                    SecureField("2FA-Schlüssel (optional)", text: $k.totpGeheim)
                    if kern.einstellungen.abwesenheiten {
                        TextField("Nur Klassen, z. B. 2a, 2b (leer = alle)", text: $k.einstellungen.abwesendKlassen).textInputAutocapitalization(.never)
                        Toggle("Sichtschutz im Widget (nur Vorname + Initiale)", isOn: $k.einstellungen.sichtschutz)
                    }
                    if !kern.einstellungen.iservHosts.isEmpty { LabeledContent("Bestätigte Anmeldeseiten", value: kern.einstellungen.iservHosts.joined(separator: ", ")) }
                    Button("Neu suchen (Module erkunden)") { k.einstellungen.abwesendQuelle = nil; k.einstellungen.stoerungQuelle = nil; Task { await kern.moduleLaden(erzwingen: true) } }
                }
            } header: { Text("IServ") } footer: { Text("Wie in den Skripten Abwesenheiten und Störungen. Mit 2FA-Schlüssel (Text unter dem QR-Code beim Einrichten der Zwei-Faktor-Anmeldung) erzeugt die App die Codes selbst – sonst fragt sie danach, und das Widget zeigt nur den letzten Stand. Achtung: Passwort und zweiter Faktor liegen dann auf demselben Gerät. Abwesenheiten werden nur angezeigt, nicht ausgewertet.") }

            Section {
                if kern.edupoolToken.isEmpty {
                    Button(kern.edupoolCode == nil ? "Mit Edupool Boards verbinden" : "Warte auf Bestätigung (Code \(kern.edupoolCode!)) …") {
                        if kern.edupoolCode == nil { Task { await kern.edupoolVerbinden { u in oeffneURL(u) } } }
                    }
                    if kern.edupoolCode != nil { Button("Abbrechen", role: .cancel) { kern.edupoolCode = nil } }
                } else {
                    Toggle("Aufgaben zeigen", isOn: $k.einstellungen.aufgaben)
                    TextField("Kartenfarbe deiner Aufgaben", text: $k.einstellungen.aufgabenFarbe).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Verbindung trennen", role: .destructive) { k.edupoolToken = ""; k.aufgaben = nil; k.einstellungen.aufgaben = false }
                }
            } header: { Text("Edupool-Aufgaben") } footer: { Text("Verbinden öffnet die Freigabeseite von Edupool Boards mit eingetragenem Code: anmelden, nur „Lesen“ anhaken, Laufzeit wählen (bis 90 Tage), bestätigen und zurück in die App. Dein Passwort sieht die App nie.") }

            Section {
                TextField("Name des Skripts", text: $k.einstellungen.meinTagSkript).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !kern.einstellungen.kollegium.isEmpty { LabeledContent("Kollegium", value: "\(kern.einstellungen.kollegium.count) Namen") }
            } header: { Text("Mein Tag (Scriptable)") } footer: { Text("Abwesenheiten, Störungen und Aufgaben öffnen sich in Mein Tag. Übernehmen: in Scriptable Mein Tag öffnen → Menü → „An Guten Morgen übergeben“ – dann kommen Kürzel, Ordner, Häuser, Kollegium und Kantine (mit Passwort) herüber.") }

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
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .onAppear { haeuserText = Vertretung.text(haeuser: kern.einstellungen.haeuser) }
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
                Text("Spotify").tag(Weckmusik.Quelle.spotify)
                Text("Kurzbefehl").tag(Weckmusik.Quelle.kurzbefehl)
            }
            switch musik.quelle {
            case .apple:
                if !musik.titel.isEmpty { LabeledContent("Titel", value: musik.titel) }
                Button("Titel aus der Mediathek wählen …") { mediathek = true }
            case .datei:
                if !musik.titel.isEmpty { LabeledContent("Datei", value: musik.titel) }
                Button("Musikdatei wählen …") { datei = true }
            case .spotify:
                TextField("Spotify-Link (Playlist oder Titel)", text: $musik.link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            case .kurzbefehl:
                TextField("Name des Kurzbefehls, z. B. Weckmusik", text: $musik.link).autocorrectionDisabled()
            case .aus: EmptyView()
            }
            Stepper("Einblenden: \(musik.einblendenSek) s", value: $musik.einblendenSek, in: 10...300, step: 10)
            HStack { Image(systemName: "speaker.fill"); Slider(value: $musik.zielLautstaerke, in: 0.2...1); Image(systemName: "speaker.wave.3.fill") }
        } header: { Text("Weckmusik (Nachtmodus)") } footer: {
            Text("Im Nachtmodus bleibt die App auf dem Nachttisch offen (am besten am Ladekabel) und spielt zur Weckzeit die Musik – leise beginnend. Der normale Wecker klingelt zur Sicherheit 5 Minuten später.\n\nSpotify: In Spotify bei einer Playlist „Teilen → Link kopieren“ und hier einfügen – zur Weckzeit öffnet sich Spotify damit und die Lautstärke wird langsam lauter (falls Spotify nicht von selbst losspielt: einmal auf Play). Zuverlässiger: einen Kurzbefehl mit „Spotify: Wiedergabe“ bzw. „Medien wiedergeben“ anlegen und hier unter „Kurzbefehl“ seinen Namen eintragen.")
        }
        .sheet(isPresented: $mediathek) { MediathekWahl { musik.appleGewaehlt($0) } }
        .fileImporter(isPresented: $datei, allowedContentTypes: [.audio]) { erg in
            if case .success(let url) = erg { _ = musik.dateiGewaehlt(url) }
        }
    }
}
