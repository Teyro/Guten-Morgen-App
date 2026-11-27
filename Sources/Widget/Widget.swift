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

/// Ohne Einstellungen pro Widget (StaticConfiguration) – die starten auch in neu signierten Apps.
struct MorgenZeitleiste: TimelineProvider {
    func placeholder(in context: Context) -> MorgenEintrag { .beispiel }
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
        // Läuft regelmäßig im Hintergrund – hier kommt auch „Vertretungsplan ist da“, wenn die App zu ist
        if e.mitteilungen || e.vertretungMelden || e.vertretungDa {
            Melder.pruefen(stoerungen: e.mitteilungen && e.stoerungen ? stoe : nil, aufgaben: e.mitteilungen && e.aufgaben ? auf : nil,
                           vertretung: plan, planDa: e.vertretungDa, betrifft: e.vertretungMelden, dringend: e.vertretungDringend)
        }
        // Standort (falls erlaubt): in der Schule die Schul-Infos, zu Hause und am Wochenende Termine und Post zuerst
        var hier: Kontext.Ort?
        let ortung = CLLocationManager()
        if ortung.isAuthorizedForWidgetUpdates, let l = ortung.location { hier = Kontext.Ort(lat: l.coordinate.latitude, lon: l.coordinate.longitude) }
        if e.chatMelden { await Melder.chat(e, geheim: geheim, hier: hier, frei: frei) }
        let kontext = Kontext.bestimme(jetzt: jetzt, frei: frei, hier: hier, schule: e.schulOrt, zuhause: e.zuhauseOrt)
        let amTag = abw.map { Abwesenheiten.amTag($0.eintraege, ziel: schulTag, klassen: e.klassenListe) }
        let kinder = amTag.map { $0.filter { !Abwesenheiten.ausgegraut($0, e.abwesendAus) }.map { e.sichtschutz ? Abwesenheiten.kurzName($0.name) : $0.name } }
        let fehlen = amTag.map { Abwesenheiten.zahl($0, aus: e.abwesendAus, plan: plan, ziel: schulTag) }
        return MorgenEintrag(date: jetzt, eingerichtet: true, wecker: wecker, wetter: await w, termin: naechster, post: await p,
                             heute: tagesTermine, vertretung: e.vertretung ? plan : nil, haeuser: e.haeuser,
                             mensa: e.mensa ? mensaPlan?.tag(ziel) : nil, mensaWahl: (e.favoriten, e.meiden), gemerkt: (e.lieblingsGerichte, e.nichtLecker),
                             obst: e.obstBereit && obstTage.contains(ziel), farbton: e.farbton, schulName: Tagwahl.name(schulTag, jetzt: jetzt),
                             kinder: e.abwesenheiten ? kinder : nil, fehlen: e.abwesenheiten ? fehlen : nil, stoerungen: e.stoerungen ? stoe?.offen.count : nil, aufgaben: e.aufgaben ? auf?.offen.count : nil,
                             kontext: kontext,
                             ersetzt: Dictionary(e.schultag(schulTag, vertretung: plan).filter { $0.art == .vertretung }.compactMap { b in b.ersetzt.map { (b.name, $0) } }, uniquingKeysWith: { a, _ in a }))
    }
}


/// Das Haupt-Widget in Liquid Glass: gläserne Karten und Knöpfe (heller Lichtrand, durchscheinend), klare Typo wie Apples Widgets.
/// Rot = außerplanmäßig (Vertretung, Begleitung), Orange = Aufsicht, Grün = alles nach Plan.
/// Klein · Mittel · Groß · Extragroß (iPad) und Sperrbildschirm. Getönt/klar übernimmt iOS das Glas selbst.
struct MorgenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "morgen", provider: MorgenZeitleiste()) { e in
            MorgenWidgetAnsicht(e: e)
                .containerBackground(for: .widget) { WidgetGrund(farbton: Farbton.zu(e.farbton)) }
                .widgetURL(URL(string: Marke.link("start")))
        }
        .configurationDisplayName(Marke.name)
        .description(Marke.schule ? "Dein Schultag in Liquid Glass: Vertretung (rot), Aufsicht, Mensa, Abwesenheiten und Termine – ab 16 Uhr schon für morgen."
                     : "Wecker, Wetter, Schultag, Mensa, Termine und Post in Liquid Glass – ab 16 Uhr schon für morgen.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
        #endif
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
