import SwiftUI
import MorgenKern

/// Speiseplan wie im Kantinen-Widget: Guthaben, diese und nächste Woche, bestellt ✓, Lieblingsessen ⭐, Meiden 🚫
struct MensaAnsicht: View {
    @Bindable var kern: Kern
    @State private var zusatz = false

    var body: some View {
        let e = kern.einstellungen
        List {
            if let p = kern.mensaPlan {
                Section {
                    if let g = p.guthaben {
                        LabeledContent("Guthaben verfügbar") {
                            Text(g.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))).font(.headline)
                                .foregroundStyle(g < 10 ? .red : .primary)
                        }
                    }
                    LabeledContent("Stand", value: p.stand.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).hour().minute()))
                }
                ForEach(wochen(p.tage), id: \.0) { (titel, tage) in
                    Section(titel) {
                        ForEach(tage, id: \.datum) { t in tagZeilen(t, e: e) }
                    }
                }
            } else {
                Text(kern.mensaFehler.isEmpty ? "Noch kein Speiseplan geladen." : kern.mensaFehler).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Zusatzstoffe zeigen", isOn: $zusatz)
                TextField("Lieblingsessen, z. B. Pizza, Nudeln", text: $kern.einstellungen.favoriten)
                TextField("Meiden, z. B. Schwein, Fisch", text: $kern.einstellungen.meiden)
                if let u = URL(string: e.mensaAdresse), !e.mensaAdresse.isEmpty { Link("Im Kantinen-Portal bestellen", destination: u) }
            } header: { Text("Auswahl") } footer: { Text("⭐ Lieblingsessen und 🚫 Meiden (auch in den Zusatzstoffen) wie im Kantinen-Widget. Bestellt wird weiter im Portal.") }
        }
        .navigationTitle("Speiseplan")
        .refreshable { await kern.aktualisieren() }
    }

    @ViewBuilder private func tagZeilen(_ t: MensaTag, e: MorgenEinstellungen) -> some View {
        let d = Zeit.tag(t.datum) ?? Date()
        let istZiel = t.datum == Zeit.iso(kern.schulTag)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month(.twoDigits))).font(.subheadline.weight(.semibold))
                if istZiel { Text(Tagwahl.name(d).capitalized).font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(kern.farbton.akzent.opacity(0.2), in: Capsule()).foregroundStyle(kern.farbton.akzent) }
            }
            if let f = t.frei { Text("Geschlossen" + (f.isEmpty ? "" : " – \(f)")).foregroundStyle(.secondary) }
            ForEach(t.gerichte, id: \.self) { g in
                let fav = !e.favoriten.isEmpty && g.passt(e.favoriten)
                let mied = !e.meiden.isEmpty && g.passt(e.meiden, mitZusatz: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(g.bestellt ? "✓" : "·").font(.headline).foregroundStyle(g.bestellt ? .green : .secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((fav ? "⭐ " : mied ? "🚫 " : "") + g.text).font(g.bestellt ? .body.weight(.semibold) : .body)
                            .foregroundStyle(mied && !g.bestellt ? .secondary : .primary)
                        Text(g.menue + (zusatz && !g.zusatz.isEmpty ? " · \(g.zusatz)" : "") + (g.bestellt ? " · bestellt" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(istZiel ? kern.farbton.akzent.opacity(0.08) : nil)
    }

    /// Tage nach Kalenderwoche gruppiert: „Diese Woche“, „Nächste Woche“
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
