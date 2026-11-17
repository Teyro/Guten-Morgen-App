import Foundation

public struct WetterTag: Codable, Hashable, Sendable {
    public var code: Int
    public var max: Double
    public var min: Double
    public var regen: Int
    public var wind: Double
    public init(code: Int, max: Double, min: Double, regen: Int, wind: Double) { self.code = code; self.max = max; self.min = min; self.regen = regen; self.wind = wind }
}

/// Ein 15-Minuten-Schritt (Open-Meteo minutely_15). [regen] = Niederschlag der vorigen 15 Minuten in mm,
/// [chance] = Regenwahrscheinlichkeit der Stunde (nur stündlich verfügbar).
public struct WetterSchritt: Codable, Hashable, Sendable {
    public var zeit: Date
    public var code: Int
    public var temp: Double?
    public var regen: Double
    public var chance: Int?
    public var boeen: Double?
    public init(zeit: Date, code: Int, temp: Double?, regen: Double, chance: Int?, boeen: Double?) {
        self.zeit = zeit; self.code = code; self.temp = temp; self.regen = regen; self.chance = chance; self.boeen = boeen
    }
}

/// Wetter in einer Hofpause: Symbol, Temperatur und ob es vermutlich eine Regenpause (drinnen) wird.
public struct PausenWetter: Hashable, Sendable {
    public var code: Int
    public var temp: Double?
    public var regen: Double
    public var chance: Int
    public var boeen: Double
    /// Regenpause wahrscheinlich (Regen, Gewitter, Sturm oder starker Schneefall)
    public var drinnen: Bool
    /// „Regenpause“, „Gewitter – Regenpause“, „Schnee“, „trocken“ …
    public var text: String
    public var symbol: String { Wetter.symbol(code) }
}

public struct Wetter: Codable, Hashable, Sendable {
    public var jetzt: Double?
    public var jetztCode: Int?
    public var heute: WetterTag?
    public var morgen: WetterTag?
    public var stand: Date
    /// 15-Minuten-Verlauf für heute und morgen (für die Hofpausen); fehlt in älteren gespeicherten Ständen
    public var verlauf: [WetterSchritt]? = nil
    public init(jetzt: Double?, jetztCode: Int?, heute: WetterTag?, morgen: WetterTag?, stand: Date, verlauf: [WetterSchritt]? = nil) {
        self.jetzt = jetzt; self.jetztCode = jetztCode; self.heute = heute; self.morgen = morgen; self.stand = stand; self.verlauf = verlauf
    }

    public static let beschreibung: [Int: String] = [
        0: "klar", 1: "überwiegend klar", 2: "teils bewölkt", 3: "bedeckt", 45: "neblig", 48: "neblig mit Reif",
        51: "leichter Nieselregen", 53: "Nieselregen", 55: "starker Nieselregen", 56: "gefrierender Nieselregen", 57: "gefrierender Nieselregen",
        61: "leichter Regen", 63: "Regen", 65: "starker Regen", 66: "gefrierender Regen", 67: "gefrierender Regen",
        71: "leichter Schneefall", 73: "Schneefall", 75: "starker Schneefall", 77: "Schneegriesel",
        80: "Regenschauer", 81: "Regenschauer", 82: "heftige Regenschauer", 85: "Schneeschauer", 86: "Schneeschauer",
        95: "Gewitter", 96: "Gewitter mit Hagel", 99: "Gewitter mit Hagel",
    ]
    public static func symbol(_ code: Int) -> String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// Open-Meteo (ohne Schlüssel)
    public static func laden(lat: Double, lon: Double) async throws -> Wetter {
        let url = URL(string: String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f", lat, lon)
            + "&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max"
            + "&minutely_15=temperature_2m,precipitation,weather_code,wind_gusts_10m&hourly=precipitation_probability"
            + "&timezone=Europe%2FBerlin&forecast_days=2")!
        return lesen(try await Netz.json(url))
    }

    public static func lesen(_ j: Any, jetzt: Date = Date()) -> Wetter {
        let o = j as? [String: Any] ?? [:]
        let c = o["current"] as? [String: Any] ?? [:]
        let d = o["daily"] as? [String: Any] ?? [:]
        func tag(_ i: Int) -> WetterTag? {
            func zahl(_ k: String) -> Double? { ((d[k] as? [Any])?.dropFirst(i).first as? NSNumber)?.doubleValue }
            guard let code = zahl("weather_code"), let mx = zahl("temperature_2m_max"), let mn = zahl("temperature_2m_min") else { return nil }
            return WetterTag(code: Int(code), max: mx, min: mn, regen: Int(zahl("precipitation_probability_max") ?? 0), wind: zahl("wind_speed_10m_max") ?? 0)
        }
        return Wetter(jetzt: (c["temperature_2m"] as? NSNumber)?.doubleValue, jetztCode: (c["weather_code"] as? NSNumber)?.intValue,
                      heute: tag(0), morgen: tag(1), stand: jetzt, verlauf: verlauf(o))
    }

    /// 15-Minuten-Verlauf aus der Antwort („minutely_15“), mit der Regenwahrscheinlichkeit der jeweiligen Stunde
    static func verlauf(_ o: [String: Any]) -> [WetterSchritt]? {
        guard let m = o["minutely_15"] as? [String: Any], let zeiten = m["time"] as? [String] else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Berlin"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        func reihe(_ quelle: [String: Any], _ k: String) -> [Double?] { (quelle[k] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue } }
        let h = o["hourly"] as? [String: Any] ?? [:]
        var chance: [String: Int] = [:]   // „2026-11-17T10“ → %
        for (z, p) in zip(h["time"] as? [String] ?? [], reihe(h, "precipitation_probability")) { if let p { chance[String(z.prefix(13))] = Int(p) } }
        let code = reihe(m, "weather_code"), temp = reihe(m, "temperature_2m"), regen = reihe(m, "precipitation"), boeen = reihe(m, "wind_gusts_10m")
        func wert(_ r: [Double?], _ i: Int) -> Double? { i < r.count ? r[i] : nil }
        let schritte = zeiten.enumerated().compactMap { i, z -> WetterSchritt? in
            guard let t = f.date(from: z), let c = wert(code, i) else { return nil }
            return WetterSchritt(zeit: t, code: Int(c), temp: wert(temp, i), regen: wert(regen, i) ?? 0, chance: chance[String(z.prefix(13))], boeen: wert(boeen, i))
        }
        return schritte.isEmpty ? nil : schritte
    }

    /// Wie schlimm ist ein Wettercode für eine Hofpause? (Gewitter > starker Regen > Regen > Schnee > Niesel > Nebel > Wolken > Sonne)
    static func schwere(_ c: Int) -> Int {
        switch c {
        case 95...99: return 9
        case 65, 67, 82: return 8
        case 61, 63, 66, 80, 81: return 7
        case 71...77, 85, 86: return 6
        case 51...57: return 5
        case 45, 48: return 3
        case 3: return 2
        case 2: return 1
        default: return 0
        }
    }

    /// Wetter in einer Pause [von, bis) aus dem 15-Minuten-Verlauf, oder nil (keine Daten für diese Zeit).
    /// Regenpause: Gewitter, Böen ab 70 km/h, Regen ab 0,3 mm in der Pause bzw. gemeldeter Regen mit ≥ 60 %,
    /// bei Schnee erst ab 1,5 mm (bei Schnee geht es meist trotzdem raus).
    public func pause(von: Date, bis: Date) -> PausenWetter? {
        // Ein Schritt gilt für die 15 Minuten VOR seinem Zeitpunkt. Er zählt, wenn er mindestens zur Hälfte in der Pause
        // liegt (sonst machte Regen um 12:15–12:30 eine Pause bis 12:20 zur Regenpause); fehlt so einer, der mit der größten Überschneidung.
        func ueberlappung(_ x: WetterSchritt) -> TimeInterval {
            min(x.zeit, bis).timeIntervalSince(max(x.zeit.addingTimeInterval(-15 * 60), von))
        }
        let alle = (verlauf ?? []).filter { ueberlappung($0) > 0 }
        let haelfte = alle.filter { ueberlappung($0) >= 7.5 * 60 }
        let s = !haelfte.isEmpty ? haelfte : alle.max(by: { ueberlappung($0) < ueberlappung($1) }).map { [$0] } ?? []
        guard let code = s.map(\.code).max(by: { Wetter.schwere($0) < Wetter.schwere($1) }) else { return nil }
        let regen = s.reduce(0) { $0 + $1.regen }
        let chance = s.compactMap(\.chance).max() ?? 0
        let boeen = s.compactMap(\.boeen).max() ?? 0
        let temps = s.compactMap(\.temp)
        let temp = temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
        let gewitter = (95...99).contains(code)
        let schnee = (71...77).contains(code) || code == 85 || code == 86
        let nass = (51...67).contains(code) || (80...82).contains(code)
        let sturm = boeen >= 70
        let drinnen = gewitter || sturm || (schnee ? regen >= 1.5 : (regen >= 0.3 || (nass && chance >= 60)))
        let text: String
        if gewitter { text = "Gewitter – Regenpause" }
        else if sturm { text = "Sturm – Regenpause" }
        else if drinnen { text = schnee ? "starker Schneefall – Regenpause" : "Regenpause" }
        else if schnee { text = "Schnee" }
        else if nass { text = "vielleicht Nieselregen" }
        else { text = "trocken" }
        return PausenWetter(code: code, temp: temp, regen: regen, chance: chance, boeen: boeen, drinnen: drinnen, text: text)
    }

    /// Schnee oder Schneegriesel
    public static func schnee(_ t: WetterTag) -> Bool { (71...77).contains(t.code) || t.code == 85 || t.code == 86 }

    /// Glatt: gefrierender Regen/Niesel, Schnee, oder Frost mit Niederschlag
    public static func glaette(_ t: WetterTag) -> Bool {
        [56, 57, 66, 67].contains(t.code) || schnee(t) || (t.min <= 0.5 && t.regen >= 40)
    }

    /// Kurze Hinweise: „Schirm mitnehmen“, „Scheibe kratzen“ …
    public static func hinweise(_ t: WetterTag, auto: Bool) -> [String] {
        var h: [String] = []
        if glaette(t) { h.append("Vorsicht, glatt") }
        if t.regen >= 50 && !schnee(t) { h.append("Schirm mitnehmen") }
        if auto && t.min <= 0 { h.append("Scheibe kratzen") }
        if t.max <= 3 { h.append("Warm anziehen") }
        if t.wind >= 50 { h.append("Sturm") }
        return h
    }

    /// „Draußen 4 Grad, bedeckt. Heute 2 bis 7 Grad, Regen wahrscheinlich (70 %).“
    public func satz(morgen istMorgen: Bool = false) -> String {
        guard let t = istMorgen ? morgen : heute else { return "" }
        var s = ""
        if !istMorgen, let j = jetzt { s += "Draußen sind es \(Int(j.rounded())) Grad, \(Wetter.beschreibung[jetztCode ?? t.code] ?? "wechselhaft"). " }
        s += (istMorgen ? "Morgen " : "Heute ") + "\(Int(t.min.rounded())) bis \(Int(t.max.rounded())) Grad"
        if t.regen >= 60 { s += ", Regen wahrscheinlich (\(t.regen) Prozent)" } else if t.regen >= 30 { s += ", vielleicht Regen" } else { s += ", es bleibt trocken" }
        if t.min <= 1 { s += ". Vorsicht, es kann glatt sein" }
        if t.wind >= 50 { s += ". Es wird stürmisch" }
        return s + "."
    }
}
