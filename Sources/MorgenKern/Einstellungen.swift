import Foundation

/// Eine Home-Assistant-Aktion, z. B. „Alle Lichter aus“ = light.turn_off auf „all“
public struct HAAktion: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var dienst: String   // "light.turn_off"
    public var ziel: String     // entity_id oder "all"
    public init(name: String, dienst: String, ziel: String) { self.name = name; self.dienst = dienst; self.ziel = ziel }
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

    public init() {}

    enum CodingKeys: String, CodingKey {
        case weckzeiten, vorlauf, fruehestens, ferienFrei, feiertagFrei, bundesland, weckerAutomatisch, ortName, lat, lon, haAdresse,
             nacht, morgen, post, vertretung, vertretungLink, kuerzel, termine, erinnerungen, haeuser, mensa, mensaAdresse, mensaBenutzer, obst, obstKalender, farbton
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
    }

    /// Ist der Speiseplan vollständig eingerichtet (Passwort extra)?
    public var mensaBereit: Bool { mensa && !mensaAdresse.isEmpty && !mensaBenutzer.isEmpty }
    public var obstBereit: Bool { obst && !obstKalender.isEmpty }

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
    public init(mensa: String = "", freigabe: String = "") { self.mensa = mensa; self.freigabe = freigabe }
    public func json() -> String { (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}" }
    public static func aus(json: String) -> Geheimnisse? { try? JSONDecoder().decode(Geheimnisse.self, from: Data(json.utf8)) }
}
