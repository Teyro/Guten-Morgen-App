import SwiftUI
import MorgenKern

/// Mein Stundenplan, übersichtlich: Tag, Woche oder nach Klassen – filterbar nach Klasse.
/// Quelle: WebUntis (falls eingerichtet), sonst „Mein Stundenplan“ aus den Einstellungen.
struct StundenplanWoche: View {
    @Bindable var kern: Kern
    @State private var ansicht = 0
    @State private var klasse: String?
    @State private var tag = Zeit.iso(Date())

    /// Alle Stunden der angezeigten Wochen (WebUntis bzw. aus dem eigenen Plan für diese und nächste Woche gebaut)
    private var stunden: [UntisStunde] {
        if let u = kern.untis, !u.meine.isEmpty { return u.meine }
        let k = Zeit.kalender
        let montag = k.date(from: k.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return (0..<12).flatMap { i -> [UntisStunde] in
            guard let d = k.date(byAdding: .day, value: i, to: montag) else { return [] }
            let wt = k.component(.weekday, from: d)
            return kern.einstellungen.unterricht.filter { $0.tag == wt }.compactMap { u in
                guard let z = kern.einstellungen.schulzeiten.first(where: { $0.name == u.stunde }) else { return nil }
                return UntisStunde(datum: Zeit.iso(d), von: z.von, bis: z.bis, fach: u.fach, fachLang: u.fach,
                                   klassen: u.klasse.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, lehrer: [], raum: u.raum)
            }
        }.sorted { ($0.datum, $0.von) < ($1.datum, $1.von) }
    }

    private var gefiltert: [UntisStunde] { klasse.map { k in stunden.filter { $0.klassen.contains(k) } } ?? stunden }
    private var klassen: [String] { Array(Set(stunden.flatMap(\.klassen))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var tage: [String] { Array(Set(stunden.map(\.datum))).sorted() }
    private func name(_ kuerzel: String) -> String { kern.einstellungen.kollegium[kuerzel].map { "\($0) (\(kuerzel))" } ?? kuerzel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Ansicht", selection: $ansicht) { Text("Tag").tag(0); Text("Woche").tag(1); Text("Klassen").tag(2) }
                    .pickerStyle(.segmented)
                if ansicht != 2 && klassen.count > 1 { klassenWahl }
                if !kern.untisFehler.isEmpty { Label(kern.untisFehler, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange).padding(12).glas(16) }
                if stunden.isEmpty {
                    Text("Noch kein Stundenplan. In den Einstellungen WebUntis verbinden oder „Mein Stundenplan“ ausfüllen.")
                        .font(.callout).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(20)
                }
                switch ansicht {
                case 0: tagAnsicht
                case 1: wochenAnsicht
                default: klassenAnsicht
                }
                if let u = kern.untis { Text("WebUntis, Stand \(u.stand.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Stundenplan")
        .refreshable { await kern.untisLaden(erzwingen: true) }
        .onAppear { if !tage.contains(tag), let t = tage.first(where: { $0 >= Zeit.iso(Date()) }) ?? tage.first { tag = t } }
    }

    private var klassenWahl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Alle", klasse == nil) { klasse = nil }
                ForEach(klassen, id: \.self) { k in chip(k, klasse == k) { klasse = k } }
            }
        }
    }

    private func chip(_ t: String, _ an: Bool, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(an ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .background(an ? AnyShapeStyle(kern.farbton.akzent) : AnyShapeStyle(Color.clear), in: Capsule())
        .glas(18)
    }

    // MARK: Tag

    private var tagAnsicht: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tage, id: \.self) { t in
                        let d = Zeit.tag(t) ?? Date()
                        chip(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).day()), tag == t) { tag = t }
                    }
                }
            }
            let heute = gefiltert.filter { $0.datum == tag }
            if heute.isEmpty && !stunden.isEmpty {
                Text(klasse == nil ? "An diesem Tag keine Stunden." : "An diesem Tag keine Stunden in \(klasse!).").foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(20)
            }
            ForEach(Array(heute.enumerated()), id: \.offset) { _, s in stundenKarte(s) }
        }
    }

    private func stundenKarte(_ s: UntisStunde) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Zeit.hhmm(s.von)).font(.headline.monospacedDigit())
                Text(Zeit.hhmm(s.bis)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 56, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(s.entfaellt ? Color.gray : s.foerder ? Color.teal : kern.farbton.akzent).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.fachLang.isEmpty ? s.fach : s.fachLang).font(.title3.weight(.semibold)).strikethrough(s.entfaellt)
                    if s.entfaellt { marke("Entfall", .red) }
                    if s.code == "irregular" { marke("Vertretung", .orange) }
                    if s.foerder { marke("Förderkreis", .teal) }
                }
                Text([s.klassen.joined(separator: ", "), s.raum].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                let andere = s.lehrer.filter { $0.lowercased() != kern.einstellungen.kuerzel.lowercased() }
                if !andere.isEmpty { Label("mit " + andere.map(name).joined(separator: ", "), systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glas(20)
    }

    private func marke(_ t: String, _ f: Color) -> some View {
        Text(t).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3).background(f.opacity(0.2), in: Capsule()).foregroundStyle(f)
    }

    // MARK: Woche (Strichliste je Tag)

    private var wochenAnsicht: some View {
        ForEach(tage, id: \.self) { t in
            let liste = gefiltert.filter { $0.datum == t }
            if !liste.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text((Zeit.tag(t) ?? Date()).formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month())).font(.headline)
                    ForEach(Array(liste.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 10) {
                            Text(Zeit.hhmm(s.von)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                            Text(s.klassen.joined(separator: ", ")).font(.callout.weight(.semibold)).frame(width: 54, alignment: .leading)
                            Text(s.fachLang.isEmpty ? s.fach : s.fachLang).font(.callout).strikethrough(s.entfaellt).lineLimit(1)
                            Spacer(minLength: 4)
                            if s.foerder { Image(systemName: "hands.and.sparkles.fill").foregroundStyle(.teal).font(.caption) }
                            Text(s.raum).font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(s.entfaellt ? .secondary : .primary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glas(20)
            }
        }
    }

    // MARK: Klassen

    @ViewBuilder private var klassenAnsicht: some View {
        if let u = kern.untis {
            ForEach(Untis.klassen(u)) { k in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(k.klasse).font(.title2.weight(.bold))
                        Spacer()
                        Text("\(k.stunden) Std./Woche").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !k.faecher.isEmpty {
                        FlowZeile(k.faecher.map { "\($0.lang.isEmpty ? $0.kurz : $0.lang) · \($0.stunden)" })
                    }
                    Label(k.foerder > 0 ? "Förderkreis: ja (\(k.foerder) Std.)" : "Förderkreis: nein", systemImage: k.foerder > 0 ? "checkmark.circle.fill" : "minus.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(k.foerder > 0 ? .teal : .secondary)
                    if !k.doppel.isEmpty { Label("Doppelbesetzung mit " + k.doppel.map(name).joined(separator: ", "), systemImage: "person.2.fill").font(.subheadline) }
                    if !k.andere.isEmpty {
                        Divider()
                        Text("Außerdem in der Klasse").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(k.andere, id: \.self) { a in
                            HStack {
                                Text(name(a.kuerzel)).font(.callout)
                                Spacer()
                                Text(a.faecher.joined(separator: ", ") + " · \(a.stunden)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if (u.klassen[k.klasse] ?? []).isEmpty {
                        Text("Den Plan der Klasse zeigt WebUntis diesem Konto nicht.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .glas(22)
            }
        } else {
            Text("Die Übersicht nach Klassen (Fächer, Förderkreis, wer noch in der Klasse unterrichtet) braucht WebUntis – in den Einstellungen verbinden.")
                .font(.callout).foregroundStyle(.secondary).padding(16).glas(20)
        }
    }
}

/// Kleine Kapseln, die umbrechen
struct FlowZeile: View {
    let teile: [String]
    init(_ t: [String]) { teile = t }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(teile, id: \.self) { kapsel($0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(teile, id: \.self) { kapsel($0) } }
        }
    }
    private func kapsel(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5).background(.thinMaterial, in: Capsule())
    }
}
