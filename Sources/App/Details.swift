import SwiftUI
import MorgenKern

/// Liquid Glass ab iOS 26, sonst Milchglas
extension View {
    @ViewBuilder func glas(_ radius: CGFloat = 20, farbe: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(farbe.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(farbe.map { AnyShapeStyle($0.opacity(0.18)) } ?? AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    /// Getöntes, interaktives Glas für Knöpfe (iOS 26), sonst farbiger Verlauf
    @ViewBuilder func glasKnopf(_ farbe: Color, _ radius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(farbe).interactive(), in: .rect(cornerRadius: radius))
        } else {
            self.background(farbe.gradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// Farben wie das Kantinen-Skript (Design „kantine“: warmes Dunkelbraun, Orange)
enum Kantine {
    static let oben = Color(red: 0x2b / 255, green: 0x19 / 255, blue: 0x10 / 255)
    static let unten = Color(red: 0x14 / 255, green: 0x0b / 255, blue: 0x06 / 255)
    static let akzent = Color(red: 1, green: 0x6f / 255, blue: 0x1f / 255)
    static let gut = Color(red: 0.2, green: 0.75, blue: 0.4)
}

/// Speiseplan wie die Übersicht im Kantinen-Skript – Held-Karte, Kennzahlen, Wochen-Reiter, Tage mit Menüs.
/// Wischen nach rechts: ⭐ Lieblingsessen, nach links: 👎 nicht lecker (wie die Merken-Knöpfe im Skript).
struct MensaAnsicht: View {
    @Bindable var kern: Kern
    @State private var woche = 0
    @State private var zusatz = false

    var body: some View {
        let e = kern.einstellungen
        let gut = Set(e.lieblingsGerichte.map(Gericht.schluessel)), schlecht = Set(e.nichtLecker.map(Gericht.schluessel))
        List {
            if let p = kern.mensaPlan {
                Section { held(p, e).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                Section { kennzahlen(p).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                let wochen = wochen(p.tage)
                if wochen.count > 1 {
                    Picker("Woche", selection: $woche) { ForEach(wochen.indices, id: \.self) { Text(wochen[$0].0).tag($0) } }
                        .pickerStyle(.segmented).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(wochen.indices.contains(woche) ? wochen[woche].1 : [], id: \.datum) { t in
                    Section { tag(t, gut: gut, schlecht: schlecht, e: e) } header: { tagKopf(t) }
                }
            } else {
                Text(kern.mensaFehler.isEmpty ? "Noch kein Speiseplan geladen." : kern.mensaFehler).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Zusatzstoffe zeigen", isOn: $zusatz)
                    TextField("Lieblingsessen-Stichwörter, z. B. Pizza, Nudeln", text: $kern.einstellungen.favoriten)
                    TextField("Meiden, z. B. Schwein, Fisch", text: $kern.einstellungen.meiden)
                    Text("Gemerkt: \(e.lieblingsGerichte.count)× ⭐, \(e.nichtLecker.count)× 👎 – wischen zum Merken.").font(.caption).foregroundStyle(.secondary)
                    if let u = URL(string: e.mensaAdresse), !e.mensaAdresse.isEmpty {
                        Link(destination: u) { Label("Im Kantinen-Portal bestellen", systemImage: "cart.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 46) }
                            .foregroundStyle(.white).background(LinearGradient(colors: [Color(red: 1, green: 0.64, blue: 0.28), Kantine.akzent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(14).glas(20).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LinearGradient(colors: [Kantine.oben, Kantine.unten], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .tint(Kantine.akzent)
        .navigationTitle("Speiseplan")
        .refreshable { await kern.aktualisieren() }
        .onAppear { woche = wochen(kern.mensaPlan?.tage ?? []).firstIndex { w in w.1.contains { $0.datum == Zeit.iso(kern.schulTag) } } ?? 0 }
    }

    // MARK: Teile

    /// Held: was es (für dich) heute bzw. morgen gibt
    @ViewBuilder private func held(_ p: MensaPlan, _ e: MorgenEinstellungen) -> some View {
        let t = p.tag(Zeit.iso(kern.schulTag))
        let g = t?.haupt(favoriten: e.favoriten, meiden: e.meiden, gut: e.lieblingsGerichte, schlecht: e.nichtLecker)
        HStack(spacing: 14) {
            Text(g?.emoji ?? (t?.frei != nil ? "🏖️" : "🍽️")).font(.system(size: 40)).frame(width: 72, height: 72)
                .background(Kantine.akzent.opacity(0.22), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(kern.schulTagName.uppercased()).font(.caption2.weight(.heavy)).tracking(0.5).foregroundStyle(Kantine.akzent)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Kantine.akzent.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                Text(g?.text ?? (t?.frei.map { "Geschlossen" + ($0.isEmpty ? "" : " – \($0)") } ?? "Kein Essen eingetragen")).font(.title3.weight(.bold)).lineLimit(4)
                if let g {
                    HStack(spacing: 6) {
                        Text(g.menue).font(.caption).foregroundStyle(.secondary)
                        Text(g.bestellt ? "✓ bestellt" : "nicht bestellt").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(g.bestellt ? Kantine.gut : Kantine.akzent.opacity(0.25), in: Capsule()).foregroundStyle(g.bestellt ? .white : Kantine.akzent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16).glas(22)
    }

    private func kennzahlen(_ p: MensaPlan) -> some View {
        let bestellt = p.tage.filter { $0.datum >= Zeit.iso(Date()) && $0.gerichte.contains(where: \.bestellt) }.count
        let offen = p.tage.filter { $0.datum >= Zeit.iso(Date()) && $0.frei == nil && !$0.gerichte.isEmpty && !$0.gerichte.contains(where: \.bestellt) }.count
        return HStack(spacing: 10) {
            kpi("Guthaben", p.guthaben.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))) } ?? "–", farbe: (p.guthaben ?? 99) < 10 ? .red : .primary)
            kpi("Bestellt", "\(bestellt)", unter: "Tage")
            kpi("Offen", "\(offen)", unter: "ohne Bestellung", farbe: offen > 0 ? Kantine.akzent : .primary)
        }
    }

    private func kpi(_ titel: String, _ wert: String, unter: String? = nil, farbe: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            Text(wert).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(farbe).lineLimit(1).minimumScaleFactor(0.7)
            if let u = unter { Text(u).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).glas(16)
    }

    private func tagKopf(_ t: MensaTag) -> some View {
        let d = Zeit.tag(t.datum) ?? Date()
        let ziel = t.datum == Zeit.iso(kern.schulTag)
        return HStack {
            Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month(.twoDigits))).font(.subheadline.weight(.bold))
                .foregroundStyle(ziel ? Kantine.akzent : .primary)
            Spacer()
            if t.gerichte.contains(where: \.bestellt) { Text("✓ bestellt").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3).background(Kantine.gut, in: Capsule()).foregroundStyle(.white) }
            else if t.frei != nil { Text("frei").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
        }
        .textCase(nil)
    }

    @ViewBuilder private func tag(_ t: MensaTag, gut: Set<String>, schlecht: Set<String>, e: MorgenEinstellungen) -> some View {
        if let f = t.frei {
            Text(f.isEmpty ? "Geschlossen" : f).italic().foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).glas(16)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        ForEach(t.gerichte, id: \.self) { g in
            let istGut = gut.contains(g.schluessel) || (!e.favoriten.isEmpty && g.passt(e.favoriten))
            let istSchlecht = schlecht.contains(g.schluessel) || (!e.meiden.isEmpty && g.passt(e.meiden, mitZusatz: true))
            HStack(alignment: .top, spacing: 10) {
                Text(g.emoji).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.menue.uppercased()).font(.caption2.weight(.bold)).tracking(0.3).foregroundStyle(g.bestellt ? Kantine.gut : .secondary)
                    Text(g.text).font(.body.weight(.semibold)).foregroundStyle(istSchlecht && !g.bestellt ? .secondary : .primary)
                    if zusatz && !g.zusatz.isEmpty { Text(g.zusatz).font(.caption).foregroundStyle(.secondary) }
                    let m = g.merkmale
                    if !m.isEmpty {
                        HStack(spacing: 4) { ForEach(m, id: \.self) { Text($0).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) } }
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    if istGut { Text("⭐") }
                    if istSchlecht { Text("👎") }
                }
            }
            .padding(12)
            .glas(16, farbe: g.bestellt ? Kantine.gut : nil)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { merken(g, gut: true) } label: { Label(gut.contains(g.schluessel) ? "Nicht mehr ⭐" : "Lieblingsessen", systemImage: "star.fill") }.tint(.yellow)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { merken(g, gut: false) } label: { Label(schlecht.contains(g.schluessel) ? "Doch okay" : "Nicht lecker", systemImage: "hand.thumbsdown.fill") }.tint(.red)
            }
        }
    }

    /// Wie „merkeGericht“ im Skript: aus beiden Listen nehmen, dann (falls neu) in die gewählte – höchstens 200
    private func merken(_ g: Gericht, gut: Bool) {
        var e = kern.einstellungen
        let s = g.schluessel
        let warGut = e.lieblingsGerichte.contains { Gericht.schluessel($0) == s }, warSchlecht = e.nichtLecker.contains { Gericht.schluessel($0) == s }
        e.lieblingsGerichte.removeAll { Gericht.schluessel($0) == s }
        e.nichtLecker.removeAll { Gericht.schluessel($0) == s }
        if gut && !warGut { e.lieblingsGerichte = Array((e.lieblingsGerichte + [g.text]).suffix(200)) }
        if !gut && !warSchlecht { e.nichtLecker = Array((e.nichtLecker + [g.text]).suffix(200)) }
        kern.einstellungen = e
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// Tage nach Kalenderwoche: „Diese Woche“, „Nächste Woche“
    private func wochen(_ tage: [MensaTag]) -> [(String, [MensaTag])] {
        let k = Zeit.kalender
        let jetzt = k.component(.weekOfYear, from: Date())
        let gruppen = Dictionary(grouping: tage) { k.component(.weekOfYear, from: Zeit.tag($0.datum) ?? Date()) }
        return gruppen.keys.sorted { a, b in (a < jetzt - 26 ? a + 53 : a) < (b < jetzt - 26 ? b + 53 : b) }.map { kw in
            (kw == jetzt ? "Diese Woche" : kw == jetzt + 1 || (jetzt >= 52 && kw == 1) ? "Nächste Woche" : "KW \(kw)", gruppen[kw]!.sorted { $0.datum < $1.datum })
        }
    }
}

/// Vertretungsplan ganz: meine Einträge mit Haus, Aufsicht, Hinweise, wer fehlt (mit Namen aus dem Kollegium)
struct VertretungAnsicht: View {
    @Bindable var kern: Kern

    var body: some View {
        let e = kern.einstellungen
        List {
            if let p = kern.vertretung {
                Section {
                    if let d = p.datum.flatMap(Zeit.tag) {
                        LabeledContent("Plan für", value: d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month(.wide)))
                        if p.datum != Zeit.iso(kern.schulTag) {
                            Label("Für \(kern.schulTagName) liegt noch kein eigener Plan im Ordner – das ist der nächstliegende.", systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                    if !p.datei.isEmpty { LabeledContent("Datei", value: p.datei.replacingOccurrences(of: ".docx", with: "")) }
                }
                Section("Für dich (\(e.kuerzel))") {
                    if p.fehlt { Label("Du bist als fehlend eingetragen", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    if p.ausserHaus { Label("Du bist außer Haus eingetragen", systemImage: "figure.walk.departure").foregroundStyle(.orange) }
                    if p.stunden.isEmpty && p.pausen.isEmpty && !p.fehlt { Label("Keine Vertretung, keine Aufsicht", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    ForEach(p.stunden, id: \.self) { s in
                        let h = Vertretung.haus(s.klasse, e.haeuser)
                        Zeile(marke: Int(s.stunde) != nil ? "\(s.stunde)." : String(s.stunde.prefix(4)), farbe: .purple,
                              titel: "Vertretung \(s.klasse)", unter: [Int(s.stunde) != nil ? "\(s.stunde). Stunde" : s.stunde, h].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                    ForEach(p.pausen, id: \.self) { a in
                        Zeile(marke: String(a.pause.prefix(1)) + ". P", farbe: .orange, titel: a.reserve ? "Aufsicht (Reserve)" : "Hofaufsicht", unter: "\(a.pause) · \(a.ort)")
                    }
                    ForEach(p.hinweise, id: \.self) { h in Label(h, systemImage: "exclamationmark.bubble.fill") }
                }
                if !p.alleHinweise.isEmpty {
                    Section("Wichtig (für alle)") { ForEach(p.alleHinweise, id: \.self) { Text($0).font(.callout) } }
                }
                if !p.fehlen.isEmpty {
                    Section("Es fehlen (\(p.fehlen.count))") { ForEach(p.fehlen, id: \.self) { k in kollege(k, e) } }
                }
                if !p.ausserListe.isEmpty {
                    Section("Außer Haus") { ForEach(p.ausserListe, id: \.self) { k in kollege(k, e) } }
                }
            } else {
                Text(kern.vertretungFehler.isEmpty ? "Noch kein Vertretungsplan geladen." : kern.vertretungFehler).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Vertretung")
        .refreshable { await kern.aktualisieren() }
    }

    private func kollege(_ k: String, _ e: MorgenEinstellungen) -> some View {
        HStack {
            Text(k).font(.body.weight(.bold)).frame(width: 56, alignment: .leading)
            Text(e.kollegium.first { $0.key.caseInsensitiveCompare(k) == .orderedSame }?.value ?? "").foregroundStyle(.secondary)
        }
    }
}
