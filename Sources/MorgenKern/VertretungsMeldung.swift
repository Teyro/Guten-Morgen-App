import Foundation

/// Wann meldet DammAPP etwas zum Vertretungsplan? (reine Regel – App und Widget schicken nur ab, testbar)
///
/// - [planDa]: Sobald ein Plan für einen **neuen Tag** auftaucht: „Vertretungsplan für Dienstag ist da“ mit den eigenen
///   Einträgen oder „Keine Vertretung für dich“.
/// - [betrifft]: Ändern sich die eigenen Einträge (auch später am Tag): „Vertretungsplan betrifft dich“.
/// Beim allerersten Lauf wird nur gemerkt (kein alter Plan als „neu“). Pro Änderung höchstens eine Mitteilung.
public enum VertretungsMeldung {
    public struct Meldung: Equatable, Sendable {
        public var id: String
        public var titel: String
        public var text: String
    }

    /// Ergebnis: optionale Meldung und der neue Merkstand (Datum des Plans, Signatur der eigenen Einträge)
    public static func pruefen(_ v: VertretungsPlan, altDatum: String?, altSig: String?, planDa: Bool, betrifft: Bool)
        -> (meldung: Meldung?, datum: String, sig: String)? {
        guard let datum = v.datum else { return nil }
        let meine = eintraege(v)
        let sig = datum + "|" + meine.sorted().joined(separator: ";")
        var m: Meldung?
        if planDa, let altDatum, altDatum != datum {
            let tag = Zeit.tag(datum).map(Zeit.wochentag) ?? datum
            m = Meldung(id: "vertretung-plan-\(datum)", titel: "Vertretungsplan für \(tag) ist da",
                        text: meine.isEmpty ? "Keine Vertretung für dich." : meine.prefix(3).joined(separator: " · "))
        } else if betrifft, let altSig, altSig != sig, !meine.isEmpty {
            m = Meldung(id: "vertretung-tag", titel: "Vertretungsplan betrifft dich", text: meine.prefix(3).joined(separator: " · "))
        }
        return (m, datum, sig)
    }

    /// Eigene Einträge in Kurzform: „3. Vertretung 2c“, „Aufsicht 1. Pause · Hof“, „Du bist als fehlend eingetragen“
    public static func eintraege(_ v: VertretungsPlan) -> [String] {
        v.stunden.map { ($0.stunde.isEmpty ? "" : "\($0.stunde). ") + "Vertretung \($0.klasse)" }
            + v.pausen.map { "\($0.reserve ? "Reserve" : "Aufsicht") \($0.pause) · \($0.ort)" }
            + (v.fehlt ? ["Du bist als fehlend eingetragen"] : [])
            + (v.ausserHaus ? ["Du bist außer Haus eingetragen"] : [])
    }
}
