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
}
