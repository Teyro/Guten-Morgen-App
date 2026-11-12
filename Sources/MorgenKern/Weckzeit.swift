import Foundation

/// Ein Kalendertermin (aus EventKit, ohne EventKit-Abhängigkeit im Kern)
public struct Termin: Codable, Hashable, Sendable {
    public var titel: String
    public var start: Date
    public var ganztags: Bool
    public init(titel: String, start: Date, ganztags: Bool) { self.titel = titel; self.start = start; self.ganztags = ganztags }

    /// Doppelte aus mehreren Kalendern zusammenfassen: „🎂 Johanna Griese“, „Johanna Griese (1994)“, „Johanna Griese (Geburtstag)“
    /// am selben Tag = ein Termin; Geburtstage als „🎂 Name“
    public static func ohneDoppelte(_ termine: [Termin]) -> [Termin] {
        func kern(_ s: String) -> (name: String, geburtstag: Bool) {
            let geb = s.contains("🎂") || s.range(of: "geburtstag", options: .caseInsensitive) != nil
            var n = s.replacingOccurrences(of: #"\((\d{4}|[Gg]eburtstag)\)"#, with: "", options: .regularExpression)
            n = n.replacingOccurrences(of: #"(?i)geburtstag( von)?"#, with: "", options: .regularExpression)
            n = String(n.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-.:&")).contains($0) })
            return (n.split(whereSeparator: \.isWhitespace).joined(separator: " "), geb)
        }
        var gesehen: [String: Int] = [:]
        var aus: [Termin] = []
        for t in termine {
            let (name, geb) = kern(t.titel)
            let schluessel = Zeit.iso(t.start) + "|" + (t.ganztags ? "" : Zeit.uhrzeit(t.start)) + "|" + name.lowercased()
            if let i = gesehen[schluessel] {
                if geb { aus[i].titel = "🎂 " + name }
                continue
            }
            gesehen[schluessel] = aus.count
            var neu = t
            if geb && !name.isEmpty { neu.titel = "🎂 " + name }
            aus.append(neu)
        }
        return aus
    }
}

/// Ferien oder Feiertag
public struct FreierTag: Codable, Hashable, Sendable {
    public var von: String
    public var bis: String
    public var name: String
    public var ferien: Bool
    public init(von: String, bis: String, name: String, ferien: Bool) { self.von = von; self.bis = bis; self.name = name; self.ferien = ferien }
}

public struct Weckzeit: Hashable, Sendable {
    /// Minuten nach Mitternacht oder nil = kein Wecker
    public var minuten: Int?
    public var grund: String
    public var tag: Date
    public init(minuten: Int?, grund: String, tag: Date) { self.minuten = minuten; self.grund = grund; self.tag = tag }

    /// Wann am [tag] geweckt wird: Wochentags-Zeit, früher wegen des ersten Termins, frei in Ferien/an Feiertagen
    public static func berechne(tag: Date, termine: [Termin], frei: FreierTag?, e: MorgenEinstellungen) -> Weckzeit {
        let k = Zeit.kalender
        let standard = Zeit.minuten(e.weckzeiten[k.component(.weekday, from: tag)] ?? "")
        if let frei, (frei.ferien && e.ferienFrei) || (!frei.ferien && e.feiertagFrei) {
            return Weckzeit(minuten: nil, grund: frei.name, tag: tag)
        }
        guard let standard else { return Weckzeit(minuten: nil, grund: "kein Wecker am \(Zeit.wochentag(tag))", tag: tag) }
        let erster = termine.filter { !$0.ganztags && k.isDate($0.start, inSameDayAs: tag) }.min { $0.start < $1.start }
        if let erster {
            let start = k.component(.hour, from: erster.start) * 60 + k.component(.minute, from: erster.start)
            let frueh = max(start - e.vorlauf, Zeit.minuten(e.fruehestens) ?? 0)
            if frueh < standard {
                return Weckzeit(minuten: frueh, grund: "früher wegen „\(erster.titel)“ um \(Zeit.hhmm(start))", tag: tag)
            }
        }
        return Weckzeit(minuten: standard, grund: "", tag: tag)
    }

    /// Der nächste Wecktag: heute vor 4 Uhr = heute, sonst morgen
    public static func naechsterTag(_ jetzt: Date = Date()) -> Date {
        let k = Zeit.kalender
        let heute = k.startOfDay(for: jetzt)
        return k.component(.hour, from: jetzt) < 4 ? heute : (k.date(byAdding: .day, value: 1, to: heute) ?? heute)
    }

    /// Weckzeit als Datum (für den Wecker)
    public var datum: Date? {
        guard let minuten else { return nil }
        return Zeit.kalender.date(bySettingHour: minuten / 60, minute: minuten % 60, second: 0, of: tag)
    }
}

public enum FreieTage {
    /// Ferien und Feiertage (OpenHolidays, ohne Schlüssel) für das Bundesland – ein gutes Jahr voraus
    public static func laden(bundesland: String, jetzt: Date = Date()) async throws -> [FreierTag] {
        let k = Zeit.kalender
        let von = Zeit.iso(k.date(byAdding: .day, value: -7, to: jetzt) ?? jetzt)
        let bis = Zeit.iso(k.date(byAdding: .day, value: 400, to: jetzt) ?? jetzt)
        let q = "countryIsoCode=DE&subdivisionCode=DE-\(bundesland)&languageIsoCode=DE&validFrom=\(von)&validTo=\(bis)"
        async let f = Netz.json(URL(string: "https://openholidaysapi.org/SchoolHolidays?\(q)")!)
        async let t = Netz.json(URL(string: "https://openholidaysapi.org/PublicHolidays?\(q)")!)
        return lesen(ferien: try await f, feiertage: try await t, bundesland: bundesland)
    }

    public static func lesen(ferien: Any, feiertage: Any, bundesland: String) -> [FreierTag] {
        func name(_ x: [String: Any]) -> String {
            let n = x["name"] as? [[String: Any]] ?? []
            return (n.first { $0["language"] as? String == "DE" } ?? n.first)?["text"] as? String ?? "frei"
        }
        var erg: [FreierTag] = []
        for x in ferien as? [[String: Any]] ?? [] {
            if let v = x["startDate"] as? String, let b = x["endDate"] as? String { erg.append(FreierTag(von: v, bis: b, name: name(x), ferien: true)) }
        }
        for x in feiertage as? [[String: Any]] ?? [] {
            let landweit = x["nationwide"] as? Bool ?? true
            let hier = (x["subdivisions"] as? [[String: Any]] ?? []).contains { $0["code"] as? String == "DE-\(bundesland)" }
            guard landweit || hier, let v = x["startDate"] as? String, let b = x["endDate"] as? String else { continue }
            erg.append(FreierTag(von: v, bis: b, name: name(x), ferien: false))
        }
        return erg
    }

    /// Feiertag geht vor Ferien
    public static func am(_ tage: [FreierTag], _ tag: Date) -> FreierTag? {
        let t = Zeit.iso(tag)
        let treffer = tage.filter { $0.von <= t && t <= $0.bis }
        return treffer.first { !$0.ferien } ?? treffer.first
    }
}

/// Kleine Netzhilfe (JSON, Text, Daten) mit Zeitlimit
public enum Netz {
    public static func daten(_ url: URL, methode: String = "GET", kopf: [String: String] = [:], koerper: Data? = nil, zeit: TimeInterval = 15) async throws -> (Data, Int) {
        var r = URLRequest(url: url, timeoutInterval: zeit)
        r.httpMethod = methode
        kopf.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        r.httpBody = koerper
        let (d, a) = try await URLSession.shared.data(for: r)
        return (d, (a as? HTTPURLResponse)?.statusCode ?? 0)
    }
    public static func json(_ url: URL, methode: String = "GET", kopf: [String: String] = [:], koerper: Data? = nil) async throws -> Any {
        let (d, s) = try await daten(url, methode: methode, kopf: kopf, koerper: koerper)
        guard (200..<300).contains(s) else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: d)
    }
}
