import SwiftUI
import MorgenKern

/// Stundenpläne anderer suchen: Klassen, Lehrkräfte, Räume – mit Favoriten (Herz) und dem eigenen Plan oben
struct UntisSucheAnsicht: View {
    @Bindable var kern: Kern
    @State private var suche = ""

    private var treffer: [UntisElement] {
        let s = suche.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return [] }
        return kern.untisElemente.filter { $0.name.lowercased().contains(s) || $0.lang.lowercased().contains(s) }
            .sorted { $0.typ != $1.typ ? $0.typ < $1.typ : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if !kern.untisSucheHinweis.isEmpty {
                Label(kern.untisSucheHinweis, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if suche.isEmpty {
                Section("Favoriten") {
                    if let ich = kern.ichAlsElement { zeile(ich, ich: true) }
                    ForEach(kern.untisFavoriten.filter { $0.id != kern.ichAlsElement?.id }) { zeile($0) }
                        .onDelete { i in let weg = i.map { kern.untisFavoriten.filter { $0.id != kern.ichAlsElement?.id }[$0] }; kern.untisFavoriten.removeAll { e in weg.contains(e) } }
                    if kern.untisFavoriten.isEmpty { Text("Mit dem Herz merkst du dir Klassen, Lehrkräfte und Räume.").font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach([1, 2, 4], id: \.self) { typ in
                    let liste = kern.untisElemente.filter { $0.typ == typ }
                    if !liste.isEmpty {
                        Section(typ == 1 ? "Klassen" : typ == 2 ? "Lehrkräfte" : "Räume") {
                            DisclosureGroup("\(liste.count) anzeigen") { ForEach(liste) { zeile($0) } }
                        }
                    }
                }
            } else {
                Section("Treffer") {
                    if treffer.isEmpty { Text("Nichts gefunden.").foregroundStyle(.secondary) }
                    ForEach(treffer) { zeile($0) }
                }
            }
        }
        .searchable(text: $suche, prompt: "Klasse, Kürzel oder Raum")
        .overlay { if kern.untisElemente.isEmpty && kern.untisSucheHinweis.isEmpty { ProgressView("Verbinde mit WebUntis …") } }
        .navigationTitle("Stundenpläne")
        .task { await kern.untisSucheVorbereiten() }
    }

    private func zeile(_ e: UntisElement, ich: Bool = false) -> some View {
        NavigationLink { UntisPlanAnsicht(kern: kern, element: e) } label: {
            HStack {
                Image(systemName: ich ? "person.crop.circle.fill" : e.symbol).foregroundStyle(kern.farbton.akzent).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ich ? "Mein Stundenplan" : e.name).font(.body.weight(.semibold))
                    Text(ich ? e.name : (e.lang.isEmpty ? e.art : "\(e.art) · \(e.lang)")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if kern.favorit(e) { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
            }
        }
    }
}

/// Plan einer Klasse, Lehrkraft oder eines Raums: Tag oder Woche, Wochen vor und zurück, Herz zum Merken
struct UntisPlanAnsicht: View {
    @Bindable var kern: Kern
    let element: UntisElement
    @State private var ansicht = 1
    @State private var montag = Untis.montag()
    @State private var tag = Zeit.iso(Date())
    @State private var stunden: [UntisStunde] = []
    @State private var fehler = ""
    @State private var laedt = false

    private var tage: [Date] { (0..<5).compactMap { Zeit.kalender.date(byAdding: .day, value: $0, to: montag) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Ansicht", selection: $ansicht) { Text("Tag").tag(0); Text("Woche").tag(1) }.pickerStyle(.segmented)
                HStack {
                    Button { woche(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }.glas(20)
                    Spacer()
                    Text("Woche ab \(montag.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month(.wide)))").font(.headline)
                    Spacer()
                    Button { woche(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }.glas(20)
                }
                .buttonStyle(.plain)
                if !fehler.isEmpty { Label(fehler, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange).padding(12).glas(16) }
                if laedt { ProgressView().frame(maxWidth: .infinity) }
                if ansicht == 0 { tagAnsicht } else { wochenAnsicht }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle(element.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { kern.favoritUmschalten(element) } label: { Image(systemName: kern.favorit(element) ? "heart.fill" : "heart").foregroundStyle(.pink) }
                    .accessibilityLabel(kern.favorit(element) ? "Aus den Favoriten entfernen" : "Zu den Favoriten")
            }
        }
        .task(id: montag) { await laden() }
        .refreshable { await laden() }
    }

    private func woche(_ d: Int) { montag = Zeit.kalender.date(byAdding: .day, value: 7 * d, to: montag) ?? montag; tag = Zeit.iso(montag) }

    private func laden() async {
        laedt = true; defer { laedt = false }
        do { stunden = try await kern.plan(element, montag: montag); fehler = stunden.isEmpty ? "In dieser Woche keine Stunden." : "" }
        catch { stunden = []; fehler = error.localizedDescription }
        if !tage.map(Zeit.iso).contains(tag) { tag = Zeit.iso(montag) }
    }

    /// Was zu einer Stunde dazugeschrieben wird – je nachdem, wessen Plan das ist
    private func unterzeile(_ s: UntisStunde) -> String {
        var teile: [String] = []
        if element.typ != 1 { teile.append(s.klassen.joined(separator: ", ")) }
        if element.typ != 2 { teile.append(s.lehrer.joined(separator: ", ")) }
        if element.typ != 4 { teile.append(s.raum) }
        return teile.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var tagAnsicht: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tage, id: \.self) { d in
                        let t = Zeit.iso(d)
                        Button { tag = t } label: {
                            Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).day()))
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8).foregroundStyle(tag == t ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .background(tag == t ? AnyShapeStyle(kern.farbton.akzent) : AnyShapeStyle(Color.clear), in: Capsule())
                        .glas(18)
                    }
                }
            }
            ForEach(Array(stunden.filter { $0.datum == tag }.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Zeit.hhmm(s.von)).font(.headline.monospacedDigit())
                        Text(Zeit.hhmm(s.bis)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(width: 56, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 2).fill(s.entfaellt ? Color.gray : s.code == "irregular" ? Color.orange : kern.farbton.akzent).frame(width: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.fachLang.isEmpty ? s.fach : s.fachLang).font(.title3.weight(.semibold)).strikethrough(s.entfaellt)
                            if s.entfaellt { Text("Entfall").font(.caption2.weight(.bold)).foregroundStyle(.red) }
                            if s.code == "irregular" { Text("Vertretung").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
                        }
                        Text(unterzeile(s)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .glas(20)
            }
        }
    }

    /// Woche als Raster: Spalten = Tage, je Stunde ein Kästchen
    private var wochenAnsicht: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(tage, id: \.self) { d in
                let liste = stunden.filter { $0.datum == Zeit.iso(d) }
                VStack(spacing: 6) {
                    Text(d.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).day())).font(.caption.weight(.bold))
                        .foregroundStyle(Zeit.iso(d) == Zeit.iso(Date()) ? kern.farbton.akzent : .primary)
                    ForEach(Array(liste.enumerated()), id: \.offset) { _, s in
                        VStack(spacing: 2) {
                            Text(Zeit.hhmm(s.von)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            Text(s.fach).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7).strikethrough(s.entfaellt)
                            Text(unterzeile(s)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background((s.entfaellt ? Color.gray : s.code == "irregular" ? Color.orange : kern.farbton.akzent).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if liste.isEmpty { Text("–").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(10)
        .glas(20)
    }
}
