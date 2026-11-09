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
        let (e, token) = paar
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
        return MorgenEintrag(date: Date(), eingerichtet: true, wecker: wecker, wetter: await w, termin: naechster, post: await p)
    }
}

struct MorgenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "morgen", provider: MorgenZeitleiste()) { e in
            MorgenWidgetAnsicht(e: e).containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.18, green: 0.2, blue: 0.48), Color(red: 0.85, green: 0.45, blue: 0.4)], startPoint: .top, endPoint: .bottom)
            }
        }
        .configurationDisplayName("Guten Morgen")
        .description("Wecker, Wetter, nächster Termin und Post.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
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
                    if let t = e.termin { Text("\(t.start.uhrzeit) \(t.titel)").font(.caption).lineLimit(1) }
                }
            #endif
            case .systemMedium: mittel
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

    private var mittel: some View {
        HStack(spacing: 14) {
            klein.frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                if let g = e.wecker?.grund, !g.isEmpty { Text(g).font(.caption).lineLimit(2).opacity(0.9) }
                if let t = e.termin {
                    Label("\(t.start.uhrzeit) \(t.titel)", systemImage: "calendar").font(.caption.weight(.semibold)).lineLimit(2)
                }
                if !e.post.isEmpty { Label(e.post, systemImage: "shippingbox.fill").font(.caption).lineLimit(3) }
                if let w = e.wetter, let t = w.heute, t.regen >= 50 { Label("Regen \(t.regen) %", systemImage: "umbrella.fill").font(.caption) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

#if os(iOS)
/// Die kurze Live-Aktivität beim Verbinden: übernimmt beim Zeichnen Einstellungen und Token
struct UebergabeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MorgenUebergabe.self) { k in
            let _ = WidgetSpeicher.uebernehmen(json: k.attributes.einstellungen, token: k.attributes.token)
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                Text("Widget ist verbunden").font(.headline)
                Spacer(minLength: 0)
            }
            .padding(14)
        } dynamicIsland: { k in
            let _ = WidgetSpeicher.uebernehmen(json: k.attributes.einstellungen, token: k.attributes.token)
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
