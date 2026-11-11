import Foundation

public struct WetterTag: Codable, Hashable, Sendable {
    public var code: Int
    public var max: Double
    public var min: Double
    public var regen: Int
    public var wind: Double
    public init(code: Int, max: Double, min: Double, regen: Int, wind: Double) { self.code = code; self.max = max; self.min = min; self.regen = regen; self.wind = wind }
}

public struct Wetter: Codable, Hashable, Sendable {
    public var jetzt: Double?
    public var jetztCode: Int?
    public var heute: WetterTag?
    public var morgen: WetterTag?
    public var stand: Date
    public init(jetzt: Double?, jetztCode: Int?, heute: WetterTag?, morgen: WetterTag?, stand: Date) {
        self.jetzt = jetzt; self.jetztCode = jetztCode; self.heute = heute; self.morgen = morgen; self.stand = stand
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
                      heute: tag(0), morgen: tag(1), stand: jetzt)
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
