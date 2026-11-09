import Foundation

public enum Zeit {
    public static var kalender: Calendar = {
        var k = Calendar(identifier: .gregorian)
        k.locale = Locale(identifier: "de_DE")
        k.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return k
    }()

    /// "06:15" → 375; ungültig/leer → nil
    public static func minuten(_ s: String) -> Int? {
        let t = s.split(separator: ":").compactMap { Int($0) }
        guard t.count == 2, (0..<24).contains(t[0]), (0..<60).contains(t[1]) else { return nil }
        return t[0] * 60 + t[1]
    }
    public static func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
    /// „sechs Uhr fünfzehn“ wäre zu viel – Siri liest „6:15 Uhr“ gut vor
    public static func sprechen(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60) Uhr" : "\(m / 60) Uhr \(m % 60)" }

    public static func iso(_ d: Date) -> String {
        let c = kalender.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func tag(_ iso: String) -> Date? {
        let t = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard t.count == 3 else { return nil }
        return kalender.date(from: DateComponents(year: t[0], month: t[1], day: t[2], hour: 12))
    }
    public static let wochentage = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    public static func wochentag(_ d: Date) -> String { wochentage[(kalender.component(.weekday, from: d) - 1) % 7] }

    /// Gesamtdauer mehrerer Zeiträume, Überschneidungen nur einmal (z. B. Schlaf von Uhr und iPhone)
    public static func vereinigt(_ teile: [(Date, Date)]) -> TimeInterval {
        var summe: TimeInterval = 0
        var aktuell: (Date, Date)?
        for t in teile.sorted(by: { $0.0 < $1.0 }) {
            if let a = aktuell, t.0 <= a.1 { aktuell = (a.0, max(a.1, t.1)) } else {
                if let a = aktuell { summe += a.1.timeIntervalSince(a.0) }
                aktuell = t
            }
        }
        if let a = aktuell { summe += a.1.timeIntervalSince(a.0) }
        return summe
    }
}

public extension Date {
    /// „14:30“ – immer deutsch, unabhängig von der Spracheinstellung
    var uhrzeit: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = Zeit.kalender.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}

/// Wann Widget und App neu laden: Mo–Fr 7:00, 7:10 … 7:50 (je ±1 Minute und ein paar Sekunden versetzt,
/// damit nicht alle Geräte im selben Moment die Server fragen), um 16 Uhr (Umschalten auf morgen), sonst stündlich.
public enum Takt {
    public static let morgenSlots = Array(stride(from: 7 * 60, through: 7 * 60 + 50, by: 10))

    public static func naechste(nach jetzt: Date, zufall: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> Date {
        let k = Zeit.kalender
        let tag = k.startOfDay(for: jetzt)
        var kandidaten: [Date] = [jetzt.addingTimeInterval(3600)]
        for plus in 0...1 {
            guard let t = k.date(byAdding: .day, value: plus, to: tag) else { continue }
            let wt = k.component(.weekday, from: t)
            if wt != 1 && wt != 7 {
                for m in morgenSlots {
                    let d = t.addingTimeInterval(Double(m * 60) + zufall(-60...60))
                    if d > jetzt.addingTimeInterval(30) { kandidaten.append(d) }
                }
            }
            if let um16 = k.date(bySettingHour: Tagwahl.umschaltStunde, minute: 0, second: Int(zufall(5...50)), of: t), um16 > jetzt { kandidaten.append(um16) }
            if plus == 1 { kandidaten.append(t.addingTimeInterval(zufall(30...90))) } // kurz nach Mitternacht
        }
        return kandidaten.min()!
    }

    /// Liegt [jetzt] im Morgenfenster (6:55–7:55)? Dann Vertretung bei jedem Takt frisch holen.
    public static func morgenFenster(_ jetzt: Date) -> Bool {
        let k = Zeit.kalender
        let m = k.component(.hour, from: jetzt) * 60 + k.component(.minute, from: jetzt)
        return (6 * 60 + 55)...(7 * 60 + 55) ~= m
    }
}

/// Wo bin ich gerade – danach ordnen App und Widget ihre Inhalte (Schule zuerst oder Termine und Post zuerst)
public enum Kontext: String, Sendable {
    case schule, zuhause, frei

    public struct Ort: Codable, Hashable, Sendable {
        public var lat: Double, lon: Double
        public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
        /// Entfernung in Metern (Haversine)
        public func abstand(_ o: Ort) -> Double {
            let r = 6_371_000.0, p = Double.pi / 180
            let a = pow(sin((o.lat - lat) * p / 2), 2) + cos(lat * p) * cos(o.lat * p) * pow(sin((o.lon - lon) * p / 2), 2)
            return 2 * r * asin(min(1, sqrt(a)))
        }
    }

    /// Frei (Wochenende, Ferien, Feiertag) → frei; in der Nähe der Schule → schule; zu Hause → zuhause (bis 8 Uhr noch schule,
    /// zum Vorbereiten); ohne Standort nach der Uhrzeit: Schultag 6–15 Uhr = schule
    public static func bestimme(jetzt: Date = Date(), frei: [FreierTag] = [], hier: Ort? = nil, schule: Ort? = nil, zuhause: Ort? = nil) -> Kontext {
        let k = Zeit.kalender
        let wt = k.component(.weekday, from: jetzt), h = k.component(.hour, from: jetzt)
        if wt == 1 || wt == 7 || FreieTage.am(frei, jetzt) != nil { return .frei }
        if let hier {
            if let s = schule, hier.abstand(s) < 500 { return .schule }
            if let z = zuhause, hier.abstand(z) < 300 { return h < 8 ? .schule : .zuhause }
        }
        return (6..<15).contains(h) ? .schule : .zuhause
    }
}
