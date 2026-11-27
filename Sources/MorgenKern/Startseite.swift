import Foundation

/// Reihenfolge und Sichtbarkeit der Kacheln auf der Startseite (reine Regel, ohne UI – testbar).
public enum Startseite {
    /// Alle Kacheln. „mensa“, „zahlen“, „schultermine“ waren bis 2.4 Teil der Schul-Kachel, „personal“ ist neu.
    public static let alle = ["wecker", "schule", "mensa", "zahlen", "schultermine", "wetter", "termine", "post", "personal", "fussball"]

    /// Ehemalige Teile der Schul-Kachel: fehlen sie in einer gespeicherten Reihenfolge, kommen sie direkt hinter „schule“.
    static let ausSchule = ["mensa", "zahlen", "schultermine"]

    /// Reihenfolge der sichtbaren Kacheln: eigene (aus den Einstellungen) oder automatisch – in der Schule
    /// zuerst die Schule, zu Hause und am Wochenende Termine und Post. [aus] = ausgeblendete Kacheln.
    public static func ordnung(eigen: [String], aus: [String], inDerSchule: Bool) -> [String] {
        return vollstaendig(eigen, inDerSchule: inDerSchule).filter { !aus.contains($0) }
    }

    /// Alle Kacheln in Reihenfolge (auch ausgeblendete) – für die Einstellungen zum Verschieben und Abschalten.
    public static func vollstaendig(_ eigen: [String], inDerSchule: Bool) -> [String] {
        var r = eigen.filter { alle.contains($0) }
        if r.isEmpty {
            return inDerSchule
                ? ["wecker", "schule", "mensa", "zahlen", "schultermine", "fussball", "wetter", "termine", "post", "personal"]
                : ["wecker", "termine", "post", "wetter", "schule", "mensa", "zahlen", "schultermine", "fussball", "personal"]
        }
        // Neue Kacheln in eine ältere gespeicherte Reihenfolge einsortieren
        var nachSchule = r.firstIndex(of: "schule").map { $0 + 1 } ?? r.count
        for k in ausSchule where !r.contains(k) { r.insert(k, at: nachSchule); nachSchule += 1 }
        for k in alle where !r.contains(k) { r.append(k) }
        return r
    }
}
