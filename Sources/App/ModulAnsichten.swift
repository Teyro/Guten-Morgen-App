import SwiftUI
import MorgenKern

/// Wer fehlt (Kinder) – nur Anzeige, wie im Abwesenheiten-Skript: ganztägig zuerst, dann einzelne Stunden
struct AbwesendAnsicht: View {
    @Bindable var kern: Kern

    var body: some View {
        let e = kern.einstellungen
        let ziel = kern.schulTag
        let liste = Abwesenheiten.amTag(kern.abwesend?.eintraege ?? [], ziel: ziel, klassen: e.klassenListe)
        List {
            Section {
                HStack(spacing: 14) {
                    Text("\(liste.count)").font(.system(size: 44, weight: .bold, design: .rounded))
                    VStack(alignment: .leading) {
                        Text(liste.count == 1 ? "Kind fehlt" : "Kinder fehlen").font(.headline)
                        Text(kern.schulTagName.capitalized + (e.klassenListe.isEmpty ? "" : " · " + e.klassenListe.joined(separator: ", "))).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14).glas(20).listRowBackground(Color.clear).listRowSeparator(.hidden)
                if !kern.abwesendFehler.isEmpty { Label(kern.abwesendFehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).listRowBackground(Color.clear) }
            }
            let ganz = liste.filter { !$0.stundenweise }, std = liste.filter(\.stundenweise)
            if !ganz.isEmpty { Section("Ganztägig") { ForEach(ganz, id: \.self) { zeile($0, ziel) } } }
            if !std.isEmpty { Section("Einzelne Stunden") { ForEach(std, id: \.self) { zeile($0, ziel) } } }
            if let s = kern.abwesend?.stand { Text("Stand " + s.uhrzeit).font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Abwesenheiten")
        .refreshable { await kern.moduleLaden(erzwingen: true) }
    }

    private func zeile(_ a: Abwesenheit, _ ziel: Date) -> some View {
        let art = Abwesenheiten.arten[a.art] ?? ("📌", "abwesend")
        return HStack(spacing: 10) {
            Text(art.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name).font(.body.weight(.semibold))
                Text([a.klasse, art.wort, Abwesenheiten.zeitText(a, ziel: ziel)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Störungsmeldungen: oben die Zahlen, darunter getrennt nach „Noch niemand“, „In Arbeit“ und „Erledigt“
struct StoerungenAnsicht: View {
    @Bindable var kern: Kern
    @State private var offen: Stoerung?

    var body: some View {
        let st = kern.stoerungen
        let neu = st?.offen.filter { !$0.uebernommen } ?? []
        let arbeit = st?.offen.filter(\.uebernommen) ?? []
        let erledigt = (st?.alle ?? []).filter(\.erledigt)
        List {
            Section {
                HStack(spacing: 10) {
                    StatusZahl(zahl: neu.count, text: "Noch niemand", symbol: "exclamationmark.circle.fill", farbe: .orange)
                    StatusZahl(zahl: arbeit.count, text: "In Arbeit", symbol: "wrench.adjustable.fill", farbe: .blue)
                    StatusZahl(zahl: erledigt.count, text: "Erledigt", symbol: "checkmark.circle.fill", farbe: .green)
                }
                .listRowBackground(Color.clear).padding(.vertical, 10).listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)).listRowSeparator(.hidden)
                if !kern.stoerungenFehler.isEmpty {
                    Label(kern.stoerungenFehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
            }
            gruppe("Noch niemand zuständig", neu, farbe: .orange)
            gruppe("In Arbeit", arbeit, farbe: .blue)
            if kern.einstellungen.erledigteZeigen { gruppe("Erledigt", erledigt, farbe: .green) }
            Section {
                Toggle("Erledigte zeigen", isOn: $kern.einstellungen.erledigteZeigen)
            } footer: {
                if let s = st?.stand { Text("Stand " + s.uhrzeit) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Störungen")
        .refreshable { await kern.moduleLaden(erzwingen: true) }
        .sheet(item: Binding(get: { offen.map { Kasten(m: $0) } }, set: { offen = $0?.m })) { k in
            NavigationStack {
                StoerungDetail(kern: kern, m: k.m)
                    .background(Hintergrund(farbton: kern.farbton))
                    .navigationTitle("Störung").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { offen = nil } } }
            }
            .presentationDetents([.large])
        }
    }

    @ViewBuilder private func gruppe(_ titel: String, _ liste: [Stoerung], farbe: Color) -> some View {
        if !liste.isEmpty {
            Section {
                ForEach(liste, id: \.self) { m in
                    Button { offen = m } label: { StoerungZeile(m: m) }.buttonStyle(.plain)
                }
            } header: {
                Text("\(titel) (\(liste.count))").foregroundStyle(farbe)
            }
        }
    }
    struct Kasten: Identifiable { let m: Stoerung; var id: String { m.titel + m.url + (m.datum?.description ?? "") } }
}

/// Farbe und Symbol je Zustand – überall gleich
extension Stoerung {
    var farbe: Color { erledigt ? .green : uebernommen ? .blue : .orange }
    var symbol: String { erledigt ? "checkmark.circle.fill" : uebernommen ? "wrench.adjustable.fill" : "exclamationmark.circle.fill" }
    var zustandKurz: String { erledigt ? "Erledigt" : !bearbeiter.isEmpty ? bearbeiter : uebernommen ? (status.isEmpty ? "In Arbeit" : status) : "Noch niemand" }
}

/// Eine Zahl mit Symbol als kleine Glaskachel
struct StatusZahl: View {
    let zahl: Int, text: String, symbol: String, farbe: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3).foregroundStyle(farbe)
            Text("\(zahl)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).glas(18)
    }
}

/// Zeile: Zustand als farbiges Symbol links, Titel, darunter Ort · Zeit · Melder
struct StoerungZeile: View {
    let m: Stoerung
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: m.symbol).font(.title2).foregroundStyle(m.farbe).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.titel).font(.body.weight(.semibold)).foregroundStyle(m.erledigt ? .secondary : .primary).lineLimit(2)
                HStack(spacing: 10) {
                    if !m.ort.isEmpty { Label(m.ort, systemImage: "mappin.and.ellipse").lineLimit(1) }
                    if let d = m.datum { Label(d.formatted(.relative(presentation: .named)), systemImage: "clock").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary).labelStyle(KleinesSymbol())
                Text(m.zustandKurz).font(.caption.weight(.semibold)).foregroundStyle(m.farbe)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(m.farbe.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Label mit kleinem Abstand zwischen Symbol und Text
struct KleinesSymbol: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 3) { configuration.icon; configuration.title } }
}

/// Eine Störungsmeldung: farbiger Kopf mit Zustand, Angaben, Beschreibung, Verlauf als Gespräch, unten Antworten
struct StoerungDetail: View {
    let kern: Kern
    let m: Stoerung
    @State private var verlauf: StoerungVerlauf?
    @State private var fehler = ""
    @State private var antwort = ""
    @State private var sendet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Kopf
                VStack(alignment: .leading, spacing: 10) {
                    Label(m.zustandKurz, systemImage: m.symbol).font(.subheadline.weight(.bold)).foregroundStyle(m.farbe)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(m.farbe.opacity(0.16), in: Capsule())
                    Text(m.titel).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    if let d = m.datum {
                        Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month().hour().minute()) + " · " + d.formatted(.relative(presentation: .named)))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).glas(24, farbe: m.farbe)

                // Angaben
                VStack(spacing: 0) {
                    angabe("mappin.and.ellipse", .red, "Ort", m.ort)
                    angabe("person.fill", .gray, "Gemeldet von", m.autor)
                    angabe("wrench.adjustable.fill", .blue, "Bearbeitet von", m.bearbeiter.isEmpty ? (m.unbesetzt ? "noch niemand" : "") : m.bearbeiter)
                    angabe("flag.fill", m.farbe, "Status", m.status)
                }
                .padding(.vertical, 4).glas(22)

                abschnitt("Beschreibung", "text.alignleft") {
                    Text(m.inhalt.isEmpty ? "Kein weiterer Text." : m.inhalt).font(.body).foregroundStyle(m.inhalt.isEmpty ? .secondary : .primary).textSelection(.enabled)
                }

                if !m.url.isEmpty {
                    abschnitt("Verlauf", "bubble.left.and.bubble.right.fill") {
                        if let v = verlauf {
                            if v.eintraege.isEmpty { Text("Noch keine Antworten.").foregroundStyle(.secondary) }
                            ForEach(Array(v.eintraege.enumerated()), id: \.offset) { _, e in blase(e) }
                            if v.formular == nil { Label("Antworten geht für diese Meldung nur in IServ.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                        } else if fehler.isEmpty {
                            HStack { ProgressView(); Text("Lade Verlauf …").foregroundStyle(.secondary) }
                        }
                        if !fehler.isEmpty { Label(fehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                    }
                }

                if let u = URL(string: m.url), !m.url.isEmpty {
                    Link(destination: u) { Label("In IServ öffnen", systemImage: "safari").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(14) }
                        .glas(18, farbe: .blue)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if let f = verlauf?.formular {
                AntwortFeld(text: $antwort, sendet: sendet) { Task { await senden(f) } }
                    .padding(.horizontal).padding(.vertical, 10).background(.bar)
            }
        }
        .task { await laden() }
    }

    /// Jeder Kommentar eine Blase wie im Chat: Bearbeiter (Technik) rechts, alle anderen links. Farbe je Person aus dem
    /// Edupool-Board „Medien“, sonst eine feste Farbe aus dem Namen; dazu ein Kreis mit den Initialen.
    private func blase(_ e: StoerungVerlauf.Eintrag) -> some View {
        let technik = !m.bearbeiter.isEmpty && !e.autor.isEmpty && (e.autor.localizedCaseInsensitiveContains(m.bearbeiter) || m.bearbeiter.localizedCaseInsensitiveContains(e.autor))
        let farbe = Aufgaben.farbe(fuer: e.autor, in: kern.personenFarben).map(FarbWahl.farbe) ?? Self.namensFarbe(e.autor)
        let initialen = e.autor.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let kreis = Text(initialen.isEmpty ? "?" : initialen).font(.caption2.weight(.bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(farbe.gradient, in: Circle())
        return HStack(alignment: .bottom, spacing: 8) {
            if technik { Spacer(minLength: 36) } else { kreis }
            VStack(alignment: .leading, spacing: 4) {
                if !e.autor.isEmpty || !e.zeit.isEmpty {
                    Text([e.autor, e.zeit].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(farbe)
                }
                Text(e.text).font(.callout).textSelection(.enabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(farbe.opacity(0.16), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: technik ? 18 : 4, bottomTrailingRadius: technik ? 4 : 18, topTrailingRadius: 18, style: .continuous))
            if technik { kreis } else { Spacer(minLength: 36) }
        }
    }

    /// Feste Farbe aus dem Namen (gleicher Name = gleiche Farbe)
    static func namensFarbe(_ name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .cyan]
        let h = name.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return palette[Int(h % UInt32(palette.count))]
    }

    private func abschnitt<I: View>(_ titel: String, _ symbol: String, @ViewBuilder inhalt: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titel, systemImage: symbol).font(.headline)
            inhalt()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22)
    }

    @ViewBuilder private func angabe(_ s: String, _ farbe: Color, _ t: String, _ w: String) -> some View {
        if !w.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: s).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(farbe.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(t).foregroundStyle(.secondary)
                Spacer()
                Text(w).multilineTextAlignment(.trailing).font(.body.weight(.medium))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
    }

    private func laden() async {
        guard !m.url.isEmpty else { return }
        do { verlauf = try await kern.stoerungVerlauf(m.url); fehler = "" } catch { fehler = error.localizedDescription }
    }

    private func senden(_ f: StoerungVerlauf.Formular) async {
        sendet = true; defer { sendet = false }
        do { try await kern.stoerungAntworten(f, text: antwort); antwort = ""; await laden() } catch { fehler = error.localizedDescription }
    }
}

/// Edupool-Aufgaben nach Kategorien (Ideen, Zu erledigen, In Bearbeitung, Wartet, Erledigt), mit Suche; antippen = ganzer Text
struct AufgabenAnsicht: View {
    @Bindable var kern: Kern
    @State private var suche = ""
    @State private var erledigte = false
    /// Systemfarben je Kategorie (Ideen, Zu erledigen, In Bearbeitung, Wartet, Erledigt)
    static let farben: [Color] = [.purple, .blue, .orange, .pink, .green]

    var body: some View {
        let st = kern.aufgaben
        List {
            Section {
                HStack(spacing: 14) {
                    Text("\(st?.offen.count ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded))
                    VStack(alignment: .leading) {
                        Text("offene Aufgaben").font(.headline)
                        Text(st.map { "\($0.boards) Boards · Stand \($0.stand.uhrzeit)" } ?? "noch nicht geladen").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14).glas(20).listRowBackground(Color.clear).listRowSeparator(.hidden)
                Toggle("Erledigte zeigen", isOn: $erledigte).listRowBackground(Color.clear)
                if !kern.aufgabenFehler.isEmpty { Label(kern.aufgabenFehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).listRowBackground(Color.clear) }
            }
            ForEach(st?.gruppen() ?? [], id: \.kategorie) { g in
                let k = Aufgaben.kategorien[g.kategorie]
                let a = g.aufgaben.filter { suche.isEmpty || ($0.titel + " " + $0.beschreibung).localizedCaseInsensitiveContains(suche) }
                if (!k.erledigt || erledigte) && !a.isEmpty {
                    Section {
                        ForEach(a) { x in
                            NavigationLink { AufgabeAnsicht(kern: kern, a: x, farbe: Self.farben[g.kategorie]) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.titel).font(.body.weight(.semibold))
                                    if !x.beschreibung.isEmpty { Text(x.beschreibung).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    Text(x.boardTitel + (x.geaendert.map { " · " + $0.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month(.twoDigits)) } ?? "")).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: { Label("\(k.name) (\(a.count))", systemImage: k.symbol).foregroundStyle(Self.farben[g.kategorie]) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .searchable(text: $suche, prompt: "Aufgaben durchsuchen")
        .navigationTitle("Aufgaben")
        .refreshable { await kern.moduleLaden(erzwingen: true) }
    }
}

/// Eine Aufgabe mit allem Inhalt (Text, Links, Dateien) – aus dem Speicher, ohne Netz
struct AufgabeAnsicht: View {
    let kern: Kern
    let a: Aufgabe
    let farbe: Color
    @State private var kommentare: [Aufgaben.Kommentar]?
    @State private var fehler = ""
    @State private var antwort = ""
    @State private var sendet = false
    var body: some View {
        List {
            Section {
                Label(Aufgaben.kategorien[a.kategorie].name, systemImage: Aufgaben.kategorien[a.kategorie].symbol).foregroundStyle(farbe)
                LabeledContent("Board", value: a.boardTitel)
                if !a.spalte.isEmpty { LabeledContent("Spalte", value: a.spalte) }
            }
            Section {
                ForEach(Array(a.inhalt.enumerated()), id: \.offset) { _, b in
                    switch b.typ {
                    case "text": Text(Self.formatiert(b.text))
                    case "link":
                        if let u = URL(string: b.url) { Link(destination: u) { Label(b.titel.isEmpty ? b.url : b.titel, systemImage: "link") } }
                    case "image": if let u = URL(string: b.url) { Link(destination: u) { Label(b.titel.isEmpty ? "Bild" : b.titel, systemImage: "photo") } }
                    case "file": Label(b.titel, systemImage: "doc")
                    case "video", "audio": if let u = URL(string: b.url) { Link(destination: u) { Label(b.titel.isEmpty ? b.typ.capitalized : b.titel, systemImage: b.typ == "video" ? "play.rectangle" : "waveform") } }
                    default: VStack(alignment: .leading) { Text(b.titel).font(.headline); if !b.text.isEmpty { Text(b.text).font(.callout) } }
                    }
                }
            }
            Section {
                if let k = kommentare {
                    if k.isEmpty { Text("Noch keine Kommentare.").foregroundStyle(.secondary) }
                    ForEach(k) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text([c.autor, c.zeit.map { $0.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month(.twoDigits).hour().minute()) } ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(c.text).textSelection(.enabled)
                        }
                    }
                } else if fehler.isEmpty { ProgressView() }
                if !fehler.isEmpty { Label(fehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                AntwortFeld(text: $antwort, sendet: sendet) { Task { await senden() } }
            } header: { Text("Kommentare") }
        }
        .navigationTitle(a.titel)
        .navigationBarTitleDisplayMode(.inline)
        .task { await laden() }
        .refreshable { await laden() }
    }

    private func laden() async {
        do { kommentare = try await kern.aufgabeKommentare(a.id); fehler = "" } catch { fehler = error.localizedDescription }
    }

    private func senden() async {
        sendet = true; defer { sendet = false }
        do { try await kern.aufgabeAntworten(a.id, text: antwort); antwort = ""; await laden() } catch { fehler = error.localizedDescription }
    }

    /// HTML → Markdown-ähnlich, dann als formatierter Text (fett, kursiv, Links, Listen)
    static func formatiert(_ s: String) -> AttributedString {
        var t = s.replacingOccurrences(of: #"<(b|strong)>(.*?)</\1>"#, with: "**$2**", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<(i|em)>(.*?)</\1>"#, with: "*$2*", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<a [^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, with: "[$2]($1)", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<li[^>]*>"#, with: "\n• ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"</p>|<br\s*/?>|</h\d>|</div>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (x, y) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { t = t.replacingOccurrences(of: x, with: y) }
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }
}


/// Eingabe für eine Antwort mit Senden-Knopf (wie in Nachrichten)
struct AntwortFeld: View {
    @Binding var text: String
    let sendet: Bool
    let senden: () -> Void
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Antworten …", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
            Button(action: senden) {
                if sendet { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
            }
            .disabled(sendet || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Senden")
        }
    }
}
