import Foundation

/// Wann neue Chat-Nachrichten melden: in der Schule und unterwegs sofort, zu Hause nur abends als Zusammenfassung.
public enum ChatMelden {
    public enum Art: Equatable, Sendable { case sofort, sammeln }

    /// Mit Standort: zu Hause (300 m) sammeln, sonst (Schule, Weg dahin) sofort.
    /// Ohne Standort nach der Uhrzeit: Schultag 6–17 Uhr sofort, sonst sammeln.
    public static func art(jetzt: Date = Date(), frei: [FreierTag] = [], hier: Kontext.Ort?, zuhause: Kontext.Ort?) -> Art {
        if let hier, let zuhause { return hier.abstand(zuhause) < 300 ? .sammeln : .sofort }
        let k = Zeit.kalender
        let wt = k.component(.weekday, from: jetzt), h = k.component(.hour, from: jetzt)
        if wt == 1 || wt == 7 || FreieTage.am(frei, jetzt) != nil { return .sammeln }
        return (6..<17).contains(h) ? .sofort : .sammeln
    }

    public struct Neu: Equatable, Sendable {
        public var id: String, raum: String, absender: String, text: String
    }

    /// Neue Nachrichten anderer aus einem /sync ab [seit]; [namen] = bekannte Raumnamen (Folge-Syncs liefern sie nicht mit)
    public static func neue(_ j: [String: Any], ich: String, namen: inout [String: String]) -> [Neu] {
        var neu: [Neu] = []
        for r in Matrix.einarbeiten(j, in: []).raeume {
            if r.name != "Chat" { namen[r.id] = r.name }
            for n in r.nachrichten where n.absender != ich {
                neu.append(Neu(id: n.id, raum: namen[r.id] ?? r.name, absender: r.name(von: n.absender), text: n.text))
            }
        }
        return neu
    }

    /// „Kollegium (3), Medien (1)“ – meiste zuerst
    public static func zusammenfassung(_ gesammelt: [String: Int]) -> (titel: String, text: String) {
        let summe = gesammelt.values.reduce(0, +)
        let t = gesammelt.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        return (summe == 1 ? "1 neue Chat-Nachricht" : "\(summe) neue Chat-Nachrichten", t)
    }

    /// Nächster Zeitpunkt der Zusammenfassung („18:00“): heute, wenn noch nicht vorbei, sonst morgen
    public static func zeitpunkt(_ uhrzeit: String, jetzt: Date = Date()) -> Date {
        let k = Zeit.kalender
        let m = Zeit.minuten(uhrzeit) ?? 18 * 60
        let heute = k.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: jetzt) ?? jetzt
        return heute > jetzt ? heute : k.date(byAdding: .day, value: 1, to: heute) ?? heute
    }
}
