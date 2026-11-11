import WidgetKit
import SwiftUI
import EventKit
import CoreLocation
import MorgenKern
#if os(iOS)
import ActivityKit
#endif

@main
struct MorgenWidgets: WidgetBundle {
    var body: some Widget {
        MorgenWidget()
        SchultagWidget()
        #if os(iOS)
        UebergabeWidget()
        SchulTagLiveWidget()
        #endif
    }
}

struct MorgenEintrag: TimelineEntry {
    let date: Date
    var eingerichtet: Bool
    var wecker: Weckzeit?
    var wetter: Wetter?
    var termin: Termin?
    var post = ""
    /// Termine des Schultags (heute bzw. ab 16 Uhr morgen)
    var heute: [Termin] = []
    var vertretung: VertretungsPlan?
    var haeuser: [String: [String]] = [:]
    var mensa: MensaTag?
    var mensaWahl: (String, String) = ("", "")
    var gemerkt: ([String], [String]) = ([], [])
    var obst = false
    var farbton = "morgenrot"
    /// „heute“, „morgen“ oder „Montag“
    var schulName = "heute"
    /// Kinder, die fehlen (schon mit Sichtschutz), offene Störungen, offene Aufgaben – nil = Modul aus
    var kinder: [String]?
    var stoerungen: Int?
    var aufgaben: Int?
    /// Schule zuerst oder (zu Hause, am Wochenende) Termine und Post zuerst
    var kontext: Kontext = .schule

    /// Kurze Schul-Zeilen: „2. Vertretung 2c · Haus 2“, „1.P Aufsicht Hof“, „🍎 Schulobst“
    var schulZeilen: [(marke: String, text: String)] {
        var z: [(marke: String, text: String)] = []
        if let v = vertretung {
            if v.fehlt { z.append(("⚠️", "Als fehlend eingetragen")) }
            for s in v.stunden {
                let h = Vertretung.haus(s.klasse, haeuser)
                z.append((Int(s.stunde) != nil ? "\(s.stunde)." : String(s.stunde.prefix(3)), "Vertretung \(s.klasse)" + (h.isEmpty ? "" : " · \(h)")))
            }
            for p in v.pausen { z.append((String(p.pause.prefix(1)) + ".P", (p.reserve ? "Reserve " : "Aufsicht ") + p.ort)) }
            if v.stunden.isEmpty && v.pausen.isEmpty && !v.fehlt { z.append(("✓", "Keine Vertretung")) }
        }
        if obst { z.append(("🍎", "Schulobst")) }
        return z
    }
    var essen: String? {
        guard let m = mensa else { return nil }
        if let f = m.frei { return "Mensa zu" + (f.isEmpty ? "" : " (\(f))") }
        return m.haupt(favoriten: mensaWahl.0, meiden: mensaWahl.1, gut: gemerkt.0, schlecht: gemerkt.1).map { ($0.bestellt ? "✓ " : "") + $0.text }
    }
}

/// Ohne Einstellungen pro Widget (StaticConfiguration) – die starten auch in neu signierten Apps.
struct MorgenZeitleiste: TimelineProvider {
    func placeholder(in context: Context) -> MorgenEintrag {
        var p = VertretungsPlan(); p.stunden = [.init(stunde: "2", klasse: "2c")]; p.pausen = [.init(pause: "2. Pause", ort: "Hof")]
        return MorgenEintrag(date: Date(), eingerichtet: true, wecker: Weckzeit(minuten: 375, grund: "", tag: Weckzeit.naechsterTag()),
                             wetter: Wetter(jetzt: 6, jetztCode: 2, heute: WetterTag(code: 2, max: 9, min: 3, regen: 10, wind: 10), morgen: nil, stand: Date()),
                             vertretung: p, mensa: MensaTag(datum: Zeit.iso(Date()), gerichte: [Gericht(menue: "Menü 1", text: "Spaghetti Bolognese")]), obst: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (MorgenEintrag) -> Void) { completion(placeholder(in: context)) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorgenEintrag>) -> Void) {
        Task {
            let e = await eintrag()
            // 7:00–7:50 alle 10 Minuten (versetzt), um 16 Uhr auf morgen umschalten, sonst stündlich
            completion(Timeline(entries: [e], policy: .after(Takt.naechste(nach: Date()))))
        }
    }

    private func eintrag() async -> MorgenEintrag {
        guard let paar = WidgetSpeicher.einstellungen() else { return MorgenEintrag(date: Date(), eingerichtet: false) }
        let (e, token, geheim) = paar
        let d = UserDefaults.standard
        let jetzt = Date()
        let stand = { (schluessel: String) in jetzt.timeIntervalSince1970 - d.double(forKey: schluessel) }
        // freie Tage höchstens alle 3 Tage holen
        var frei = (d.data(forKey: "frei")).flatMap { try? JSONDecoder().decode([FreierTag].self, from: $0) } ?? []
        if stand("freiStand") > 86400 * 3 || frei.isEmpty, let neu = try? await FreieTage.laden(bundesland: e.bundesland) {
            frei = neu
            d.set(try? JSONEncoder().encode(neu), forKey: "frei")
            d.set(jetzt.timeIntervalSince1970, forKey: "freiStand")
        }
        let schulTag = Tagwahl.ziel(jetzt, frei: frei)
        let ziel = Zeit.iso(schulTag)
        // Termine (falls die Kalender-Erlaubnis der App auch fürs Widget gilt)
        var termine: [Termin] = []
        if e.termine, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let s = EKEventStore()
            let von = Zeit.kalender.startOfDay(for: jetzt)
            let p = s.predicateForEvents(withStart: von, end: von.addingTimeInterval(4 * 86400), calendars: nil)
            termine = s.events(matching: p).map { Termin(titel: $0.title ?? "Termin", start: $0.startDate, ganztags: $0.isAllDay) }
        }
        let tag = Weckzeit.naechsterTag()
        let wecker = Weckzeit.berechne(tag: tag, termine: termine, frei: FreieTage.am(frei, tag), e: e)
        let ha = HomeAssistant(adresse: e.haAdresse, token: token)
        async let w = try? Wetter.laden(lat: e.lat, lon: e.lon)
        async let p: String = e.post && ha.eingerichtet ? ha.postHeute() : ""
        let naechster = termine.filter { !$0.ganztags && $0.start > jetzt }.min { $0.start < $1.start }
        let tagesTermine = termine.filter { Zeit.kalender.isDate($0.start, inSameDayAs: schulTag) && ($0.ganztags || $0.start > jetzt) }.sorted { $0.start < $1.start }

        // Vertretung: im Morgenfenster bei jedem Takt, sonst höchstens alle 30 Minuten – und sofort, wenn der Tag wechselt (16 Uhr)
        var plan = d.data(forKey: "vertretung").flatMap { try? JSONDecoder().decode(VertretungsPlan.self, from: $0) }
        if d.string(forKey: "vertretungZiel") != ziel { plan = nil }
        if e.vertretung, !e.vertretungLink.isEmpty, !e.kuerzel.isEmpty,
           plan == nil || stand("vertretungStand") > (Takt.morgenFenster(jetzt) ? 300 : 1800) {
            if let neu = try? await Vertretung.laden(link: e.vertretungLink, kuerzel: e.kuerzel, passwort: geheim.freigabe, ziel: ziel) {
                plan = neu
                d.set(try? JSONEncoder().encode(neu), forKey: "vertretung")
                d.set(ziel, forKey: "vertretungZiel")
            }
            d.set(jetzt.timeIntervalSince1970, forKey: "vertretungStand")
        }
        // Kantine: Plan (zwei Wochen) einmal am Tag; fehlt der Schultag, höchstens stündlich neu versuchen
        var mensaPlan = d.data(forKey: "mensaPlan").flatMap { try? JSONDecoder().decode(MensaPlan.self, from: $0) }
        let mensaAlt = mensaPlan.map { !Zeit.kalender.isDateInToday($0.stand) } ?? true
        if e.mensaBereit, !geheim.mensa.isEmpty, mensaAlt || mensaPlan?.tag(ziel) == nil, stand("mensaVersuch") > 3600,
           Mensa.darfAnmelden(d, benutzer: e.mensaBenutzer, passwort: geheim.mensa) {
            d.set(jetzt.timeIntervalSince1970, forKey: "mensaVersuch")
            do {
                let neu = try await Mensa.ladePlan(adresse: e.mensaAdresse, benutzer: e.mensaBenutzer, passwort: geheim.mensa)
                mensaPlan = neu
                d.set(try? JSONEncoder().encode(neu), forKey: "mensaPlan")
                Mensa.merke(d, fehler: nil, benutzer: e.mensaBenutzer, passwort: geheim.mensa)
            } catch { Mensa.merke(d, fehler: error, benutzer: e.mensaBenutzer, passwort: geheim.mensa) }
        }
        // Schulobst: Kalender höchstens alle 12 Stunden
        var obstTage = Set(d.stringArray(forKey: "obst") ?? [])
        if e.obstBereit, stand("obstStand") > 12 * 3600, let neu = try? await SchulKalender.laden(e.obstKalender) {
            obstTage = neu
            d.set(Array(neu), forKey: "obst")
            d.set(jetzt.timeIntervalSince1970, forKey: "obstStand")
        }
        // IServ (Abwesenheiten, Störungen): höchstens alle 30 Minuten; ohne 2FA-Schlüssel nur, solange die Sitzung hält
        let iz = IServZugang(server: e.iservServer, benutzer: e.iservBenutzer, passwort: geheim.iserv, totp: geheim.totp)
        let merkmal = Mensa.merkmal(e.iservServer + "|" + e.iservBenutzer, geheim.iserv)
        var abw = d.data(forKey: "abwesend").flatMap { try? JSONDecoder().decode(AbwesenheitenStand.self, from: $0) }
        var stoe = d.data(forKey: "stoerungen").flatMap { try? JSONDecoder().decode(StoerungenStand.self, from: $0) }
        if (e.abwesenheiten || e.stoerungen), iz.vollstaendig, d.string(forKey: "iservAbgelehnt") != merkmal, stand("iservStand") > (Takt.morgenFenster(jetzt) ? 600 : 1800) {
            d.set(jetzt.timeIntervalSince1970, forKey: "iservStand")
            let s = IServ(iz, erlaubteHosts: Set(e.iservHosts))
            do {
                if e.abwesenheiten {
                    let (st, _) = try await Abwesenheiten.laden(s, quelle: e.abwesendQuelle)
                    abw = st; d.set(try? JSONEncoder().encode(st), forKey: "abwesend")
                }
                if e.stoerungen {
                    let (st, _) = try await Stoerungen.laden(s, quelle: e.stoerungQuelle)
                    stoe = st; d.set(try? JSONEncoder().encode(st), forKey: "stoerungen")
                }
            } catch IServFehler.zugangsdaten(_) { d.set(merkmal, forKey: "iservAbgelehnt") } catch {}
        }
        // Aufgaben: höchstens alle 3 Stunden
        var auf = d.data(forKey: "aufgaben").flatMap { try? JSONDecoder().decode(AufgabenStand.self, from: $0) }
        if e.aufgaben, !geheim.edupool.isEmpty, stand("aufgabenStand") > 3 * 3600 {
            d.set(jetzt.timeIntervalSince1970, forKey: "aufgabenStand")
            if let st = try? await Aufgaben.laden(token: geheim.edupool, farbe: e.aufgabenFarbe) { auf = st; d.set(try? JSONEncoder().encode(st), forKey: "aufgaben") }
        }
        if e.mitteilungen { Melder.pruefen(stoerungen: e.stoerungen ? stoe : nil, aufgaben: e.aufgaben ? auf : nil) }
        // Standort (falls erlaubt): in der Schule die Schul-Infos, zu Hause und am Wochenende Termine und Post zuerst
        var hier: Kontext.Ort?
        let ortung = CLLocationManager()
        if ortung.isAuthorizedForWidgetUpdates, let l = ortung.location { hier = Kontext.Ort(lat: l.coordinate.latitude, lon: l.coordinate.longitude) }
        let kontext = Kontext.bestimme(jetzt: jetzt, frei: frei, hier: hier, schule: e.schulOrt, zuhause: e.zuhauseOrt)
        let kinder = abw.map { Abwesenheiten.amTag($0.eintraege, ziel: schulTag, klassen: e.klassenListe).map { e.sichtschutz ? Abwesenheiten.kurzName($0.name) : $0.name } }
        return MorgenEintrag(date: jetzt, eingerichtet: true, wecker: wecker, wetter: await w, termin: naechster, post: await p,
                             heute: tagesTermine, vertretung: e.vertretung ? plan : nil, haeuser: e.haeuser,
                             mensa: e.mensa ? mensaPlan?.tag(ziel) : nil, mensaWahl: (e.favoriten, e.meiden), gemerkt: (e.lieblingsGerichte, e.nichtLecker),
                             obst: e.obstBereit && obstTage.contains(ziel), farbton: e.farbton, schulName: Tagwahl.name(schulTag, jetzt: jetzt),
                             kinder: e.abwesenheiten ? kinder : nil, stoerungen: e.stoerungen ? stoe?.offen.count : nil, aufgaben: e.aufgaben ? auf?.offen.count : nil,
                             kontext: kontext)
    }
}

struct MorgenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "morgen", provider: MorgenZeitleiste()) { e in
            MorgenWidgetAnsicht(e: e).containerBackground(for: .widget) {
                LinearGradient(colors: Farbton.zu(e.farbton).widget, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "gutenmorgen://start"))
        }
        .configurationDisplayName("Guten Morgen")
        .description("Wecker, Wetter, Vertretung, Hofaufsicht, Mensa, Schulobst, Termine und Post – ab 16 Uhr schon für morgen.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
        #endif
    }
}

struct MorgenWidgetAnsicht: View {
    let e: MorgenEintrag
    @Environment(\.widgetFamily) private var familie

    var weckText: String { e.wecker?.minuten.map(Zeit.hhmm) ?? "frei" }
    var weckTag: String {
        guard let w = e.wecker else { return "" }
        return Zeit.kalender.isDateInToday(w.tag) ? "heute" : Zeit.kalender.isDateInTomorrow(w.tag) ? "morgen" : Zeit.wochentag(w.tag)
    }
    var schulTitel: String { "Schule " + e.schulName }

    var body: some View {
        if !e.eingerichtet {
            VStack(spacing: 6) {
                Image(systemName: "sunrise.fill").font(.title)
                Text("App öffnen – sie verbindet das Widget").font(.caption).multilineTextAlignment(.center)
            }.foregroundStyle(.white)
        } else {
            switch familie {
            #if os(iOS)
            case .accessoryInline: Text("⏰ \(weckText) \(weckTag)")
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "alarm.fill").font(.caption); Text(weckText).font(.system(size: 13, weight: .bold)).minimumScaleFactor(0.6) }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("⏰ \(weckText) \(weckTag)").font(.headline)
                    if let s = e.schulZeilen.first { Text("\(s.marke) \(s.text)").font(.caption).lineLimit(1) }
                    if let m = e.essen { Text("🍽 \(m)").font(.caption).lineLimit(1) }
                    else if let t = e.termin { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption).lineLimit(1) }
                }
            #endif
            case .systemMedium: mittel
            case .systemLarge, .systemExtraLarge: gross
            default: klein
            }
        }
    }

    // MARK: Bausteine

    /// Ein klar abgegrenzter Kasten mit Kopfzeile; antippen öffnet den Bereich in der App
    private func kasten<I: View>(_ titel: String, _ symbol: String, ziel: String, @ViewBuilder inhalt: () -> I) -> some View {
        Link(destination: URL(string: "gutenmorgen://\(ziel)")!) {
            VStack(alignment: .leading, spacing: 3) {
                Label(titel, systemImage: symbol).font(.system(size: 10, weight: .bold)).textCase(.uppercase).opacity(0.75)
                inhalt()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func schulZeile(_ z: (marke: String, text: String)) -> some View {
        HStack(spacing: 6) {
            Text(z.marke).font(.system(size: 11, weight: .bold, design: .rounded)).frame(minWidth: 26, minHeight: 18)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(z.text).font(.caption.weight(.semibold)).lineLimit(1)
        }
    }

    private var weckerBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) { Image(systemName: "alarm.fill"); Text("Wecker \(weckTag)") }.font(.caption.weight(.semibold)).opacity(0.85)
            Text(weckText).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder private var wetterBlock: some View {
        if let w = e.wetter, let t = w.heute {
            HStack(spacing: 5) {
                Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(.multicolor)
                Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.headline)
                Text("\(Int(t.min.rounded()))–\(Int(t.max.rounded()))°").font(.caption).opacity(0.85)
            }
        }
    }

    /// Kinder fehlen · Störungen · Aufgaben – je ein Kasten, antippen öffnet die Liste
    private var zahlen: some View {
        HStack(spacing: 6) {
            if let k = e.kinder {
                kasten("Fehlen", "person.crop.circle.badge.xmark", ziel: "abwesend") {
                    Text("\(k.count)").font(.headline.monospacedDigit())
                    if !k.isEmpty { Text(k.prefix(2).joined(separator: ", ")).font(.caption2).lineLimit(1).opacity(0.85) }
                }
            }
            if let s = e.stoerungen { kasten("Störungen", "wrench.and.screwdriver.fill", ziel: "stoerungen") { Text("\(s)").font(.headline.monospacedDigit()) } }
            if let a = e.aufgaben { kasten("Aufgaben", "checklist", ziel: "aufgaben") { Text("\(a)").font(.headline.monospacedDigit()) } }
        }
    }

    // MARK: Größen

    private var klein: some View {
        VStack(alignment: .leading, spacing: 4) {
            weckerBlock
            Spacer(minLength: 0)
            if let z = e.schulZeilen.first { schulZeile(z) } else { wetterBlock }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mittel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                weckerBlock
                Spacer(minLength: 0)
                wetterBlock
            }
            .frame(width: 112, alignment: .leading)
            VStack(spacing: 6) {
                if e.kontext != .schule {
                    if let t = e.termin { kasten("Termin", "calendar", ziel: "termine") { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption.weight(.semibold)).lineLimit(2) } }
                    if !e.post.isEmpty { kasten("Post", "shippingbox.fill", ziel: "post") { Text(e.post).font(.caption).lineLimit(e.termin == nil ? 4 : 2) } }
                }
                if e.kontext == .schule || (e.termin == nil && e.post.isEmpty), !e.schulZeilen.isEmpty {
                    kasten(schulTitel, "graduationcap.fill", ziel: "vertretung") { ForEach(Array(e.schulZeilen.prefix(e.essen == nil ? 4 : 2).enumerated()), id: \.offset) { _, z in schulZeile(z) } }
                }
                if e.kontext == .schule, let m = e.essen { kasten("Mensa", "fork.knife", ziel: "mensa") { Text(m).font(.caption.weight(.semibold)).lineLimit(2) } }
                if e.kontext == .schule && e.schulZeilen.isEmpty && e.essen == nil {
                    if let t = e.termin { kasten("Termin", "calendar", ziel: "termine") { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption.weight(.semibold)).lineLimit(2) } }
                    if !e.post.isEmpty { kasten("Post", "shippingbox.fill", ziel: "post") { Text(e.post).font(.caption).lineLimit(3) } }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    private var zahlenDa: Bool { e.kinder != nil || e.stoerungen != nil || e.aufgaben != nil }

    @ViewBuilder private var gross: some View {
        if e.kontext == .schule { grossSchule } else { grossZuhause }
    }

    /// Zu Hause und am Wochenende: Termine und Post groß, Schule (für den nächsten Schultag) knapp
    private var grossZuhause: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                weckerBlock
                Spacer()
                if let w = e.wetter, let t = w.heute {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(.multicolor).font(.system(size: 28))
                        Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.title3.weight(.bold))
                    }
                }
            }
            kasten(e.kontext == .frei ? "Termine" : "Termine " + e.schulName, "calendar", ziel: "termine") {
                if e.heute.isEmpty { Text("Keine Termine").font(.caption).opacity(0.8) }
                ForEach(Array(e.heute.prefix(4).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 8) {
                        Text(t.ganztags ? "ganzt." : t.start.uhrzeit).font(.caption.monospacedDigit()).opacity(0.85).frame(width: 42, alignment: .leading)
                        Text(t.titel).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
            }
            if !e.post.isEmpty { kasten("Post & Pakete", "shippingbox.fill", ziel: "post") { Text(e.post).font(.caption).lineLimit(3) } }
            if !e.schulZeilen.isEmpty {
                kasten(schulTitel, "graduationcap.fill", ziel: "vertretung") { ForEach(Array(e.schulZeilen.prefix(2).enumerated()), id: \.offset) { _, z in schulZeile(z) } }
            }
            if e.kontext != .frei, let m = e.essen { kasten("Mensa " + e.schulName, "fork.knife", ziel: "mensa") { Text(m).font(.caption.weight(.semibold)).lineLimit(1) } }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grossSchule: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                weckerBlock
                Spacer()
                if let w = e.wetter, let t = w.heute {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(.multicolor).font(.system(size: 28))
                        Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.title3.weight(.bold))
                        Text("\(Int(t.min.rounded()))–\(Int(t.max.rounded()))° · ☂︎ \(t.regen) %").font(.caption2).opacity(0.85)
                    }
                }
            }
            if !e.schulZeilen.isEmpty {
                kasten(schulTitel, "graduationcap.fill", ziel: "vertretung") { ForEach(Array(e.schulZeilen.prefix(zahlenDa ? 3 : 4).enumerated()), id: \.offset) { _, z in schulZeile(z) } }
            }
            if let m = e.essen { kasten("Mensa " + e.schulName, "fork.knife", ziel: "mensa") { Text(m).font(.caption.weight(.semibold)).lineLimit(2) } }
            if zahlenDa { zahlen }
            kasten("Termine " + e.schulName, "calendar", ziel: "termine") {
                if e.heute.isEmpty { Text("Keine Termine").font(.caption).opacity(0.8) }
                ForEach(Array(e.heute.prefix(zahlenDa ? 2 : 3).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 8) {
                        Text(t.ganztags ? "ganzt." : t.start.uhrzeit).font(.caption.monospacedDigit()).opacity(0.85).frame(width: 42, alignment: .leading)
                        Text(t.titel).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
            }
            if !e.post.isEmpty && !zahlenDa { kasten("Post", "shippingbox.fill", ziel: "post") { Text(e.post).font(.caption).lineLimit(2) } }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if os(iOS)
/// Die kurze Live-Aktivität beim Verbinden: übernimmt beim Zeichnen Einstellungen und Token
struct UebergabeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MorgenUebergabe.self) { k in
            let _ = WidgetSpeicher.uebernehmen(json: k.attributes.einstellungen, token: k.attributes.token, geheim: k.attributes.geheim)
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                Text("Widget ist verbunden").font(.headline)
                Spacer(minLength: 0)
            }
            .padding(14)
        } dynamicIsland: { k in
            let _ = WidgetSpeicher.uebernehmen(json: k.attributes.einstellungen, token: k.attributes.token, geheim: k.attributes.geheim)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text("Widget ist verbunden").font(.headline) }
            } compactLeading: {
                Image(systemName: "sunrise.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Image(systemName: "checkmark").foregroundStyle(.green)
            } minimal: {
                Image(systemName: "sunrise.fill").foregroundStyle(.orange)
            }
        }
    }
}
#endif
