import SwiftUI
import MorgenKern

/// Post & Pakete (aus der Home-Assistant-Integration, wie in der App Post & Pakete): heute, unterwegs, zugestellt, Briefe mit Bild
struct PostAnsicht: View {
    @Bindable var kern: Kern
    @State private var brief: PostStand.Brief?
    @State private var bild: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !kern.ha.eingerichtet {
                    hinweis("Erst Home Assistant in den Einstellungen verbinden – Post & Pakete kommen aus der Integration „Briefankündigung“.")
                } else if let p = kern.postStand {
                    let g = p.gruppen()
                    kopf(p, g)
                    if !g.heute.isEmpty { abschnitt("Heute") { ForEach(g.heute) { paket($0) } } }
                    if !g.unterwegs.isEmpty { abschnitt("Unterwegs") { ForEach(g.unterwegs) { paket($0) } } }
                    let offen = p.briefe.filter { !$0.erledigt }
                    if !offen.isEmpty { abschnitt("Briefe") { ForEach(offen) { briefZeile($0) } } }
                    if !g.zugestellt.isEmpty { abschnitt("Zugestellt (14 Tage)") { ForEach(g.zugestellt) { paket($0) } } }
                    if g.heute.isEmpty && g.unterwegs.isEmpty && offen.isEmpty { hinweis("Gerade ist nichts unterwegs.") }
                } else {
                    hinweis(kern.postFehler.isEmpty ? "Lädt …" : kern.postFehler)
                }
            }
            .padding()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Post & Pakete")
        .refreshable { await kern.postLaden() }
        .task { if kern.postStand == nil { await kern.postLaden() } }
        .sheet(item: $brief) { b in
            NavigationStack {
                ScrollView {
                    if let i = bild { Image(uiImage: i).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16)).padding() }
                    else if b.bild { ProgressView().padding(40) }
                    else { Text("Kein Bild des Umschlags.").foregroundStyle(.secondary).padding(40) }
                }
                .navigationTitle(b.absender.isEmpty ? "Brief" : b.absender).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig") { brief = nil } }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Angekommen") { Task { _ = await kern.ha.erledigt(b.id, true); brief = nil; await kern.postLaden() } }
                    }
                }
            }
            .task { bild = nil; if b.bild, let d = await kern.ha.briefBild(b.id) { bild = UIImage(data: d) } }
            .presentationDetents([.medium, .large])
        }
    }

    private func hinweis(_ t: String) -> some View {
        Text(t).font(.callout).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(20)
    }

    private func kopf(_ p: PostStand, _ g: (heute: [PostStand.Paket], unterwegs: [PostStand.Paket], zugestellt: [PostStand.Paket])) -> some View {
        HStack(spacing: 10) {
            zahl(g.heute.count, "heute", "shippingbox.fill", .orange)
            zahl(g.unterwegs.count, "unterwegs", "truck.box.fill", .blue)
            zahl(p.briefe.filter { !$0.erledigt }.count, "Briefe", "envelope.fill", .purple)
        }
    }

    private func zahl(_ n: Int, _ t: String, _ s: String, _ f: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) { Image(systemName: s).foregroundStyle(f); Text("\(n)").font(.title2.weight(.bold).monospacedDigit()) }
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).glas(16)
    }

    private func abschnitt<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel).font(.headline).padding(.leading, 4)
            inhalt()
        }
    }

    private func symbol(_ p: PostStand.Paket) -> (String, Color) {
        if p.problem { return ("exclamationmark.triangle.fill", .red) }
        switch p.stand {
        case "zugestellt": return ("checkmark.circle.fill", .green)
        case "abholbereit": return ("mappin.circle.fill", .orange)
        case "zustellung": return ("truck.box.fill", .orange)
        default: return ("shippingbox.fill", .blue)
        }
    }

    private func paket(_ p: PostStand.Paket) -> some View {
        let (s, f) = symbol(p)
        return NavigationLink {
            PaketDetail(paket: p, kern: kern)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: s).font(.title2).foregroundStyle(f).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.titel).font(.body.weight(.semibold)).lineLimit(1)
                    Text([p.dienst, p.statusText.isEmpty ? p.stand.capitalized : p.statusText].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if !p.erwartet.isEmpty || !p.zeitfenster.isEmpty { Text("Erwartet: " + [p.erwartet, p.zeitfenster].filter { !$0.isEmpty }.joined(separator: ", ")).font(.caption).foregroundStyle(.orange) }
                    if !p.abholcode.isEmpty { Text("Abholcode \(p.abholcode)").font(.callout.monospaced().weight(.bold)).foregroundStyle(.orange) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .glas(20)
        }
        .buttonStyle(.plain)
    }

    private func briefZeile(_ b: PostStand.Brief) -> some View {
        Button { brief = b } label: {
            HStack(spacing: 12) {
                Image(systemName: b.wichtig ? "envelope.badge.fill" : "envelope.fill").font(.title3).foregroundStyle(b.wichtig ? .red : .purple).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.absender.isEmpty ? "Brief" : b.absender).font(.body.weight(.semibold))
                    Text(b.datum.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if b.bild { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .padding(14)
            .glas(20)
        }
        .buttonStyle(.plain)
    }
}

/// Ein Paket mit Verlauf, Abholcode und „Erledigt“
struct PaketDetail: View {
    let paket: PostStand.Paket
    @Bindable var kern: Kern
    @Environment(\.dismiss) private var zurueck

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(paket.titel).font(.title2.weight(.bold))
                    Text([paket.dienst, paket.statusText].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                    if !paket.nummer.isEmpty { Text(paket.nummer).font(.callout.monospaced()).textSelection(.enabled) }
                    if !paket.erwartet.isEmpty || !paket.zeitfenster.isEmpty { Label([paket.erwartet, paket.zeitfenster].filter { !$0.isEmpty }.joined(separator: ", "), systemImage: "clock").foregroundStyle(.orange) }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22)
                if !paket.abholcode.isEmpty || !paket.abholort.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !paket.abholcode.isEmpty { Text(paket.abholcode).font(.system(size: 34, weight: .bold, design: .monospaced)).textSelection(.enabled) }
                        if !paket.abholort.isEmpty { Label(paket.abholort, systemImage: "mappin.and.ellipse") }
                        if !paket.abholfrist.isEmpty { Label("Abholen bis \(paket.abholfrist)", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.red) }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22, farbe: .orange)
                }
                if !paket.notiz.isEmpty { Label(paket.notiz, systemImage: "note.text").padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(20) }
                if !paket.ereignisse.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Verlauf").font(.headline)
                        ForEach(Array(paket.ereignisse.enumerated()), id: \.offset) { i, e in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(i == 0 ? Color.orange : Color.secondary.opacity(0.4)).frame(width: 10, height: 10).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.text).font(.callout)
                                    Text([e.zeit?.formatted(date: .abbreviated, time: .shortened) ?? "", e.ort].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glas(22)
                }
                if !paket.zugestellt {
                    Button { Task { _ = await kern.ha.erledigt(paket.id, true); await kern.postLaden(); zurueck() } } label: {
                        Label("Als zugestellt markieren", systemImage: "checkmark.circle").frame(maxWidth: .infinity).padding(12)
                    }
                    .buttonStyle(.plain).glas(18, farbe: .green)
                }
            }
            .padding()
        }
        .background(Hintergrund(farbton: kern.farbton))
        .navigationTitle("Paket")
        .navigationBarTitleDisplayMode(.inline)
    }
}
