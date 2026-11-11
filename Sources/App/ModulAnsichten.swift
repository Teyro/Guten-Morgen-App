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

/// Störungsmeldungen: offene zuerst (neueste oben), wer sie übernommen hat; antippen zeigt den Text
struct StoerungenAnsicht: View {
    @Bindable var kern: Kern
    @State private var offen: Stoerung?

    var body: some View {
        let st = kern.stoerungen
        let liste = kern.einstellungen.erledigteZeigen ? (st?.alle ?? []) : (st?.offen ?? [])
        List {
            Section {
                HStack(spacing: 14) {
                    Text("\(st?.offen.count ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded))
                    VStack(alignment: .leading) {
                        Text("offene Störungen").font(.headline)
                        Text("\(st?.offen.filter { !$0.uebernommen }.count ?? 0) noch ohne Bearbeiter").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14).glas(20).listRowBackground(Color.clear).listRowSeparator(.hidden)
                Toggle("Erledigte zeigen", isOn: $kern.einstellungen.erledigteZeigen).listRowBackground(Color.clear)
                if !kern.stoerungenFehler.isEmpty { Label(kern.stoerungenFehler, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).listRowBackground(Color.clear) }
            }
            Section {
                ForEach(liste, id: \.self) { m in
                    Button { offen = m } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.titel).font(.body.weight(.semibold)).foregroundStyle(m.erledigt ? .secondary : .primary)
                            Text([m.ort, m.datum.map { $0.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month(.twoDigits).hour().minute()) } ?? "", m.autor.isEmpty ? "" : "von \(m.autor)"]
                                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            Text(m.zustand).font(.caption.weight(.semibold)).foregroundStyle(m.erledigt ? .green : m.uebernommen ? .blue : .orange)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Störungen")
        .refreshable { await kern.moduleLaden(erzwingen: true) }
        .sheet(item: Binding(get: { offen.map { Kasten(m: $0) } }, set: { offen = $0?.m })) { k in
            NavigationStack {
                StoerungDetail(m: k.m)
                    .background(Hintergrund(farbton: kern.farbton))
                    .navigationTitle("Störung").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { offen = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
    struct Kasten: Identifiable { let m: Stoerung; var id: String { m.titel + m.url + (m.datum?.description ?? "") } }
}

/// Eine Störungsmeldung ausführlich: Zustand groß, alle Angaben, ganzer Text, Link zu IServ
struct StoerungDetail: View {
    let m: Stoerung
    private var farbe: Color { m.erledigt ? .green : m.uebernommen ? .blue : .orange }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.zustand).font(.subheadline.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(farbe.opacity(0.2), in: Capsule()).foregroundStyle(farbe)
                    Text(m.titel).font(.title2.weight(.bold))
                    if let d = m.datum {
                        Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month().hour().minute()) + " · " + d.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22, farbe: farbe)

                VStack(alignment: .leading, spacing: 10) {
                    angabe("mappin.and.ellipse", "Ort", m.ort)
                    angabe("person.fill", "Gemeldet von", m.autor)
                    angabe("wrench.adjustable.fill", "Bearbeitet von", m.bearbeiter.isEmpty ? (m.unbesetzt ? "noch niemand" : "") : m.bearbeiter)
                    angabe("flag.fill", "Status", m.status)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung").font(.headline)
                    Text(m.inhalt.isEmpty ? "Kein weiterer Text." : m.inhalt).font(.body).textSelection(.enabled)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22)

                if let u = URL(string: m.url), !m.url.isEmpty {
                    Link(destination: u) { Label("In IServ öffnen", systemImage: "safari").frame(maxWidth: .infinity).padding(12) }
                        .glas(18, farbe: .blue)
                }
            }
            .padding()
        }
    }

    @ViewBuilder private func angabe(_ s: String, _ t: String, _ w: String) -> some View {
        if !w.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: s).foregroundStyle(.secondary).frame(width: 22)
                Text(t).foregroundStyle(.secondary)
                Spacer()
                Text(w).multilineTextAlignment(.trailing).font(.body.weight(.medium))
            }
        }
    }
}

/// Edupool-Aufgaben nach Kategorien (Ideen, Zu erledigen, In Bearbeitung, Wartet, Erledigt), mit Suche; antippen = ganzer Text
struct AufgabenAnsicht: View {
    @Bindable var kern: Kern
    @State private var suche = ""
    @State private var erledigte = false
    static let farben: [Color] = [Color(red: 0.42, green: 0.31, blue: 0.77), Color(red: 0.6, green: 0.38, blue: 0), Color(red: 0.11, green: 0.44, blue: 0.65),
                                  Color(red: 0.71, green: 0.27, blue: 0.12), Color(red: 0.17, green: 0.48, blue: 0.26)]

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
                            NavigationLink { AufgabeAnsicht(a: x, farbe: Self.farben[g.kategorie]) } label: {
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
    let a: Aufgabe
    let farbe: Color
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
        }
        .navigationTitle(a.titel)
        .navigationBarTitleDisplayMode(.inline)
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
