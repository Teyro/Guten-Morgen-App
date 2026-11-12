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
    var mensaPasswort: String { didSet { if !vorschau { Schluesselbund.speichern(mensaPasswort, "mensa"); speichern() } } }
    var freigabePasswort: String { didSet { if !vorschau { Schluesselbund.speichern(freigabePasswort, "freigabe"); speichern() } } }
    var iservPasswort: String { didSet { if !vorschau { Schluesselbund.speichern(iservPasswort, "iserv"); speichern() } } }
    var totpGeheim: String { didSet { if !vorschau { Schluesselbund.speichern(totpGeheim, "totp"); speichern() } } }
    var edupoolToken: String { didSet { if !vorschau { Schluesselbund.speichern(edupoolToken, "edupool"); speichern() } } }
    var untisPasswort: String { didSet { if !vorschau { Schluesselbund.speichern(untisPasswort, "untis") } } }
    /// Schlüssel aus dem QR-Code „Untis Mobile“ (für Konten mit zweitem Faktor)
    var untisSchluessel: String { didSet { if !vorschau { Schluesselbund.speichern(untisSchluessel, "untisSchluessel") } } }
    var untis: UntisStand? { didSet { merke(untis, "untisStand") } }
    var untisFehler = ""
    var postStand: PostStand? { didSet { merke(postStand, "postStand") } }
    var postFehler = ""
    /// Gerade nicht zu Hause (Schalter „Unterwegs“ und gespeichertes Zuhause)
    var unterwegs = false
    var geheim: Geheimnisse { Geheimnisse(mensa: mensaPasswort, freigabe: freigabePasswort, iserv: iservPasswort, totp: totpGeheim, edupool: edupoolToken) }

    // Module aus Mein Tag (nativ): zuletzt geladener Stand bleibt gespeichert (Anzeige sofort, Aufgaben auch offline)
    var abwesend: AbwesenheitenStand? { didSet { merke(abwesend, "abwesendStand") } }
    var abwesendFehler = ""
    var stoerungen: StoerungenStand? { didSet { merke(stoerungen, "stoerungenStand") } }
    var stoerungenFehler = ""
    var aufgaben: AufgabenStand? { didSet { merke(aufgaben, "aufgabenStand") } }
    var aufgabenFehler = ""
    /// Zwei-Faktor-Code von Hand: Hinweis für das Eingabefenster, Antwort über die Fortsetzung
    var codeHinweis: String?
    @ObservationIgnored var codeWarten: CheckedContinuation<String?, Never>?
    /// Neue Anmeldeseite (z. B. Schuldock) muss einmal bestätigt werden
    var hostFrage: String?
    /// Edupool verbinden: angezeigter Code, solange gewartet wird
    var edupoolCode: String?

    private func merke<T: Encodable>(_ w: T?, _ k: String) {
        guard !vorschau else { return }
        if let w { UserDefaults.standard.set(try? JSONEncoder().encode(w), forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
    }
    private static func gemerkt<T: Decodable>(_ k: String) -> T? { UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    var farbton: Farbton { Farbton.zu(einstellungen.farbton) }

    var wetter: Wetter?
    var frei: [FreierTag] = []
    var termine: [Termin] = []
    var erinnerungen: [String] = []
    var post = ""
    var vertretung: VertretungsPlan?
    var vertretungFehler = ""
    var mensaPlan: MensaPlan?
    var mensaFehler = ""
    var obstTage: Set<String> = []
    /// Fahrzeit zur Schule für einen Schultag (Apple Karten), gemerkt bis zum nächsten Laden
    var fahrt: (tag: Date, minuten: Int)?
    var routineMeldung = ""
    var schlaf: TimeInterval?
    var laedt = false
    /// Sprungziel aus dem Widget (gutenmorgen://mensa …)
    var bereich: Bereich?
    /// Wartende Übernahme aus Mein Tag (wird erst nach Rückfrage angewendet)
    var importAnfrage: ImportDaten?

    /// Für welchen Tag die Schul-Infos gelten: bis 16 Uhr heute, danach der nächste Schultag
    var schulTag: Date { Tagwahl.ziel(Date(), frei: frei) }
    var schulTagName: String { Tagwahl.name(schulTag) }
    var mensa: MensaTag? { mensaPlan?.tag(Zeit.iso(schulTag)) }
    var obstHeute: Bool { obstTage.contains(Zeit.iso(schulTag)) }
    var meldung = ""
    var weckerText = ""
    var einstellungenOffen = false

    @ObservationIgnored let kalender = Kalender()
    @ObservationIgnored let ortung = Ortung()
    /// Wo bin ich: Schule zuerst oder Termine und Post zuerst
    var kontext: Kontext = .schule
    let musik = Weckmusik()
    var nachtOffen = false

    init() {
        if vorschau {
            var e = MorgenEinstellungen()
            e.haAdresse = "http://homeassistant.local:8123"
            e.kuerzel = "Sta"
            einstellungen = e
            token = ""
            mensaPasswort = ""
            freigabePasswort = ""
            iservPasswort = ""; totpGeheim = ""; edupoolToken = ""; untisPasswort = ""; untisSchluessel = ""
            vorschauDaten()
            return
        }
        einstellungen = UserDefaults.standard.string(forKey: "einstellungen").flatMap(MorgenEinstellungen.aus(json:)) ?? MorgenEinstellungen()
        token = Schluesselbund.lesen("token") ?? ""
        mensaPasswort = Schluesselbund.lesen("mensa") ?? ""
        freigabePasswort = Schluesselbund.lesen("freigabe") ?? ""
        iservPasswort = Schluesselbund.lesen("iserv") ?? ""
        totpGeheim = Schluesselbund.lesen("totp") ?? ""
        edupoolToken = Schluesselbund.lesen("edupool") ?? ""
        untisPasswort = Schluesselbund.lesen("untis") ?? ""
        untisSchluessel = Schluesselbund.lesen("untisSchluessel") ?? ""
        untis = Kern.gemerkt("untisStand")
        postStand = Kern.gemerkt("postStand")
        abwesend = Kern.gemerkt("abwesendStand")
        stoerungen = Kern.gemerkt("stoerungenStand")
        aufgaben = Kern.gemerkt("aufgabenStand")
    }

    var ha: HomeAssistant { HomeAssistant(adresse: einstellungen.haAdresse, token: token) }

    private func speichern() {
        guard !vorschau else { return }
        UserDefaults.standard.set(einstellungen.json(), forKey: "einstellungen")
        if MorgenAblage.gruppeDa { MorgenAblage.speichern(einstellungen, token: token, geheim: geheim) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Der nächste Wecktag und seine Weckzeit (mit Glätte und Anfahrt)
    var naechsterWecker: Weckzeit {
        let tag = Weckzeit.naechsterTag()
        let k = Zeit.kalender
        let wetterTag = k.isDateInToday(tag) ? wetter?.heute : wetter?.morgen
        let f = fahrt.flatMap { k.isDate($0.tag, inSameDayAs: tag) ? $0.minuten : nil }
        return einstellungen.wecker(tag: tag, termine: termine, frei: FreieTage.am(frei, tag), wetter: wetterTag, vertretung: vertretung, fahrtMinuten: f)
    }

    /// Eigener Tagesablauf des Schultags (heute, ab 16 Uhr der nächste) und von heute
    var schultag: [Block] { einstellungen.schultag(schulTag, vertretung: vertretung, ausfall: ausfall(schulTag)) }
    var heuteBloecke: [Block] { freiHeute == nil ? einstellungen.schultag(Date(), vertretung: vertretung, ausfall: ausfall(Date())) : [] }
    /// Ausgefallene eigene Stunden laut WebUntis an einem Tag
    func ausfall(_ tag: Date) -> [ClosedRange<Int>] {
        let iso = Zeit.iso(tag)
        return untis?.meine.filter { $0.datum == iso && $0.entfaellt && $0.bis > $0.von }.map { $0.von...$0.bis } ?? []
    }

    /// „Losfahren um 7 Uhr 12, 23 Minuten mit dem Auto.“ – nur am Morgen des Schultags
    var anfahrtText: String {
        guard einstellungen.fahrt, let f = fahrt, Zeit.kalender.isDateInToday(f.tag), let b = Stundenplan.beginn(heuteBloecke), b > Date() else { return "" }
        let k = Zeit.kalender
        let los = Anfahrt.losfahren(beginn: k.component(.hour, from: b) * 60 + k.component(.minute, from: b), fahrtMinuten: f.minuten, puffer: einstellungen.puffer)
        let art = einstellungen.fahrtArt == "oepnv" ? "mit Bus und Bahn" : einstellungen.fahrtArt == "fuss" ? "zu Fuß" : "mit dem Auto"
        return "Losfahren um \(Zeit.sprechen(los)), \(f.minuten) Minuten \(art)."
    }

    /// Fahrzeit für den nächsten Schulbeginn: heute (falls noch vor der ersten Stunde), sonst der nächste Wecktag
    func anfahrtBerechnen() async {
        let e = einstellungen
        guard e.fahrt, let schule = e.schulOrt else { fahrt = nil; return }
        let k = Zeit.kalender
        var tag = Date()
        var beginn = Stundenplan.beginn(heuteBloecke)
        if beginn == nil || beginn! <= Date() {
            tag = Weckzeit.naechsterTag()
            beginn = FreieTage.am(frei, tag) == nil ? Stundenplan.beginn(e.schultag(tag, vertretung: vertretung)) : nil
        }
        guard let b = beginn, let von = e.zuhauseOrt ?? ortung.ort else { return }
        if let m = await Fahrt.minuten(von: von, nach: schule, art: e.fahrtArt, ankunft: b.addingTimeInterval(-Double(e.puffer * 60))) {
            fahrt = (tag: k.startOfDay(for: tag), minuten: m)
        }
    }

    /// Nach dem Laden: Aufsicht-Erinnerungen, Live-Aktivität, Weckzeit an Home Assistant, Hintergrund-Lauf, Apple Watch
    func nachAussen() async {
        guard !vorschau else { return }
        let heute = heuteBloecke
        await AufsichtErinnerung.planen(schultag, an: einstellungen.aufsichtErinnern)
        await Schulalltag.aktualisieren(heute, an: einstellungen.schulAktivitaet)
        // Unterwegs: keine Morgenroutine zu Hause (Sensor „unbekannt“ → die Automation löst nicht aus)
        if ha.eingerichtet && !einstellungen.routine.isEmpty { await ha.weckzeitMelden(unterwegs ? nil : (Wecker.gestellt ?? naechsterWecker.datum)) }
        HintergrundLauf.planen(wecker: naechsterWecker.datum, bloecke: heute)
        Uhr.shared.senden(self)
    }

    /// WebUntis: höchstens alle 6 Stunden; mit „übernehmen“ wird die Grundwoche zu „Mein Stundenplan“
    func untisLaden(erzwingen: Bool = false) async {
        let e = einstellungen
        guard e.untisAn, !e.untisLink.isEmpty, !untisPasswort.isEmpty || !untisSchluessel.isEmpty || Untis.qr(e.untisLink) != nil else { return }
        let d = UserDefaults.standard
        guard erzwingen || Date().timeIntervalSince1970 - d.double(forKey: "untisGeladen") > 6 * 3600 else { return }
        do {
            let st = try await Untis.laden(link: e.untisLink, schule: e.untisSchule, benutzer: e.untisBenutzer, passwort: untisPasswort,
                                           schluessel: untisSchluessel.replacingOccurrences(of: " ", with: "").uppercased(), kuerzel: e.kuerzel.isEmpty ? e.untisBenutzer : e.kuerzel)
            untis = st; untisFehler = ""
            d.set(Date().timeIntervalSince1970, forKey: "untisGeladen")
            if e.untisUebernehmen {
                let neu = Untis.unterricht(st, zeiten: e.schulzeiten)
                if !neu.isEmpty && neu != einstellungen.unterricht { einstellungen.unterricht = neu }
            }
        } catch { untisFehler = error.localizedDescription }
    }

    /// Post und Pakete (Integration „Briefankündigung“)
    func postLaden() async {
        guard ha.eingerichtet, !vorschau else { return }
        do { postStand = try await ha.post(); postFehler = "" } catch { postFehler = "Post & Pakete nicht erreichbar (Integration „Briefankündigung“ in Home Assistant?)" }
    }

    /// Morgenroutine als Automation in Home Assistant anlegen (leer = löschen)
    func routineEinrichten() async {
        guard ha.eingerichtet else { routineMeldung = "Erst Home Assistant verbinden."; return }
        do {
            try await ha.routineEinrichten(einstellungen.routine)
            if !einstellungen.routine.isEmpty { await ha.weckzeitMelden(Wecker.gestellt ?? naechsterWecker.datum) }
            routineMeldung = einstellungen.routine.isEmpty ? "Morgenroutine in Home Assistant entfernt." : "Morgenroutine in Home Assistant eingerichtet (Automation „Guten Morgen – Morgenroutine“)."
        } catch {
            routineMeldung = (error as? URLError)?.code == .userAuthenticationRequired
                ? "Home Assistant lehnt ab – der Zugang braucht Admin-Rechte, um Automationen anzulegen."
                : "Einrichten hat nicht geklappt: \(error.localizedDescription)"
        }
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
        if mitPost { await postLaden() }
        let pw = freigabePasswort, mpw = mensaPasswort
        let ziel = Zeit.iso(schulTag)
        async let v: Result<VertretungsPlan, Error>? = e.vertretung && !e.vertretungLink.isEmpty && !e.kuerzel.isEmpty
            ? await versuch { try await Vertretung.laden(link: e.vertretungLink, kuerzel: e.kuerzel, passwort: pw, ziel: ziel) } : nil
        let mensaErlaubt = Mensa.darfAnmelden(.standard, benutzer: e.mensaBenutzer, passwort: mpw)
        async let m: Result<MensaPlan, Error>? = e.mensaBereit && !mpw.isEmpty && mensaErlaubt
            ? await versuch { try await Mensa.ladePlan(adresse: e.mensaAdresse, benutzer: e.mensaBenutzer, passwort: mpw) } : nil
        async let s: TimeInterval? = e.gesundheit ? await Gesundheit.schlafLetzteNacht() : nil
        async let o: Set<String>? = e.obstBereit ? try? await SchulKalender.laden(e.obstKalender) : nil
        switch await v {
        case .success(let p)?: vertretung = p; vertretungFehler = ""
        case .failure(let f)?: vertretungFehler = (f as? URLError)?.code == .userAuthenticationRequired ? "Freigabe-Passwort fehlt oder stimmt nicht" : "Vertretungsplan nicht erreichbar"
        case nil: vertretung = nil; vertretungFehler = ""
        }
        switch await m {
        case .success(let t)?: mensaPlan = t; mensaFehler = t.tag(ziel) == nil ? "Für \(schulTagName) steht nichts im Speiseplan" : ""
            Mensa.merke(.standard, fehler: nil, benutzer: e.mensaBenutzer, passwort: mpw)
        case .failure(let f)?: mensaFehler = f.localizedDescription
            Mensa.merke(.standard, fehler: f, benutzer: e.mensaBenutzer, passwort: mpw)
        case nil: mensaPlan = nil
            mensaFehler = e.mensa && mpw.isEmpty ? "Kantinen-Passwort fehlt" : !mensaErlaubt ? "Kantinen-Zugang wurde abgelehnt – bitte Benutzer oder Passwort prüfen" : ""
        }
        if let tage = await o { obstTage = tage } else if !e.obstBereit { obstTage = [] }
        schlaf = await s
        if e.schulOrt != nil || e.zuhauseOrt != nil { _ = await ortung.einmal() }
        unterwegs = e.unterwegs(hier: ortung.ort)
        kontext = Kontext.bestimme(frei: frei, hier: ortung.ort, schule: e.schulOrt, zuhause: e.zuhauseOrt)
        if await SchulFokusFilter.schuleAktiv() { kontext = .schule }
        await moduleLaden()
        await anfahrtBerechnen()
        if e.weckerAutomatisch && Wecker.verfuegbar { await weckerStellen(still: true) }
        await nachAussen()
        await widgetUebergeben()
    }

    // MARK: Aktionen

    func briefing() -> String {
        var d = BriefingDaten()
        d.wetter = wetter; d.termine = termine; d.erinnerungen = erinnerungen; d.post = post
        d.vertretung = einstellungen.vertretung ? vertretung : nil; d.frei = freiHeute
        d.haeuser = einstellungen.haeuser; d.mensa = einstellungen.mensa ? mensa : nil; d.obst = einstellungen.obst && obstHeute
        d.schulTag = schulTag; d.schlaf = schlaf
        d.mensaWahl = (einstellungen.favoriten, einstellungen.meiden)
        d.gemerkt = (einstellungen.lieblingsGerichte, einstellungen.nichtLecker)
        d.schultag = schultag
        d.anfahrt = anfahrtText
        d.auto = einstellungen.fahrt && einstellungen.fahrtArt == "auto"
        return Briefing.morgen(d)
    }

    func briefingVorlesen() async {
        if !vorschau && wetter == nil { await aktualisieren() }
        if ha.eingerichtet && !unterwegs { for a in einstellungen.morgen { _ = await ha.ausfuehren(a) } }
        Sprecher.shared.sprechen(briefing())
    }

    /// Gute Nacht: Home-Assistant-Aktionen, offene Fenster, Wecker für morgen – und vorlesen
    @discardableResult
    func guteNacht(vorlesen: Bool = true) async -> String {
        var d = BriefingDaten()
        // Unterwegs (z. B. bei Verwandten): statt „Alle Lichter aus“ die Unterwegs-Aktionen (Urlaubsmodus), keine Fenster-Warnung
        if einstellungen.unterwegsAn, einstellungen.zuhauseOrt != nil, !vorschau {
            if let l = await ortung.einmal() { unterwegs = einstellungen.unterwegs(hier: Kontext.Ort(lat: l.coordinate.latitude, lon: l.coordinate.longitude)) }
        }
        d.unterwegs = unterwegs
        if ha.eingerichtet {
            for a in (unterwegs ? einstellungen.unterwegsAktionen : einstellungen.nacht) { if await ha.ausfuehren(a) { d.erledigt.append(a.name) } }
            if !unterwegs { d.offeneFenster = await ha.offeneFenster() }
            if unterwegs && !einstellungen.routine.isEmpty { await ha.weckzeitMelden(nil) }
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
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "nachtBeginn")
        if einstellungen.gesundheit { _ = await Gesundheit.erlauben() }
        guard Wecker.verfuegbar, let d = naechsterWecker.datum else { return }
        weckerText = await Wecker.stellen(d.addingTimeInterval(300))
    }

    /// Nach dem Aufstehen (oder Abbruch): den Wecker für den nächsten Tag stellen
    func nachtVorbei() async {
        let beginn = UserDefaults.standard.double(forKey: "nachtBeginn")
        UserDefaults.standard.removeObject(forKey: "nachtBeginn")
        if einstellungen.gesundheit, beginn > 0 { await Gesundheit.nachtEintragen(von: Date(timeIntervalSince1970: beginn), bis: Date()) }
        if Wecker.verfuegbar && einstellungen.weckerAutomatisch { await weckerStellen(still: true) }
    }

    /// Übernahme aus Mein Tag anwenden (nach Bestätigung)
    func importieren(_ i: ImportDaten) async {
        var e = einstellungen
        let pw = i.anwenden(&e)
        einstellungen = e
        if !pw.mensa.isEmpty { mensaPasswort = pw.mensa }
        if !pw.freigabe.isEmpty { freigabePasswort = pw.freigabe }
        if !pw.iserv.isEmpty { iservPasswort = pw.iserv }
        if !pw.totp.isEmpty { totpGeheim = pw.totp }
        if !pw.edupool.isEmpty { edupoolToken = pw.edupool }
        meldung = "Aus Mein Tag übernommen"
        await aktualisieren()
    }

    // MARK: Abwesenheiten, Störungen (IServ), Aufgaben (Edupool)

    var iservZugang: IServZugang { IServZugang(server: einstellungen.iservServer, benutzer: einstellungen.iservBenutzer, passwort: iservPasswort, totp: totpGeheim) }

    /// Eine IServ-Sitzung; der Zwei-Faktor-Code wird – falls nötig und kein Schlüssel hinterlegt – hier abgefragt
    private func iservSitzung() -> IServ {
        IServ(iservZugang, erlaubteHosts: Set(einstellungen.iservHosts)) { [weak self] hinweis in
            await withCheckedContinuation { (k: CheckedContinuation<String?, Never>) in
                Task { @MainActor in
                    guard let self else { k.resume(returning: nil); return }
                    self.codeWarten?.resume(returning: nil)
                    self.codeWarten = k
                    self.codeHinweis = hinweis.isEmpty ? "6-stelligen Code aus deiner Authenticator-App eingeben." : hinweis
                }
            }
        }
    }

    /// Antwort aus dem Code-Fenster (nil = abgebrochen)
    func codeEingegeben(_ code: String?) {
        codeHinweis = nil
        codeWarten?.resume(returning: code)
        codeWarten = nil
    }

    func hostErlauben(_ h: String) async {
        if !einstellungen.iservHosts.contains(h) { einstellungen.iservHosts.append(h) }
        hostFrage = nil
        await moduleLaden(erzwingen: true)
    }

    /// Abgelehnte IServ-Zugangsdaten nicht immer wieder probieren (Kontosperre) – erst nach einer Änderung
    private var iservMerkmal: String { Mensa.merkmal(einstellungen.iservServer + "|" + einstellungen.iservBenutzer, iservPasswort) }

    func moduleLaden(erzwingen: Bool = false) async {
        guard !vorschau else { return }
        let e = einstellungen
        let d = UserDefaults.standard
        let alt = { (k: String, min: Double) in erzwingen || Date().timeIntervalSince1970 - d.double(forKey: k) > min * 60 }
        if (e.abwesenheiten || e.stoerungen) && iservZugang.vollstaendig {
            if d.string(forKey: "iservAbgelehnt") == iservMerkmal && !erzwingen {
                abwesendFehler = "IServ hat die Zugangsdaten abgelehnt – bitte prüfen."; stoerungenFehler = abwesendFehler
            } else {
                let s = iservSitzung()
                func fehler(_ f: Error) -> String {
                    if let i = f as? IServFehler {
                        if case .zugangsdaten = i { d.set(iservMerkmal, forKey: "iservAbgelehnt") }
                        if case .neuerHost(let h) = i { hostFrage = h }
                        return i.localizedDescription
                    }
                    return "IServ nicht erreichbar"
                }
                if e.abwesenheiten && alt("abwesendGeladen", 10) {
                    do {
                        let (st, q) = try await Abwesenheiten.laden(s, quelle: e.abwesendQuelle)
                        abwesend = st; abwesendFehler = ""
                        if q != e.abwesendQuelle { einstellungen.abwesendQuelle = q }
                        d.set(Date().timeIntervalSince1970, forKey: "abwesendGeladen")
                        d.removeObject(forKey: "iservAbgelehnt")
                    } catch { abwesendFehler = fehler(error) }
                }
                if e.stoerungen && alt("stoerungenGeladen", 15) {
                    do {
                        let (st, q) = try await Stoerungen.laden(s, quelle: e.stoerungQuelle)
                        stoerungen = st; stoerungenFehler = ""
                        if q != e.stoerungQuelle { einstellungen.stoerungQuelle = q }
                        d.set(Date().timeIntervalSince1970, forKey: "stoerungenGeladen")
                    } catch { stoerungenFehler = fehler(error) }
                }
            }
        }
        if e.aufgaben && !edupoolToken.isEmpty && alt("aufgabenGeladen", 30) {
            do {
                aufgaben = try await Aufgaben.laden(token: edupoolToken, farbe: e.aufgabenFarbe)
                aufgabenFehler = ""
                d.set(Date().timeIntervalSince1970, forKey: "aufgabenGeladen")
            } catch { aufgabenFehler = error.localizedDescription }
        }
        if e.mitteilungen { Melder.pruefen(stoerungen: e.stoerungen ? stoerungen : nil, aufgaben: e.aufgaben ? aufgaben : nil) }
        await untisLaden(erzwingen: erzwingen)
    }

    /// Edupool verbinden: Code holen, Freigabeseite öffnen, dann abholen (bis bestätigt oder abgelaufen)
    func edupoolVerbinden(oeffne: (URL) -> Void) async {
        do {
            let f = try await Aufgaben.freigabeStarten()
            edupoolCode = f.userCode
            oeffne(f.seite)
            while Date() < f.ablauf, edupoolCode != nil {
                try? await Task.sleep(nanoseconds: UInt64(f.intervall * 1_000_000_000))
                if let t = try await Aufgaben.freigabeAbholen(f) {
                    edupoolToken = t; einstellungen.aufgaben = true; edupoolCode = nil
                    meldung = "Mit Edupool verbunden"
                    await moduleLaden(erzwingen: true)
                    return
                }
            }
            if edupoolCode != nil { meldung = "Der Code ist abgelaufen – bitte noch einmal verbinden." }
        } catch { meldung = error.localizedDescription }
        edupoolCode = nil
    }

    /// Aktuellen Standort als Schule bzw. Zuhause merken
    func ortMerken(schule: Bool) async {
        guard let l = await ortung.einmal() else { meldung = "Standort nicht verfügbar – Ortungsdienste für Guten Morgen erlauben."; return }
        let o = Kontext.Ort(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        if schule { einstellungen.schulOrt = o } else { einstellungen.zuhauseOrt = o }
        meldung = schule ? "Schule gespeichert" : "Zuhause gespeichert"
        kontext = Kontext.bestimme(frei: frei, hier: o, schule: einstellungen.schulOrt, zuhause: einstellungen.zuhauseOrt)
    }

    /// Abwesenheiten, Störungen, Aufgaben: das Modul in Mein Tag (Scriptable) öffnen
    func meinTagURL(_ modul: String) -> URL? {
        let name = einstellungen.meinTagSkript.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "Mein-Tag"
        return URL(string: "scriptable:///run/\(name)?modul=\(modul)")
    }

    func weckerStellen(still: Bool = false) async {
        let w = naechsterWecker
        let text = await Wecker.stellen(w.datum)
        weckerText = text
        if !still { meldung = text }
        if ha.eingerichtet && !einstellungen.routine.isEmpty { await ha.weckzeitMelden(unterwegs ? nil : w.datum) }
    }

    /// Widget ohne App-Gruppe: Einstellungen und Token per kurzer Live-Aktivität übergeben (einmal je Änderung)
    func widgetUebergeben(erzwingen: Bool = false) async {
        #if canImport(ActivityKit)
        guard !vorschau, !MorgenAblage.gruppeDa else { return }
        let sig = einstellungen.json() + "|" + String(token.suffix(8)) + "|" + String(stabil(geheim.json()))
        guard erzwingen || UserDefaults.standard.string(forKey: "widgetUebergeben") != sig else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            if erzwingen { meldung = "Live-Aktivitäten sind aus – iPhone-Einstellungen → Guten Morgen → Live-Aktivitäten erlauben." }
            return
        }
        do {
            let a = try Activity.request(attributes: MorgenUebergabe(einstellungen: einstellungen.json(), token: token, geheim: geheim.json()),
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

    /// Gleiche Eingabe → gleiche Zahl, auch nach einem Neustart (hashValue ist je Start anders)
    private func stabil(_ s: String) -> UInt64 { s.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ UInt64($1) } }

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
        einstellungen.haeuser = ["Haus 2": ["2a", "2b", "2c"]]
        einstellungen.mensa = true; einstellungen.obst = true
        einstellungen.unterricht = (2...6).flatMap { t in [Unterricht(tag: t, stunde: "1", klasse: "5a", fach: "Mathe", raum: "R12"), Unterricht(tag: t, stunde: "4", klasse: "6b", fach: "Deutsch", raum: "R7")] }
        einstellungen.vertretungLink = "https://cloud.example.de/s/Beispiel"; einstellungen.obstKalender = "https://example.de/obst.ics"
        mensaPlan = MensaPlan(tage: [MensaTag(datum: Zeit.iso(schulTag), gerichte: [Gericht(menue: "Menü 1", text: "Spaghetti Bolognese", bestellt: true), Gericht(menue: "Menü 2", text: "Gemüsecurry mit Reis")])], guthaben: 23.4)
        obstTage = [Zeit.iso(schulTag)]
        schlaf = 7 * 3600 + 12 * 60
        weckerText = "Wecker gestellt: Dienstag, 06:15 Uhr"
    }
}

/// Fehler als Wert (für async let mit Ergebnis oder Fehler)
func versuch<T: Sendable>(_ f: @Sendable () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await f()) } catch { return .failure(error) }
}

/// Bereiche, die das Widget direkt öffnet
enum Bereich: String, Identifiable, Hashable {
    case mensa, vertretung, termine, wetter, post, abwesend, stoerungen, aufgaben, stundenplan
    var id: String { rawValue }
}
