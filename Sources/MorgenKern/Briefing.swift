import Foundation

/// Alles, was das Morgen-Briefing braucht (von der App eingesammelt)
public struct BriefingDaten: Sendable {
    public var jetzt = Date()
    public var wetter: Wetter?
    public var termine: [Termin] = []
    public var erinnerungen: [String] = []
    public var post = ""
    public var vertretung: VertretungsPlan?
    public var frei: FreierTag?
    public var wecker: Weckzeit?
    public var offeneFenster: [String] = []
    public var erledigt: [String] = []
    public init() {}
}

public enum Briefing {
    static func aufzaehlen(_ t: [String]) -> String {
        t.count <= 1 ? (t.first ?? "") : t.dropLast().joined(separator: ", ") + " und " + t.last!
    }
    static func uhr(_ d: Date) -> String {
        let k = Zeit.kalender
        return Zeit.sprechen(k.component(.hour, from: d) * 60 + k.component(.minute, from: d))
    }

    /// Das gesprochene Morgen-Briefing
    public static func morgen(_ d: BriefingDaten) -> String {
        let k = Zeit.kalender
        let h = k.component(.hour, from: d.jetzt)
        var s: [String] = []
        let gruss = h < 11 ? "Guten Morgen" : h < 18 ? "Hallo" : "Guten Abend"
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM"
        s.append("\(gruss)! Heute ist \(f.string(from: d.jetzt)), es ist \(uhr(d.jetzt)).")
        if let frei = d.frei { s.append(frei.ferien ? "Es sind \(frei.name)." : "Heute ist \(frei.name).") }
        if let w = d.wetter { s.append(w.satz()) }
        let heute = d.termine.filter { k.isDate($0.start, inSameDayAs: d.jetzt) }
        let ganz = heute.filter(\.ganztags).map(\.titel)
        let zeit = heute.filter { !$0.ganztags && $0.start > d.jetzt.addingTimeInterval(-1800) }.sorted { $0.start < $1.start }
        if ganz.isEmpty && zeit.isEmpty { s.append("Im Kalender steht heute nichts.") } else {
            let teile = ganz + zeit.prefix(6).map { "um \(uhr($0.start)) \($0.titel)" }
            s.append((teile.count == 1 ? "Heute steht an: " : "Heute stehen an: ") + aufzaehlen(teile) + ".")
        }
        if !d.erinnerungen.isEmpty {
            s.append(d.erinnerungen.count == 1 ? "Eine Erinnerung ist fällig: \(d.erinnerungen[0])." : "\(d.erinnerungen.count) Erinnerungen sind fällig, zum Beispiel: \(aufzaehlen(Array(d.erinnerungen.prefix(3))))." )
        }
        if !d.post.isEmpty { s.append(d.post) }
        if let v = d.vertretung, d.frei == nil, (2...6).contains(k.component(.weekday, from: d.jetzt)) { s.append(v.satz()) }
        s.append(h < 18 ? "Einen schönen Tag!" : "Einen schönen Abend!")
        return s.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Gute Nacht: was erledigt ist, offene Fenster, Wecker und Wetter für morgen
    public static func nacht(_ d: BriefingDaten) -> String {
        var s: [String] = []
        if !d.erledigt.isEmpty { s.append(aufzaehlen(d.erledigt) + " – erledigt.") }
        for f in d.offeneFenster.prefix(4) { s.append("Achtung: \(f) ist offen.") }
        if let w = d.wecker {
            if let m = w.minuten {
                let morgen = Zeit.kalender.isDate(w.tag, inSameDayAs: d.jetzt) ? "heute" : "morgen"
                s.append("Der Wecker klingelt \(morgen) um \(Zeit.sprechen(m))\(w.grund.isEmpty ? "" : ", \(w.grund)").")
            } else { s.append("Morgen kein Wecker – \(w.grund).") }
        }
        if let w = d.wetter { s.append(w.satz(morgen: true)) }
        s.append("Gute Nacht!")
        return s.joined(separator: " ")
    }
}
