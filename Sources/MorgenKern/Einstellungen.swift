import Foundation

/// Eine Home-Assistant-Aktion, z. B. „Alle Lichter aus“ = light.turn_off auf „all“
public struct HAAktion: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var dienst: String   // "light.turn_off"
    public var ziel: String     // entity_id oder "all"
    public init(name: String, dienst: String, ziel: String) { self.name = name; self.dienst = dienst; self.ziel = ziel }
}

/// Ein Schritt der Morgenroutine in Home Assistant, z. B. „Heizung Bad“ 20 Minuten vor dem Wecken
public struct RoutinenSchritt: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var dienst: String   // "climate.set_temperature", "light.turn_on", "script.turn_on"
    public var ziel: String     // entity_id
    /// Minuten relativ zum Wecker: −20 = 20 Minuten vorher, 0 = beim Wecken, 5 = danach
    public var minuten: Int
    /// Licht langsam heller werden lassen: Sekunden (0 = sofort) – nur bei light.turn_on
    public var langsam: Int = 0
    public init(name: String, dienst: String, ziel: String, minuten: Int, langsam: Int = 0) {
        self.name = name; self.dienst = dienst; self.ziel = ziel; self.minuten = minuten; self.langsam = langsam
    }
}

/// Alle Einstellungen (ohne Token – der liegt im Schlüsselbund bzw. wird dem Widget übergeben)
public struct MorgenEinstellungen: Codable, Hashable, Sendable {
    /// Weckzeit je Wochentag (1 = Sonntag … 7 = Samstag wie Calendar.weekday), "" = kein Wecker
    public var weckzeiten: [Int: String] = [1: "", 2: "06:15", 3: "06:15", 4: "06:15", 5: "06:15", 6: "06:15", 7: ""]
    /// so viele Minuten vor dem ersten Termin wecken, falls das früher ist
    public var vorlauf = 75
    public var fruehestens = "05:00"
    public var ferienFrei = true
    public var feiertagFrei = true
    public var bundesland = "HH"
    public var weckerAutomatisch = true
    public var ortName = "Hamburg"
    public var lat = 53.5511
    public var lon = 9.9937
    public var haAdresse = ""
    public var nacht: [HAAktion] = [HAAktion(name: "Alle Lichter aus", dienst: "light.turn_off", ziel: "all")]
    public var morgen: [HAAktion] = []
    public var post = true
    public var vertretung = true
    public var vertretungLink = ""
    public var kuerzel = ""
    public var termine = true
    public var erinnerungen = true
    /// Häuser der Klassen („Haus 1“: [1a, 1b]) – damit die Vertretung sagt, wohin
    public var haeuser: [String: [String]] = [:]
    /// Speiseplan der Kantine (PCA-Portal; Passwort im Schlüsselbund)
    public var mensa = false
    public var mensaAdresse = ""
    public var mensaBenutzer = ""
    /// Öffentlicher Kalender mit den Schulobst-Tagen (ICS-Link)
    public var obst = false
    public var obstKalender = ""
    /// Farbton von App und Widget (siehe Farbton im App-Teil)
    public var farbton = "morgenrot"
    /// Kantine: Stichwörter für Lieblingsessen und zum Meiden (wie im Kantinen-Widget)
    public var favoriten = ""
    public var meiden = ""
    /// Mit ⭐ / 👎 gemerkte Gerichte (genauer Text, wie im Kantinen-Skript)
    public var lieblingsGerichte: [String] = []
    public var nichtLecker: [String] = []
    /// IServ (Abwesenheiten, Störungen) – Passwort und 2FA-Schlüssel im Schlüsselbund
    public var iservServer = ""
    public var iservBenutzer = ""
    /// Bestätigte Anmeldeseiten außerhalb von IServ (z. B. Schuldock)
    public var iservHosts: [String] = []
    public var abwesenheiten = false
    /// Nur diese Klassen („2a, 2b“), leer = alle
    public var abwesendKlassen = ""
    /// Widget: nur Vorname + Initiale
    public var sichtschutz = true
    public var abwesendQuelle: IServQuelle?
    public var stoerungen = false
    public var erledigteZeigen = false
    public var stoerungQuelle: IServQuelle?
    /// Edupool-Aufgaben (Token im Schlüsselbund)
    public var aufgaben = false
    public var aufgabenFarbe = "#76a5af"
    /// Mitteilungen bei neuen Störungsmeldungen und neuen/verschobenen Aufgaben
    public var mitteilungen = false
    /// Orte für die Anordnung (Schule zuerst bzw. Termine und Post zuerst)
    public var schulOrt: Kontext.Ort?
    public var zuhauseOrt: Kontext.Ort?
    /// Kollegium: Kürzel → Name (aus Mein Tag übernommen) – für „Es fehlen“
    public var kollegium: [String: String] = [:]
    /// Name des Scriptable-Skripts für Abwesenheiten, Störungen und Aufgaben
    public var meinTagSkript = "Mein-Tag"
    /// Schlaf aus Apple Health zeigen und den Nachtmodus als Schlaf eintragen
    public var gesundheit = false
    /// Eigener Stundenplan: Klingelzeiten der Schule und die eigenen Stunden
    public var schulzeiten: [Schulzeit] = Schulzeit.standard
    public var unterricht: [Unterricht] = []
    /// Mitteilung 5 Minuten vor einer Hofaufsicht
    public var aufsichtErinnern = true
    /// Live-Aktivität im Schulalltag (Sperrbildschirm, Dynamic Island, Apple Watch)
    public var schulAktivitaet = true
    /// Anfahrt: Fahrzeit über Apple Karten, früher wecken, wenn es sonst knapp wird
    public var fahrt = false
    /// "auto", "oepnv", "fuss"
    public var fahrtArt = "auto"
    /// Minuten vom Wecken bis zum Losfahren
    public var fertig = 45
    /// so viele Minuten vor der ersten Stunde da sein
    public var puffer = 10
    /// Bei Glätte oder Schnee so viele Minuten früher wecken (0 = aus)
    public var glaetteFrueher = 15
    /// Morgenroutine in Home Assistant (läuft dort als Automation, gesteuert über die Weckzeit)
    public var routine: [RoutinenSchritt] = []
    /// WebUntis: eigener Plan, Klassen-Übersicht (Passwort im Schlüsselbund)
    public var untisAn = false
    public var untisLink = ""
    /// Schule laut WebUntis (z. B. „hh5586“); leer = aus der Url
    public var untisSchule = ""
    public var untisBenutzer = ""
    /// Grundwoche aus WebUntis als „Mein Stundenplan“ übernehmen
    public var untisUebernehmen = true
    /// Unterwegs (nicht zu Hause, z. B. bei Verwandten): bei „Gute Nacht“ diese Aktionen statt der normalen, keine Morgenroutine
    public var unterwegsAn = false
    public var unterwegsAktionen: [HAAktion] = []
    /// Ab dieser Entfernung von „Zuhause“ gilt man als unterwegs (Meter)
    public var zuhauseRadius = 1500

    public init() {}

    enum CodingKeys: String, CodingKey {
        case weckzeiten, vorlauf, fruehestens, ferienFrei, feiertagFrei, bundesland, weckerAutomatisch, ortName, lat, lon, haAdresse,
             nacht, morgen, post, vertretung, vertretungLink, kuerzel, termine, erinnerungen, haeuser, mensa, mensaAdresse, mensaBenutzer, obst, obstKalender, farbton,
             favoriten, meiden, kollegium, meinTagSkript, gesundheit, lieblingsGerichte, nichtLecker,
             iservServer, iservBenutzer, iservHosts, abwesenheiten, abwesendKlassen, sichtschutz, abwesendQuelle, stoerungen, erledigteZeigen, stoerungQuelle, aufgaben, aufgabenFarbe,
             mitteilungen, schulOrt, zuhauseOrt,
             schulzeiten, unterricht, aufsichtErinnern, schulAktivitaet, fahrt, fahrtArt, fertig, puffer, glaetteFrueher, routine,
             untisAn, untisLink, untisSchule, untisBenutzer, untisUebernehmen, unterwegsAn, unterwegsAktionen, zuhauseRadius
    }

    /// Ältere/fehlende Felder → Standard
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = MorgenEinstellungen()
        func w<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil ?? d }
        weckzeiten = w(.weckzeiten, s.weckzeiten); vorlauf = w(.vorlauf, s.vorlauf); fruehestens = w(.fruehestens, s.fruehestens)
        ferienFrei = w(.ferienFrei, s.ferienFrei); feiertagFrei = w(.feiertagFrei, s.feiertagFrei); bundesland = w(.bundesland, s.bundesland)
        weckerAutomatisch = w(.weckerAutomatisch, s.weckerAutomatisch); ortName = w(.ortName, s.ortName); lat = w(.lat, s.lat); lon = w(.lon, s.lon)
        haAdresse = w(.haAdresse, s.haAdresse); nacht = w(.nacht, s.nacht); morgen = w(.morgen, s.morgen); post = w(.post, s.post)
        vertretung = w(.vertretung, s.vertretung); vertretungLink = w(.vertretungLink, s.vertretungLink); kuerzel = w(.kuerzel, s.kuerzel)
        termine = w(.termine, s.termine); erinnerungen = w(.erinnerungen, s.erinnerungen)
        haeuser = w(.haeuser, s.haeuser); mensa = w(.mensa, s.mensa); mensaAdresse = w(.mensaAdresse, s.mensaAdresse)
        mensaBenutzer = w(.mensaBenutzer, s.mensaBenutzer); obst = w(.obst, s.obst); obstKalender = w(.obstKalender, s.obstKalender)
        farbton = w(.farbton, s.farbton)
        favoriten = w(.favoriten, s.favoriten); meiden = w(.meiden, s.meiden); kollegium = w(.kollegium, s.kollegium)
        meinTagSkript = w(.meinTagSkript, s.meinTagSkript); gesundheit = w(.gesundheit, s.gesundheit)
        lieblingsGerichte = w(.lieblingsGerichte, s.lieblingsGerichte); nichtLecker = w(.nichtLecker, s.nichtLecker)
        iservServer = w(.iservServer, s.iservServer); iservBenutzer = w(.iservBenutzer, s.iservBenutzer); iservHosts = w(.iservHosts, s.iservHosts)
        abwesenheiten = w(.abwesenheiten, s.abwesenheiten); abwesendKlassen = w(.abwesendKlassen, s.abwesendKlassen); sichtschutz = w(.sichtschutz, s.sichtschutz)
        abwesendQuelle = (try? c.decodeIfPresent(IServQuelle.self, forKey: .abwesendQuelle)) ?? nil
        stoerungen = w(.stoerungen, s.stoerungen); erledigteZeigen = w(.erledigteZeigen, s.erledigteZeigen)
        stoerungQuelle = (try? c.decodeIfPresent(IServQuelle.self, forKey: .stoerungQuelle)) ?? nil
        aufgaben = w(.aufgaben, s.aufgaben); aufgabenFarbe = w(.aufgabenFarbe, s.aufgabenFarbe)
        mitteilungen = w(.mitteilungen, s.mitteilungen)
        schulOrt = (try? c.decodeIfPresent(Kontext.Ort.self, forKey: .schulOrt)) ?? nil
        zuhauseOrt = (try? c.decodeIfPresent(Kontext.Ort.self, forKey: .zuhauseOrt)) ?? nil
        schulzeiten = w(.schulzeiten, s.schulzeiten); unterricht = w(.unterricht, s.unterricht)
        aufsichtErinnern = w(.aufsichtErinnern, s.aufsichtErinnern); schulAktivitaet = w(.schulAktivitaet, s.schulAktivitaet)
        fahrt = w(.fahrt, s.fahrt); fahrtArt = w(.fahrtArt, s.fahrtArt); fertig = w(.fertig, s.fertig); puffer = w(.puffer, s.puffer)
        glaetteFrueher = w(.glaetteFrueher, s.glaetteFrueher); routine = w(.routine, s.routine)
        untisAn = w(.untisAn, s.untisAn); untisLink = w(.untisLink, s.untisLink); untisBenutzer = w(.untisBenutzer, s.untisBenutzer)
        untisSchule = w(.untisSchule, s.untisSchule)
        untisUebernehmen = w(.untisUebernehmen, s.untisUebernehmen); unterwegsAn = w(.unterwegsAn, s.unterwegsAn)
        unterwegsAktionen = w(.unterwegsAktionen, s.unterwegsAktionen); zuhauseRadius = w(.zuhauseRadius, s.zuhauseRadius)
    }

    /// Unterwegs? (nur mit Schalter und gespeichertem Zuhause; ohne Standort: nein)
    public func unterwegs(hier: Kontext.Ort?) -> Bool {
        guard unterwegsAn, let z = zuhauseOrt, let h = hier else { return false }
        return z.abstand(h) > Double(zuhauseRadius)
    }

    /// Der eigene Tagesablauf (Stunden, Vertretung, Aufsichten)
    public func schultag(_ datum: Date, vertretung: VertretungsPlan?) -> [Block] {
        Stundenplan.tag(datum, zeiten: schulzeiten, unterricht: unterricht, vertretung: vertretung, haeuser: haeuser)
    }

    /// Weckzeit mit allem: Wochentag/Termine, dann Glätte, dann Anfahrt (Fahrzeit in Minuten, falls bekannt)
    public func wecker(tag: Date, termine: [Termin], frei: FreierTag?, wetter: WetterTag?, vertretung: VertretungsPlan?, fahrtMinuten: Int?) -> Weckzeit {
        var w = Weckzeit.berechne(tag: tag, termine: termine, frei: frei, e: self)
        let frueh = Zeit.minuten(fruehestens) ?? 0
        w = WetterWecken.weckzeit(w, wetter: wetter, minuten: glaetteFrueher, fruehestens: frueh)
        if fahrt, let f = fahrtMinuten, let b = Stundenplan.beginn(schultag(tag, vertretung: vertretung)) {
            let k = Zeit.kalender
            w = Anfahrt.weckzeit(w, beginn: k.component(.hour, from: b) * 60 + k.component(.minute, from: b), fahrtMinuten: f, puffer: puffer,
                                 fertig: fertig, fruehestens: frueh, art: fahrtArt == "oepnv" ? "mit Bus und Bahn" : fahrtArt == "fuss" ? "zu Fuß" : "mit dem Auto")
        }
        return w
    }

    /// Ist der Speiseplan vollständig eingerichtet (Passwort extra)?
    public var mensaBereit: Bool { mensa && !mensaAdresse.isEmpty && !mensaBenutzer.isEmpty }
    public var obstBereit: Bool { obst && !obstKalender.isEmpty }
    public var klassenListe: [String] { abwesendKlassen.split(whereSeparator: { ",; ".contains($0) }).map(String.init) }

    public func json() -> String { (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}" }
    public static func aus(json: String) -> MorgenEinstellungen? { try? JSONDecoder().decode(MorgenEinstellungen.self, from: Data(json.utf8)) }
}

/// Gemeinsame Ablage: App-Gruppe, wenn die Signatur sie erlaubt – sonst die eigene des Widgets (Übergabe per Live-Aktivität)
public enum MorgenAblage {
    public static let gruppe = "group.de.teyro.gutenmorgen"
    public static var defaults: UserDefaults { UserDefaults(suiteName: gruppe) ?? .standard }
    public static var gruppeDa: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppe) != nil }

    public static func einstellungen(_ d: UserDefaults = defaults) -> MorgenEinstellungen? {
        d.string(forKey: "einstellungen").flatMap(MorgenEinstellungen.aus(json:))
    }
    public static func speichern(_ e: MorgenEinstellungen, token: String, geheim: Geheimnisse = Geheimnisse(), _ d: UserDefaults = defaults) {
        d.set(e.json(), forKey: "einstellungen")
        d.set(token, forKey: "token")
        d.set(geheim.json(), forKey: "geheim")
    }
    public static func token(_ d: UserDefaults = defaults) -> String { d.string(forKey: "token") ?? "" }
    public static func geheim(_ d: UserDefaults = defaults) -> Geheimnisse { d.string(forKey: "geheim").flatMap(Geheimnisse.aus(json:)) ?? Geheimnisse() }
}

/// Weitere Passwörter (Kantine, Freigabe des Vertretungsplans) – in der App im Schlüsselbund, fürs Widget mit übergeben
public struct Geheimnisse: Codable, Hashable, Sendable {
    public var mensa = ""
    public var freigabe = ""
    public var iserv = ""
    public var totp = ""
    public var edupool = ""
    public init(mensa: String = "", freigabe: String = "", iserv: String = "", totp: String = "", edupool: String = "") {
        self.mensa = mensa; self.freigabe = freigabe; self.iserv = iserv; self.totp = totp; self.edupool = edupool
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func w(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil ?? "" }
        mensa = w(.mensa); freigabe = w(.freigabe); iserv = w(.iserv); totp = w(.totp); edupool = w(.edupool)
    }
    public func json() -> String { (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}" }
    public static func aus(json: String) -> Geheimnisse? { try? JSONDecoder().decode(Geheimnisse.self, from: Data(json.utf8)) }
}

/// Übernahme aus Scriptable („Mein Tag → An Guten Morgen übergeben“): gutenmorgen://import?d=<base64url-JSON>
public struct ImportDaten: Codable, Sendable {
    public struct Kantine: Codable, Sendable { public var adresse: String?; public var benutzer: String?; public var passwort: String?; public var favoriten: String?; public var meiden: String?; public var gut: [String]?; public var schlecht: [String]? }
    public var kuerzel: String?
    public var link: String?
    public var passwort: String?
    public var haeuser: [String: [String]]?
    public var kollegium: [String: String]?
    public var obstKalender: String?
    public var skript: String?
    public var kantine: Kantine?
    public struct IServDaten: Codable, Sendable { public var server: String?; public var benutzer: String?; public var passwort: String?; public var totp: String?; public var klassen: String? }
    public var iserv: IServDaten?
    public struct Edupool: Codable, Sendable { public var token: String?; public var farbe: String? }
    public var edupool: Edupool?

    public static func aus(url: URL) -> ImportDaten? {
        guard let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        var b = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let daten = Data(base64Encoded: b) else { return nil }
        return try? JSONDecoder().decode(ImportDaten.self, from: daten)
    }

    /// Kurze Liste, was übernommen wird (ohne Passwörter)
    public var zusammenfassung: [String] {
        var t: [String] = []
        if let k = kuerzel, !k.isEmpty { t.append("Kürzel \(k)") }
        if let l = link, !l.isEmpty { t.append("Vertretungsplan-Ordner") }
        if let h = haeuser, !h.isEmpty { t.append("\(h.count) Häuser") }
        if let k = kollegium, !k.isEmpty { t.append("\(k.count) Namen im Kollegium") }
        if let o = obstKalender, !o.isEmpty { t.append("Schulobst-Kalender") }
        if let m = kantine, m.benutzer?.isEmpty == false { t.append("Kantine (\(m.benutzer!))") }
        if let f = kantine?.favoriten, !f.isEmpty { t.append("Lieblingsessen") }
        if let i = iserv, i.benutzer?.isEmpty == false { t.append("IServ (\(i.benutzer!)" + (i.totp?.isEmpty == false ? ", mit 2FA-Schlüssel" : "") + ")") }
        if edupool?.token?.isEmpty == false { t.append("Edupool-Freigabe") }
        return t
    }

    /// In die Einstellungen übernehmen; Rückgabe: Passwörter – leer = unverändert
    public func anwenden(_ e: inout MorgenEinstellungen) -> Geheimnisse {
        if let k = kuerzel, !k.isEmpty { e.kuerzel = k }
        if let l = link, !l.isEmpty { e.vertretungLink = l; e.vertretung = true }
        if let h = haeuser, !h.isEmpty { e.haeuser = h }
        if let k = kollegium, !k.isEmpty { e.kollegium = k }
        if let o = obstKalender, !o.isEmpty { e.obstKalender = o; e.obst = true }
        if let s = skript, !s.isEmpty { e.meinTagSkript = s }
        if let m = kantine {
            if let a = m.adresse, !a.isEmpty { e.mensaAdresse = a }
            if let b = m.benutzer, !b.isEmpty { e.mensaBenutzer = b; e.mensa = true }
            if let f = m.favoriten { e.favoriten = f }
            if let x = m.meiden { e.meiden = x }
            if let g = m.gut, !g.isEmpty { e.lieblingsGerichte = g }
            if let s = m.schlecht, !s.isEmpty { e.nichtLecker = s }
        }
        if let i = iserv {
            if let s = i.server, !s.isEmpty { e.iservServer = IServ.bereinige(s) }
            if let b = i.benutzer, !b.isEmpty { e.iservBenutzer = b; e.abwesenheiten = true; e.stoerungen = true }
            if let k = i.klassen { e.abwesendKlassen = k }
        }
        if let f = edupool?.farbe, !f.isEmpty { e.aufgabenFarbe = f }
        if edupool?.token?.isEmpty == false { e.aufgaben = true }
        return Geheimnisse(mensa: kantine?.passwort ?? "", freigabe: passwort ?? "", iserv: iserv?.passwort ?? "", totp: iserv?.totp ?? "", edupool: edupool?.token ?? "")
    }
}
