import WidgetKit
import SwiftUI
import EventKit
import MorgenKern
#if os(iOS)
import ActivityKit
#endif

@main
struct MorgenWidgets: WidgetBundle {
    var body: some Widget {
        MorgenWidget()
        #if os(iOS)
        UebergabeWidget()
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
    var heute: [Termin] = []
    var vertretung: VertretungsPlan?
    var haeuser: [String: [String]] = [:]
    var mensa: MensaTag?
    var obst = false
    var farbton = "morgenrot"

    /// Kurze Schul-Zeilen fürs Widget: „2. Vertretung 2c · Haus 2“, „1. P Hofaufsicht Mensa“, „🍎 Schulobst“, „🍽 Spaghetti“
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
        if obst { z.append(("🍎", "Heute Schulobst")) }
        if let m = mensa {
            if let f = m.frei { z.append(("🍽", "Mensa zu" + (f.isEmpty ? "" : " (\(f))"))) } else if let h = m.haupt { z.append(("🍽", h.text)) }
        }
        return z
    }
}

/// Ohne Einstellungen pro Widget (StaticConfiguration) – die starten auch in neu signierten Apps.
struct MorgenZeitleiste: TimelineProvider {
    func placeholder(in context: Context) -> MorgenEintrag {
        MorgenEintrag(date: Date(), eingerichtet: true, wecker: Weckzeit(minuten: 375, grund: "", tag: Weckzeit.naechsterTag()),
                      wetter: Wetter(jetzt: 6, jetztCode: 2, heute: WetterTag(code: 2, max: 9, min: 3, regen: 10, wind: 10), morgen: nil, stand: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (MorgenEintrag) -> Void) { completion(placeholder(in: context)) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorgenEintrag>) -> Void) {
        Task {
            let e = await eintrag()
            let k = Zeit.kalender
            let mitternacht = k.date(byAdding: .day, value: 1, to: k.startOfDay(for: Date())) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [e], policy: .after(min(mitternacht, Date().addingTimeInterval(3600)))))
        }
    }

    private func eintrag() async -> MorgenEintrag {
        guard let paar = WidgetSpeicher.einstellungen() else { return MorgenEintrag(date: Date(), eingerichtet: false) }
        let (e, token, geheim) = paar
        let d = UserDefaults.standard
        // freie Tage höchstens einmal am Tag holen
        var frei = (d.data(forKey: "frei")).flatMap { try? JSONDecoder().decode([FreierTag].self, from: $0) } ?? []
        if Date().timeIntervalSince1970 - d.double(forKey: "freiStand") > 86400 * 3 || frei.isEmpty,
           let neu = try? await FreieTage.laden(bundesland: e.bundesland) {
            frei = neu
            d.set(try? JSONEncoder().encode(neu), forKey: "frei")
            d.set(Date().timeIntervalSince1970, forKey: "freiStand")
        }
        // Termine (falls die Kalender-Erlaubnis der App auch fürs Widget gilt)
        var termine: [Termin] = []
        if e.termine, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let s = EKEventStore()
            let von = Zeit.kalender.startOfDay(for: Date())
            let p = s.predicateForEvents(withStart: von, end: von.addingTimeInterval(3 * 86400), calendars: nil)
            termine = s.events(matching: p).map { Termin(titel: $0.title ?? "Termin", start: $0.startDate, ganztags: $0.isAllDay) }
        }
        let tag = Weckzeit.naechsterTag()
        let wecker = Weckzeit.berechne(tag: tag, termine: termine, frei: FreieTage.am(frei, tag), e: e)
        let ha = HomeAssistant(adresse: e.haAdresse, token: token)
        async let w = try? Wetter.laden(lat: e.lat, lon: e.lon)
        async let p: String = e.post && ha.eingerichtet ? ha.postHeute() : ""
        let naechster = termine.filter { !$0.ganztags && $0.start > Date() }.min { $0.start < $1.start }
        let heute = termine.filter { Zeit.kalender.isDateInToday($0.start) }.sorted { $0.start < $1.start }
        // Vertretung (fürs große Widget) höchstens alle 30 Minuten aus dem Schul-Ordner
        var plan = d.data(forKey: "vertretung").flatMap { try? JSONDecoder().decode(VertretungsPlan.self, from: $0) }
        if e.vertretung, !e.vertretungLink.isEmpty, !e.kuerzel.isEmpty, Date().timeIntervalSince1970 - d.double(forKey: "vertretungStand") > 1800 {
            if let neu = try? await Vertretung.laden(link: e.vertretungLink, kuerzel: e.kuerzel, passwort: geheim.freigabe) {
                plan = neu
                d.set(try? JSONEncoder().encode(neu), forKey: "vertretung")
            }
            d.set(Date().timeIntervalSince1970, forKey: "vertretungStand")
        }
        // Mensa: einmal je Tag (bei Fehler höchstens stündlich neu versuchen)
        let ziel = Mensa.zielTag()
        var mensa = d.data(forKey: "mensa").flatMap { try? JSONDecoder().decode(MensaTag.self, from: $0) }
        if mensa?.datum != ziel { mensa = nil }
        if e.mensaBereit, !geheim.mensa.isEmpty, mensa == nil, Date().timeIntervalSince1970 - d.double(forKey: "mensaVersuch") > 3600 {
            d.set(Date().timeIntervalSince1970, forKey: "mensaVersuch")
            if let t = try? await Mensa.laden(adresse: e.mensaAdresse, benutzer: e.mensaBenutzer, passwort: geheim.mensa, ziel: ziel) {
                mensa = t
                d.set(try? JSONEncoder().encode(t), forKey: "mensa")
            }
        }
        // Schulobst: Kalender höchstens alle 12 Stunden
        var obstTage = Set(d.stringArray(forKey: "obst") ?? [])
        if e.obstBereit, Date().timeIntervalSince1970 - d.double(forKey: "obstStand") > 12 * 3600, let neu = try? await SchulKalender.laden(e.obstKalender) {
            obstTage = neu
            d.set(Array(neu), forKey: "obst")
            d.set(Date().timeIntervalSince1970, forKey: "obstStand")
        }
        return MorgenEintrag(date: Date(), eingerichtet: true, wecker: wecker, wetter: await w, termin: naechster, post: await p,
                             heute: heute, vertretung: e.vertretung ? plan : nil, haeuser: e.haeuser,
                             mensa: e.mensa ? mensa : nil, obst: e.obstBereit && obstTage.contains(Zeit.iso(Date())), farbton: e.farbton)
    }
}

struct MorgenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "morgen", provider: MorgenZeitleiste()) { e in
            MorgenWidgetAnsicht(e: e).containerBackground(for: .widget) {
                LinearGradient(colors: Farbton.zu(e.farbton).widget, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .configurationDisplayName("Guten Morgen")
        .description("Wecker, Wetter, Vertretung, Hofaufsicht, Mensa, Schulobst, Termine und Post.")
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
                    if let w = e.wetter?.heute { Text("\(Int(w.min.rounded()))–\(Int(w.max.rounded()))° · Regen \(w.regen) %").font(.caption) }
                    if let s = e.schulZeilen.first { Text("\(s.marke) \(s.text)").font(.caption).lineLimit(1) }
                    else if let t = e.termin { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption).lineLimit(1) }
                }
            #endif
            case .systemMedium: mittel
            case .systemLarge, .systemExtraLarge: gross
            default: klein
            }
        }
    }

    private var klein: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { Image(systemName: "alarm.fill"); Text("Wecker \(weckTag)") }.font(.caption.weight(.semibold)).opacity(0.85)
            Text(weckText).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if let w = e.wetter, let t = w.heute {
                HStack(spacing: 5) {
                    Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(.multicolor)
                    Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.headline)
                    Text("\(Int(t.min.rounded()))–\(Int(t.max.rounded()))°").font(.caption).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gross: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) { Image(systemName: "alarm.fill"); Text("Wecker \(weckTag)") }.font(.caption.weight(.semibold)).opacity(0.85)
                    Text(weckText).font(.system(size: 44, weight: .bold, design: .rounded))
                    if let g = e.wecker?.grund, !g.isEmpty { Text(g).font(.caption).lineLimit(2).opacity(0.9) }
                }
                Spacer()
                if let w = e.wetter, let t = w.heute {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: Wetter.symbol(w.jetztCode ?? t.code)).symbolRenderingMode(.multicolor).font(.system(size: 30))
                        Text("\(Int((w.jetzt ?? t.max).rounded()))°").font(.title2.weight(.bold))
                        Text("\(Int(t.min.rounded()))–\(Int(t.max.rounded()))° · ☂︎ \(t.regen) %").font(.caption2).opacity(0.85)
                    }
                }
            }
            Divider().overlay(.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 4) {
                Label("Heute", systemImage: "calendar").font(.caption.weight(.semibold)).opacity(0.85)
                if e.heute.isEmpty { Text("Keine Termine").font(.callout).opacity(0.8) }
                ForEach(Array(e.heute.prefix(4).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 8) {
                        Text(t.ganztags ? "ganzt." : t.start.uhrzeit).font(.caption.monospacedDigit()).opacity(0.85).frame(width: 44, alignment: .leading)
                        Text(t.titel).font(.callout.weight(.medium)).lineLimit(1)
                    }
                }
            }
            if !e.schulZeilen.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Schule", systemImage: "graduationcap.fill").font(.caption.weight(.semibold)).opacity(0.85)
                    ForEach(Array(e.schulZeilen.prefix(5).enumerated()), id: \.offset) { _, z in schulZeile(z) }
                }
            }
            if !e.post.isEmpty { Label(e.post, systemImage: "shippingbox.fill").font(.caption).lineLimit(2) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mittel: some View {
        HStack(spacing: 14) {
            klein.frame(width: 120)
            VStack(alignment: .leading, spacing: 5) {
                // Schule zuerst (Vertretung, Aufsicht, Obst, Mensa), dann Termin und Post
                ForEach(Array(e.schulZeilen.prefix(4).enumerated()), id: \.offset) { _, z in schulZeile(z) }
                if e.schulZeilen.isEmpty, let g = e.wecker?.grund, !g.isEmpty { Text(g).font(.caption).lineLimit(2).opacity(0.9) }
                if e.schulZeilen.count < 3, let t = e.termin {
                    Label("\(t.start.uhrzeit) \(t.titel)", systemImage: "calendar").font(.caption.weight(.semibold)).lineLimit(2)
                }
                if e.schulZeilen.count < 2, !e.post.isEmpty { Label(e.post, systemImage: "shippingbox.fill").font(.caption).lineLimit(3) }
                if e.schulZeilen.count < 4, let w = e.wetter, let t = w.heute, t.regen >= 50 { Label("Regen \(t.regen) %", systemImage: "umbrella.fill").font(.caption) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

extension MorgenWidgetAnsicht {
    func schulZeile(_ z: (marke: String, text: String)) -> some View {
        HStack(spacing: 6) {
            Text(z.marke).font(.system(size: 11, weight: .bold, design: .rounded)).frame(minWidth: 26, minHeight: 18)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(z.text).font(.caption.weight(.semibold)).lineLimit(1)
        }
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
