import WidgetKit
import SwiftUI
import MorgenKern

/// Hintergrund: „Liquid Glass (wie Apple)“ = ruhiger Systemgrund mit weichem Licht, sonst der Farbverlauf mit Glanz oben links
struct WidgetGrund: View {
    let farbton: Farbton
    @Environment(\.colorScheme) private var modus
    var body: some View {
        ZStack {
            if farbton.systemGrund {
                Color(uiColor: .secondarySystemGroupedBackground)
                LinearGradient(colors: [farbton.akzent.opacity(modus == .dark ? 0.22 : 0.10), .clear], startPoint: .topLeading, endPoint: .center)
            } else {
                LinearGradient(colors: farbton.widget, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Lichtfleck wie auf Glas
            RadialGradient(colors: [.white.opacity(farbton.systemGrund ? (modus == .dark ? 0.06 : 0.35) : 0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
        }
    }
}

struct MorgenWidgetAnsicht: View {
    let e: MorgenEintrag
    /// Nur für die Vorschau in der App (außerhalb eines Widgets gibt es keine Familie)
    var familieVorgabe: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var familie
    @Environment(\.widgetRenderingMode) private var darstellung
    @Environment(\.colorScheme) private var modus

    // MARK: Farben

    /// Volle Farbe (normaler Home-Bildschirm); getönt/klar zeichnet iOS selbst Glas und färbt ein
    private var voll: Bool { darstellung == .fullColor }
    private var hell: Bool { Farbton.zu(e.farbton).systemGrund || !voll }
    private var schrift: Color { hell ? .primary : .white }
    private var leise: Color { hell ? .secondary : .white.opacity(0.75) }
    private let rot = Color(red: 0.92, green: 0.2, blue: 0.2)
    private let orange = Color(red: 0.98, green: 0.55, blue: 0.1)
    private let gruen = Color(red: 0.2, green: 0.72, blue: 0.4)

    private func farbe(_ a: MorgenEintrag.SchulZeile.Art) -> Color {
        switch a { case .rot, .warnung: rot; case .aufsicht: orange; case .gut, .obst: gruen }
    }

    // MARK: Texte

    private var weckText: String { e.wecker?.minuten.map(Zeit.hhmm) ?? "frei" }
    private var weckTag: String {
        guard let w = e.wecker else { return "" }
        return Zeit.kalender.isDateInToday(w.tag) ? "heute" : Zeit.kalender.isDateInTomorrow(w.tag) ? "morgen" : Zeit.wochentag(w.tag)
    }
    private var wochentag: String { Date().formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide)) }
    private var datum: String { Date().formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month(.wide)) }
    private var zahlenDa: Bool { e.kinder != nil || e.stoerungen != nil || e.aufgaben != nil }

    var body: some View {
        if !e.eingerichtet {
            VStack(spacing: 8) {
                Image(systemName: Marke.schule ? "graduationcap.fill" : "sunrise.fill").font(.title).widgetAccentable()
                Text("App öffnen – sie verbindet das Widget").font(.caption.weight(.medium)).multilineTextAlignment(.center)
            }
            .foregroundStyle(schrift)
        } else {
            switch familieVorgabe ?? familie {
            #if os(iOS)
            case .accessoryInline: Text(kopfKurz)
            case .accessoryCircular: rundSperre
            case .accessoryRectangular: rechteckSperre
            #endif
            case .systemMedium: mittel
            case .systemLarge: gross
            case .systemExtraLarge: extragross
            default: klein
            }
        }
    }

    // MARK: Glas-Bausteine

    /// Gläserne Fläche: durchscheinende Füllung, heller Lichtrand oben links, weicher Schatten (nur bei voller Farbe)
    private func glas<S: Shape>(_ form: S, farbe: Color? = nil) -> some View {
        ZStack {
            if let f = farbe, voll {
                form.fill(f.opacity(hell ? 0.16 : 0.85))
            } else {
                form.fill(hell ? AnyShapeStyle(Color.primary.opacity(modus == .dark ? 0.08 : 0.045)) : AnyShapeStyle(Color.white.opacity(voll ? 0.14 : 0.1)))
            }
            form.stroke(LinearGradient(colors: [.white.opacity(hell && modus == .light ? 0.9 : 0.5), .white.opacity(0.04), .white.opacity(hell && modus == .light ? 0.5 : 0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(voll ? (hell ? 0.06 : 0.14) : 0), radius: 5, y: 2)
    }

    /// Glaskarte mit Kopfzeile; antippen öffnet den Bereich in der App
    private func karte<I: View>(_ titel: String, _ symbol: String, ziel: String, akzent: Color? = nil, hoch: Bool = false, @ViewBuilder inhalt: () -> I) -> some View {
        Link(destination: URL(string: Marke.link(ziel))!) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(akzent ?? leise).widgetAccentable()
                    Text(titel).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).foregroundStyle(leise).lineLimit(1).minimumScaleFactor(0.7)
                }
                inhalt()
            }
            .frame(maxWidth: .infinity, maxHeight: hoch ? .infinity : nil, alignment: .topLeading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(glas(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        }
    }

    /// Gläserner Knopf (Kapsel) mit Symbol und Wort
    private func knopf(_ titel: String, _ symbol: String, ziel: String) -> some View {
        Link(destination: URL(string: Marke.link(ziel))!) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).widgetAccentable()
                Text(titel).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(schrift)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(glas(Capsule()))
        }
    }

    /// Runder Glasknopf (nur Symbol)
    private func rundKnopf(_ symbol: String, ziel: String, hilfe: String) -> some View {
        Link(destination: URL(string: Marke.link(ziel))!) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(schrift).widgetAccentable()
                .frame(width: 30, height: 30).background(glas(Circle()))
        }
        .accessibilityLabel(hilfe)
    }

    /// Eine Schul-Zeile: farbige Glasmarke (rot = außerplanmäßig), Text, darüber die ersetzte eigene Stunde rot durchgestrichen
    private func zeile(_ z: MorgenEintrag.SchulZeile, statt: Bool = true) -> some View {
        HStack(spacing: 7) {
            Text(z.marke).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(voll && hell ? farbe(z.art) : .white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(minWidth: 28, minHeight: 20).padding(.horizontal, 2)
                .background(glas(RoundedRectangle(cornerRadius: 7, style: .continuous), farbe: farbe(z.art)))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                if statt, let s = z.statt {
                    Text(s).font(.system(size: 10)).strikethrough(true, color: rot).foregroundStyle(leise).lineLimit(1)
                }
                Text(z.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(schrift).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Kopf

    /// Links oben: DammAPP der Schultag (Wochentag groß), GutenMorgen der Wecker
    private func kopf(gross: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if Marke.schule {
                Label(gross ? "Schule \(e.schulName)" : e.schulName.capitalized, systemImage: "graduationcap.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(leise).lineLimit(1)
                Text(wochentag).font(.system(size: gross ? 30 : 24, weight: .bold, design: .rounded)).foregroundStyle(schrift).minimumScaleFactor(0.6).lineLimit(1)
                if gross { Text(datum).font(.caption.weight(.medium)).foregroundStyle(leise) }
            } else {
                Label(gross ? "Wecker \(weckTag)" : weckTag.capitalized, systemImage: "alarm.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(leise).lineLimit(1)
                Text(weckText).font(.system(size: gross ? 40 : 32, weight: .bold, design: .rounded)).foregroundStyle(schrift).minimumScaleFactor(0.6).lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder private func wetter(gross: Bool) -> some View {
        if let w = e.wetter, let t = w.heute {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(voll ? SymbolRenderingMode.multicolor : SymbolRenderingMode.hierarchical).font(.system(size: gross ? 22 : 15))
                    Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.system(size: gross ? 20 : 15, weight: .semibold, design: .rounded)).foregroundStyle(schrift)
                }
                if gross { Text("\(Int(t.min.rounded()))° / \(Int(t.max.rounded()))° · ☂︎ \(t.regen) %").font(.system(size: 10, weight: .medium)).foregroundStyle(leise) }
            }
        }
    }

    /// Großer Zustand: wie viel heute außerplanmäßig ist – oder „nach Plan“
    private var zustand: some View {
        let n = e.rotZahl
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if e.vertretung == nil {
                Text("Kein Plan").font(.system(size: 15, weight: .semibold)).foregroundStyle(leise)
            } else if n > 0 {
                Text("\(n)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(voll ? rot : schrift).widgetAccentable()
                Text("außer Plan").font(.system(size: 12, weight: .semibold)).foregroundStyle(leise)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(voll ? gruen : schrift).widgetAccentable()
                Text("nach Plan").font(.system(size: 13, weight: .semibold)).foregroundStyle(schrift)
            }
        }
    }

    // MARK: Teile

    /// [mitMensa]: das Essen als letzte Zeile (spart im großen Widget eine eigene Karte)
    private func schulKarte(_ max: Int, hoch: Bool = false, mitMensa: Bool = false) -> some View {
        karte("Schule " + e.schulName, "graduationcap.fill", ziel: "vertretung", akzent: e.rotZahl > 0 ? rot : nil, hoch: hoch) {
            let z = e.schulZeilen
            if z.isEmpty { Text("Noch kein Vertretungsplan").font(.caption).foregroundStyle(leise) }
            ForEach(Array(z.prefix(max).enumerated()), id: \.offset) { _, x in zeile(x) }
            if z.count > max { Text("+ \(z.count - max) weitere").font(.system(size: 10, weight: .medium)).foregroundStyle(leise) }
            if mitMensa, let m = e.essen {
                HStack(spacing: 7) {
                    Image(systemName: "fork.knife").font(.system(size: 10, weight: .bold)).foregroundStyle(voll ? gruen : schrift).frame(width: 32)
                    Text(m).font(.system(size: 12, weight: .semibold)).foregroundStyle(schrift).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var mensaKarte: some View {
        if let m = e.essen {
            karte("Mensa " + e.schulName, "fork.knife", ziel: "mensa", akzent: gruen) {
                Text(m).font(.system(size: 12, weight: .semibold)).foregroundStyle(schrift).lineLimit(2)
            }
        }
    }

    private func termineKarte(_ max: Int) -> some View {
        karte(e.kontext == .frei ? "Termine" : "Termine " + e.schulName, "calendar", ziel: "termine", akzent: rot) {
            if e.heute.isEmpty { Text("Keine Termine").font(.caption).foregroundStyle(leise) }
            ForEach(Array(e.heute.prefix(max).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Text(t.ganztags ? "ganzt." : t.start.uhrzeit).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(leise).frame(width: 40, alignment: .leading)
                    Text(t.titel).font(.system(size: 12, weight: .semibold)).foregroundStyle(schrift).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var postKarte: some View {
        if !e.post.isEmpty {
            karte("Post & Pakete", "shippingbox.fill", ziel: "post", akzent: .blue) { Text(e.post).font(.caption).foregroundStyle(schrift).lineLimit(2) }
        }
    }

    /// Abwesend · Störungen · Aufgaben als drei gleich große Glaskacheln mit großer Zahl
    private var zahlen: some View {
        HStack(spacing: 6) {
            if let k = e.kinder {
                zahlKachel("Abwesend", "person.crop.circle.badge.xmark", ziel: "abwesend", zahl: e.fehlen?.zahl ?? "\(k.count)",
                           unter: e.fehlen.map { $0.text.hasPrefix("krank") } == true ? e.fehlen!.text : (k.isEmpty ? "niemand" : k.prefix(2).joined(separator: ", ")))
            }
            if let s = e.stoerungen { zahlKachel("Störungen", "wrench.and.screwdriver.fill", ziel: "stoerungen", zahl: "\(s)", unter: "offen") }
            if let a = e.aufgaben { zahlKachel("Aufgaben", "checklist", ziel: "aufgaben", zahl: "\(a)", unter: "offen") }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func zahlKachel(_ titel: String, _ symbol: String, ziel: String, zahl: String, unter: String) -> some View {
        karte(titel, symbol, ziel: ziel, hoch: true) {
            Text(zahl).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(schrift).lineLimit(1).minimumScaleFactor(0.6).widgetAccentable()
            Text(unter).font(.system(size: 10)).foregroundStyle(leise).lineLimit(1)
        }
    }

    private var knoepfe: some View {
        HStack(spacing: 6) {
            knopf("Stundenplan", "calendar.day.timeline.left", ziel: "stundenplan")
            knopf("Vertretung", "arrow.triangle.swap", ziel: "vertretung")
            knopf("Mensa", "fork.knife", ziel: "mensa")
        }
    }

    // MARK: Größen

    private var klein: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) { kopf(gross: false); Spacer(minLength: 2); wetter(gross: false) }
            Spacer(minLength: 0)
            if Marke.schule || e.kontext == .schule { zustand }
            if let z = e.schulZeilen.first(where: { $0.art != .gut }) ?? e.schulZeilen.first { zeile(z, statt: false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mittel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                kopf(gross: false)
                wetter(gross: false)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    rundKnopf("calendar.day.timeline.left", ziel: "stundenplan", hilfe: "Stundenplan")
                    rundKnopf("fork.knife", ziel: "mensa", hilfe: "Speiseplan")
                    if zahlenDa { rundKnopf("person.crop.circle.badge.xmark", ziel: "abwesend", hilfe: "Abwesenheiten") }
                    else { rundKnopf("arrow.triangle.swap", ziel: "vertretung", hilfe: "Vertretung") }
                }
            }
            .frame(width: 112, alignment: .leading)
            VStack(spacing: 6) {
                if e.kontext != .schule, e.termin != nil || !e.post.isEmpty {
                    if let t = e.termin {
                        karte("Termin", "calendar", ziel: "termine", akzent: rot) { Text("\(t.start.uhrzeit) \(t.titel)").font(.system(size: 12, weight: .semibold)).foregroundStyle(schrift).lineLimit(2) }
                    }
                    postKarte
                } else {
                    schulKarte(e.essen == nil ? 4 : 2, hoch: e.essen == nil)
                    mensaKarte
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var gross: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                kopf(gross: true); Spacer()
                VStack(alignment: .trailing, spacing: 0) { wetter(gross: false); if Marke.schule || e.kontext == .schule { zustand } }
            }
            if e.kontext == .schule {
                schulKarte(zahlenDa ? 2 : 4, mitMensa: true)
                if zahlenDa { zahlen } else { termineKarte(2) }
            } else {
                termineKarte(3)
                postKarte
                schulKarte(2)
            }
            Spacer(minLength: 0)
            knoepfe
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// iPad: links der Schultag, rechts Mensa, Zahlen, Termine und Post
    private var extragross: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) { kopf(gross: true); Spacer(); zustand.padding(.trailing, 12); wetter(gross: true) }
            HStack(alignment: .top, spacing: 10) {
                schulKarte(7, hoch: true)
                VStack(spacing: 8) {
                    mensaKarte
                    if zahlenDa { zahlen }
                    termineKarte(3)
                    postKarte
                    Spacer(minLength: 0)
                }
            }
            knoepfe
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Sperrbildschirm

    private var kopfKurz: String {
        Marke.schule ? (e.schulZeilen.first.map { "\($0.marke) \($0.text)" } ?? "Schule \(e.schulName)") : "⏰ \(weckText) \(weckTag)"
    }

    private var rundSperre: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: Marke.schule ? (e.rotZahl > 0 ? "exclamationmark.circle.fill" : "graduationcap.fill") : "alarm.fill").font(.system(size: 12, weight: .semibold))
                Text(Marke.schule ? (e.rotZahl > 0 ? "\(e.rotZahl)" : "✓") : weckText).font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
            }
            .widgetAccentable()
        }
    }

    private var rechteckSperre: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: Marke.schule ? "graduationcap.fill" : "alarm.fill")
                Text(Marke.schule ? "Schule \(e.schulName)" : "\(weckText) \(weckTag)")
                if Marke.schule, e.rotZahl > 0 { Text("· \(e.rotZahl) außer Plan") }
            }
            .font(.headline).widgetAccentable().lineLimit(1)
            if let s = e.schulZeilen.first { Text("\(s.marke) \(s.text)").font(.caption).lineLimit(1) }
            if let m = e.essen { Text("🍽 \(m)").font(.caption).lineLimit(1) }
            else if let t = e.termin { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
