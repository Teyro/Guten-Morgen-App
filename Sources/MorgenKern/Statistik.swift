import Foundation

/// Eigene Statistik aus den Vertretungsplänen (nur über mich, nie über das Kollegium): je Plan-Tag, was für mich drinstand.
/// Gezählt wird nur, was die App gesehen hat – ein späterer Stand desselben Tages ersetzt den früheren.
public struct VertretungsStatistik: Codable, Hashable, Sendable {
    public struct Tag: Codable, Hashable, Sendable {
        /// Klassen der Vertretungsstunden (außerplanmäßig = rot)
        public var vertretungen: [String]
        public var aufsichten: Int
        public var begleitungen: Int
        public var fehlt: Bool
        public var ausserHaus: Bool
    }
    /// ISO-Datum → Tag
    public var tage: [String: Tag] = [:]
    public init() {}

    public mutating func merken(_ p: VertretungsPlan) {
        // leere Vorlage oder Plan ohne Datum nicht zählen
        guard let d = p.datum, p.belegt > 0 else { return }
        let begleitungen = (p.bemerkungen ?? []).filter { $0.was.hasPrefix("Begleitung ") }.reduce(0) { $0 + max(1, $1.stunden.count) }
        tage[d] = Tag(vertretungen: p.stunden.map(\.klasse), aufsichten: p.pausen.filter { !$0.reserve }.count,
                      begleitungen: begleitungen, fehlt: p.fehlt, ausserHaus: p.ausserHaus)
    }

    public struct Zahlen: Hashable, Sendable {
        public var tage = 0, vertretungen = 0, aufsichten = 0, begleitungen = 0, fehlt = 0, ausserHaus = 0
        /// Klasse, in der ich am öftesten vertreten habe
        public var klasse: String?
        /// Wochentag mit den meisten Vertretungen (1 = Sonntag … 7 = Samstag)
        public var wochentag: Int?
        /// Tage mit mindestens einer Vertretungsstunde
        public var rotTage = 0
    }

    /// Zahlen im Zeitraum [ab, bis] (ISO-Daten, je einschließlich)
    public func zahlen(ab: String, bis: String = "9999-12-31") -> Zahlen {
        var z = Zahlen(), klassen: [String: Int] = [:], wt: [Int: Int] = [:]
        for (d, t) in tage where d >= ab && d <= bis {
            z.tage += 1; z.vertretungen += t.vertretungen.count; z.aufsichten += t.aufsichten; z.begleitungen += t.begleitungen
            if t.fehlt { z.fehlt += 1 }
            if t.ausserHaus { z.ausserHaus += 1 }
            if !t.vertretungen.isEmpty {
                z.rotTage += 1
                if let tag = Zeit.tag(d) { wt[Zeit.kalender.component(.weekday, from: tag), default: 0] += t.vertretungen.count }
            }
            for k in t.vertretungen where !k.isEmpty { klassen[k, default: 0] += 1 }
        }
        z.klasse = klassen.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        z.wochentag = wt.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        return z
    }

    /// Beginn des Schuljahrs (1. August) als ISO-Datum
    public static func schuljahrBeginn(_ d: Date = Date()) -> String {
        let k = Zeit.kalender, j = k.component(.year, from: d)
        return String(format: "%04d-08-01", k.component(.month, from: d) >= 8 ? j : j - 1)
    }

    /// Erster Tag des Monats als ISO-Datum
    public static func monatsBeginn(_ d: Date = Date()) -> String {
        let k = Zeit.kalender
        return String(format: "%04d-%02d-01", k.component(.year, from: d), k.component(.month, from: d))
    }
}
