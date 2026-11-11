import WidgetKit
import SwiftUI
import MorgenKern
#if os(iOS)
import ActivityKit
#endif

// MARK: Gemeinsame Anzeige „jetzt / danach“

struct JetztDanach: View {
    let bloecke: [Block]
    let datum: Date
    var kompakt = false
    var body: some View {
        let jd = Stundenplan.jetzt(bloecke, datum)
        let j = jd.jetzt, d = jd.danach
        VStack(alignment: .leading, spacing: kompakt ? 1 : 4) {
            if let j {
                HStack(alignment: .firstTextBaseline) {
                    Text(j.marke).font(.caption.bold().monospacedDigit()).foregroundStyle(.orange)
                    Text(j.art == .pause ? "Pause" : j.text).font(kompakt ? .caption.bold() : .headline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timerInterval: j.von...j.bis, countsDown: true).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing).frame(maxWidth: 52, alignment: .trailing)
                }
                if !kompakt { ProgressView(timerInterval: j.von...j.bis, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }.tint(.orange) }
            } else if let d {
                Text("Gleich: \(d.titel)").font(.caption).foregroundStyle(.secondary)
            }
            if let d {
                Text("\(d.von.formatted(date: .omitted, time: .shortened)) · " + (d.art == .pause ? d.titel : "\(d.marke) \(d.text)"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if j != nil {
                Text("Danach: Schluss").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Widget „Schultag“ – Zeitleiste mit einem Eintrag je Stundenwechsel (zuverlässig ohne App)

struct SchultagEintrag: TimelineEntry {
    let date: Date
    var bloecke: [Block]
}

struct SchultagZeitleiste: TimelineProvider {
    func placeholder(in context: Context) -> SchultagEintrag {
        let jetzt = Date()
        return SchultagEintrag(date: jetzt, bloecke: [Block(name: "3", von: jetzt.addingTimeInterval(-900), bis: jetzt.addingTimeInterval(1800), art: .unterricht, text: "5a Mathe · R12"),
                                                     Block(name: "2. Pause", von: jetzt.addingTimeInterval(1800), bis: jetzt.addingTimeInterval(3300), art: .aufsicht, text: "Aufsicht Hof")])
    }
    func getSnapshot(in context: Context, completion: @escaping (SchultagEintrag) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SchultagEintrag>) -> Void) {
        let jetzt = Date()
        guard let e = WidgetSpeicher.einstellungen()?.0 else { completion(Timeline(entries: [SchultagEintrag(date: jetzt, bloecke: [])], policy: .after(jetzt.addingTimeInterval(3600)))); return }
        let d = UserDefaults.standard
        let plan = d.data(forKey: "vertretung").flatMap { try? JSONDecoder().decode(VertretungsPlan.self, from: $0) }
        let frei = d.data(forKey: "frei").flatMap { try? JSONDecoder().decode([FreierTag].self, from: $0) } ?? []
        let bloecke = FreieTage.am(frei, jetzt) == nil ? e.schultag(jetzt, vertretung: plan) : []
        let eintraege = [SchultagEintrag(date: jetzt, bloecke: bloecke)] + Stundenplan.wechsel(bloecke).filter { $0 > jetzt }.map { SchultagEintrag(date: $0, bloecke: bloecke) }
        // nach dem letzten Wechsel: um Mitternacht bzw. in einer Stunde neu (Vertretung kann sich ändern)
        let neu = min(Zeit.kalender.date(byAdding: .day, value: 1, to: Zeit.kalender.startOfDay(for: jetzt)) ?? jetzt, jetzt.addingTimeInterval(1800))
        completion(Timeline(entries: eintraege, policy: .after(max(neu, eintraege.last?.date ?? neu))))
    }
}

struct SchultagWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "schultag", provider: SchultagZeitleiste()) { e in
            SchultagAnsicht(e: e).containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "gutenmorgen://vertretung"))
        }
        .configurationDisplayName("Schultag")
        .description("Was gerade läuft und was danach kommt – mit Restzeit bis zur Pause.")
        #if os(iOS)
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall])
        #endif
    }
}

struct SchultagAnsicht: View {
    let e: SchultagEintrag
    @Environment(\.widgetFamily) private var familie
    var body: some View {
        let jd = Stundenplan.jetzt(e.bloecke, e.date)
        let j = jd.jetzt, d = jd.danach
        switch familie {
        case .accessoryInline:
            if let j { Text("\(j.marke) \(j.art == .pause ? "Pause" : j.text) bis \(j.bis.formatted(date: .omitted, time: .shortened))") }
            else if let d { Text("\(d.von.formatted(date: .omitted, time: .shortened)) \(d.marke) \(d.text)") }
            else { Text("Heute kein Unterricht") }
        default:
            if j == nil && d == nil {
                Text(e.bloecke.isEmpty ? "Heute kein Unterricht eingetragen" : "Schulschluss").font(.caption).foregroundStyle(.secondary)
            } else {
                JetztDanach(bloecke: e.bloecke, datum: e.date, kompakt: familie == .accessoryRectangular)
            }
        }
    }
}

// MARK: Live-Aktivität im Schulalltag (Sperrbildschirm, Dynamic Island, Smart Stack der Apple Watch)

#if os(iOS)
struct SchulTagLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchulTagAktivitaet.self) { k in
            JetztDanach(bloecke: k.state.bloecke, datum: Date())
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .widgetURL(URL(string: "gutenmorgen://vertretung"))
        } dynamicIsland: { k in
            let (j, d) = Stundenplan.jetzt(k.state.bloecke, Date())
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(j?.marke ?? d?.marke ?? "").font(.title3.bold()).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let j { Text(timerInterval: j.von...j.bis, countsDown: true).font(.title3.monospacedDigit()).frame(maxWidth: 70) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(j.map { $0.art == .pause ? "Pause" : $0.text } ?? d.map { "Gleich: \($0.text)" } ?? "").font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let d { Text("Danach \(d.von.formatted(date: .omitted, time: .shortened)): " + (d.art == .pause ? d.titel : d.text)).font(.caption).foregroundStyle(.secondary) }
                }
            } compactLeading: {
                Text(j?.marke ?? d?.marke ?? "").font(.caption.bold()).foregroundStyle(.orange)
            } compactTrailing: {
                if let j { Text(timerInterval: j.von...j.bis, countsDown: true).font(.caption.monospacedDigit()).frame(maxWidth: 44) }
                else if let d { Text(d.von, style: .time).font(.caption) }
            } minimal: {
                Text(j?.marke ?? d?.marke ?? "").font(.caption2.bold()).foregroundStyle(.orange)
            }
        }
    }
}
#endif
