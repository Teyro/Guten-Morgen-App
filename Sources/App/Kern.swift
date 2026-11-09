import Foundation
import SwiftUI
import WidgetKit
import MorgenKern
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Zustand der App: Einstellungen, eingesammelte Daten, Aktionen (Vorlesen, Gute Nacht, Wecker, Widget-Übergabe)
@MainActor
@Observable
final class Kern {
    let vorschau = CommandLine.arguments.contains("--vorschau")
    var einstellungen: MorgenEinstellungen { didSet { speichern() } }
    var token: String { didSet { if !vorschau { Schluesselbund.speichern(token, "token"); speichern() } } }

    var wetter: Wetter?
    var frei: [FreierTag] = []
    var termine: [Termin] = []
    var erinnerungen: [String] = []
    var post = ""
    var vertretung: VertretungsPlan?
    var vertretungFehler = ""
    var laedt = false
    var meldung = ""
    var weckerText = ""
    var einstellungenOffen = false

    @ObservationIgnored let kalender = Kalender()
    let musik = Weckmusik()
    var nachtOffen = false

    init() {
        if vorschau {
            var e = MorgenEinstellungen()
            e.haAdresse = "http://homeassistant.local:8123"
            e.kuerzel = "Sta"
            einstellungen = e
            token = ""
            vorschauDaten()
            return
        }
        einstellungen = UserDefaults.standard.string(forKey: "einstellungen").flatMap(MorgenEinstellungen.aus(json:)) ?? MorgenEinstellungen()
        token = Schluesselbund.lesen("token") ?? ""
    }

    var ha: HomeAssistant { HomeAssistant(adresse: einstellungen.haAdresse, token: token) }

    private func speichern() {
        guard !vorschau else { return }
        UserDefaults.standard.set(einstellungen.json(), forKey: "einstellungen")
        if MorgenAblage.gruppeDa { MorgenAblage.speichern(einstellungen, token: token) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Der nächste Wecktag und seine Weckzeit
    var naechsterWecker: Weckzeit {
        let tag = Weckzeit.naechsterTag()
        return Weckzeit.berechne(tag: tag, termine: termine, frei: FreieTage.am(frei, tag), e: einstellungen)
    }

    var freiHeute: FreierTag? { FreieTage.am(frei, Date()) }

    // MARK: Laden

    func aktualisieren() async {
        guard !vorschau, !laedt else { return }
        laedt = true
        defer { laedt = false }
        if einstellungen.termine || einstellungen.erinnerungen { await kalender.erlauben() }
        let k = Zeit.kalender
        termine = einstellungen.termine ? kalender.termine(von: k.startOfDay(for: Date()), tage: 3) : []
        erinnerungen = einstellungen.erinnerungen ? await kalender.erinnerungenHeute() : []
        let e = einstellungen
        let verbindung = ha
        let mitPost = e.post && verbindung.eingerichtet
        async let w = try? Wetter.laden(lat: e.lat, lon: e.lon)
        async let f = try? FreieTage.laden(bundesland: e.bundesland)
        async let p: String = mitPost ? verbindung.postHeute() : ""
        wetter = await w
        if let neu = await f { frei = neu }
        post = await p
        if e.vertretung, !e.vertretungLink.isEmpty, !e.kuerzel.isEmpty {
            do { vertretung = try await Vertretung.laden(link: e.vertretungLink, kuerzel: e.kuerzel); vertretungFehler = "" }
            catch { vertretungFehler = "Vertretungsplan nicht erreichbar" }
        }
        if e.weckerAutomatisch && Wecker.verfuegbar { await weckerStellen(still: true) }
        await widgetUebergeben()
    }

    // MARK: Aktionen

    func briefing() -> String {
        var d = BriefingDaten()
        d.wetter = wetter; d.termine = termine; d.erinnerungen = erinnerungen; d.post = post
        d.vertretung = einstellungen.vertretung ? vertretung : nil; d.frei = freiHeute
        return Briefing.morgen(d)
    }

    func briefingVorlesen() async {
        if !vorschau && wetter == nil { await aktualisieren() }
        if ha.eingerichtet { for a in einstellungen.morgen { _ = await ha.ausfuehren(a) } }
        Sprecher.shared.sprechen(briefing())
    }

    /// Gute Nacht: Home-Assistant-Aktionen, offene Fenster, Wecker für morgen – und vorlesen
    @discardableResult
    func guteNacht(vorlesen: Bool = true) async -> String {
        var d = BriefingDaten()
        if ha.eingerichtet {
            for a in einstellungen.nacht { if await ha.ausfuehren(a) { d.erledigt.append(a.name) } }
            d.offeneFenster = await ha.offeneFenster()
        }
        if !vorschau { termine = kalender.termine(von: Zeit.kalender.startOfDay(for: Date()), tage: 3) }
        d.wecker = naechsterWecker
        d.wetter = wetter
        if einstellungen.weckerAutomatisch && Wecker.verfuegbar { await weckerStellen(still: true) }
        let t = Briefing.nacht(d)
        if vorlesen { Sprecher.shared.sprechen(t) }
        return t
    }

    /// Nachtmodus: der normale Wecker rückt als Sicherheit 5 Minuten nach hinten (zuerst spielt die Weckmusik)
    func nachtVorbereiten() async {
        guard Wecker.verfuegbar, let d = naechsterWecker.datum else { return }
        weckerText = await Wecker.stellen(d.addingTimeInterval(300))
    }

    /// Nach dem Aufstehen (oder Abbruch): den Wecker für den nächsten Tag stellen
    func nachtVorbei() async {
        if Wecker.verfuegbar && einstellungen.weckerAutomatisch { await weckerStellen(still: true) }
    }

    func weckerStellen(still: Bool = false) async {
        let w = naechsterWecker
        let text = await Wecker.stellen(w.datum)
        weckerText = text
        if !still { meldung = text }
    }

    /// Widget ohne App-Gruppe: Einstellungen und Token per kurzer Live-Aktivität übergeben (einmal je Änderung)
    func widgetUebergeben(erzwingen: Bool = false) async {
        #if canImport(ActivityKit)
        guard !vorschau, !MorgenAblage.gruppeDa else { return }
        let sig = einstellungen.json() + "|" + String(token.suffix(8))
        guard erzwingen || UserDefaults.standard.string(forKey: "widgetUebergeben") != sig else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            if erzwingen { meldung = "Live-Aktivitäten sind aus – iPhone-Einstellungen → Guten Morgen → Live-Aktivitäten erlauben." }
            return
        }
        do {
            let a = try Activity.request(attributes: MorgenUebergabe(einstellungen: einstellungen.json(), token: token),
                                         content: ActivityContent(state: .init(fertig: true), staleDate: nil))
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await a.end(nil, dismissalPolicy: .immediate)
            UserDefaults.standard.set(sig, forKey: "widgetUebergeben")
            if erzwingen { meldung = "Widget verbunden – es lädt gleich neu." }
        } catch {
            if erzwingen { meldung = "Verbinden hat nicht geklappt: \(error.localizedDescription)" }
        }
        #endif
    }

    // MARK: Vorschau (Bildschirmfotos in der CI)

    private func vorschauDaten() {
        let k = Zeit.kalender
        let heute = k.startOfDay(for: Date())
        wetter = Wetter(jetzt: 4, jetztCode: 3, heute: WetterTag(code: 61, max: 8, min: 2, regen: 70, wind: 20),
                        morgen: WetterTag(code: 2, max: 10, min: 3, regen: 10, wind: 15), stand: Date())
        termine = [Termin(titel: "Dienstbesprechung", start: k.date(bySettingHour: 7, minute: 30, second: 0, of: k.date(byAdding: .day, value: 1, to: heute)!)!, ganztags: false),
                   Termin(titel: "Zahnarzt", start: k.date(bySettingHour: 15, minute: 30, second: 0, of: heute)!, ganztags: false)]
        erinnerungen = ["Elternbriefe kopieren"]
        post = "Heute kommt ein Paket: Thalia (DHL). Dazu ein Brief."
        var p = VertretungsPlan(); p.stunden = [.init(stunde: "2", klasse: "2c")]; p.pausen = [.init(pause: "2. Pause", ort: "Mensa + Haltestelle")]
        vertretung = p
        weckerText = "Wecker gestellt: Dienstag, 06:15 Uhr"
    }
}
