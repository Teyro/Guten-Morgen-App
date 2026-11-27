import WidgetKit
import SwiftUI
import MorgenKern

/// Daten des Haupt-Widgets – gemeinsam mit der App (Widget-Vorschau in den Bildschirmfotos)
struct MorgenEintrag: TimelineEntry {
    let date: Date
    var eingerichtet: Bool
    var wecker: Weckzeit?
    var wetter: Wetter?
    var termin: Termin?
    var post = ""
    /// Termine des Schultags (heute bzw. ab 16 Uhr morgen)
    var heute: [Termin] = []
    var vertretung: VertretungsPlan?
    var haeuser: [String: [String]] = [:]
    var mensa: MensaTag?
    var mensaWahl: (String, String) = ("", "")
    var gemerkt: ([String], [String]) = ([], [])
    var obst = false
    var farbton = "morgenrot"
    /// „heute“, „morgen“ oder „Montag“
    var schulName = "heute"
    /// Kinder, die fehlen (schon mit Sichtschutz), offene Störungen, offene Aufgaben – nil = Modul aus
    var kinder: [String]?
    /// Zahl im Kasten „Fehlen“: IServ ohne Ausgegraute, ab Vertretungsplan „7 + 2“ (krank + außer Haus)
    var fehlen: (zahl: String, text: String)?
    var stoerungen: Int?
    var aufgaben: Int?
    /// Schule zuerst oder (zu Hause, am Wochenende) Termine und Post zuerst
    var kontext: Kontext = .schule
    /// Eigene feste Stunde, die eine Vertretung/Begleitung ersetzt: Stunde („3“) → „5a Mathe · R12“ (rot durchgestrichen)
    var ersetzt: [String: String] = [:]

    struct SchulZeile: Hashable {
        enum Art { case rot, aufsicht, gut, warnung, obst }
        var marke: String
        var text: String
        var art: Art
        var statt: String? = nil
    }

    /// Kurze Schul-Zeilen: „2. Vertretung 2c · Haus 2“ (rot = außerplanmäßig), „1.P Aufsicht Hof“, „🍎 Schulobst“
    var schulZeilen: [SchulZeile] {
        var z: [SchulZeile] = []
        if let v = vertretung {
            if v.fehlt { z.append(.init(marke: "!", text: "Als fehlend eingetragen", art: .warnung)) }
            if v.ausserHaus { z.append(.init(marke: "!", text: "Außer Haus eingetragen", art: .warnung)) }
            for s in v.stunden {
                let h = Vertretung.haus(s.klasse, haeuser), n = Stundenplan.stunde(s.stunde)
                z.append(.init(marke: n + ".", text: VertretungsPlan.titel(s) + (h.isEmpty ? "" : " · \(h)"), art: .rot, statt: ersetzt[n]))
            }
            // Begleitungen aus der „Wichtig“-Zeile: „3.–5.  2c → Nelson“
            for b in v.bemerkungen ?? [] where b.was.hasPrefix("Begleitung ") && !b.stunden.isEmpty {
                let wer = String(b.was.dropFirst("Begleitung ".count))
                z.append(.init(marke: b.stunden.count > 1 ? "\(b.stunden.first!)–\(b.stunden.last!)" : "\(b.stunden[0]).",
                               text: b.klasse.isEmpty ? b.was : "\(b.klasse) → \(wer)", art: .rot, statt: ersetzt[String(b.stunden[0])]))
            }
            for p in v.pausen { z.append(.init(marke: String(p.pause.prefix(1)) + ".P", text: (p.reserve ? "Reserve " : "Aufsicht ") + p.ort, art: .aufsicht)) }
            if z.isEmpty { z.append(.init(marke: "✓", text: "Alles nach Plan", art: .gut)) }
        }
        if obst { z.append(.init(marke: "🍎", text: "Schulobst", art: .obst)) }
        return z
    }
    /// Wie viel außerplanmäßig (rot) ist
    var rotZahl: Int { schulZeilen.filter { $0.art == .rot }.count }
    var essen: String? {
        guard let m = mensa else { return nil }
        if let f = m.frei { return "Mensa zu" + (f.isEmpty ? "" : " (\(f))") }
        return m.haupt(favoriten: mensaWahl.0, meiden: mensaWahl.1, gut: gemerkt.0, schlecht: gemerkt.1).map { ($0.bestellt ? "✓ " : "") + $0.text }
    }
}


extension MorgenEintrag {
    /// Beispiel für die Widget-Galerie und die Vorschau in der App
    static var beispiel: MorgenEintrag {
        var p = VertretungsPlan(); p.datum = Zeit.iso(Date()); p.belegt = 3
        p.stunden = [.init(stunde: "2", klasse: "2c")]; p.pausen = [.init(pause: "2. Pause", ort: "Hof")]
        p.bemerkungen = [Bemerkung(stunden: [4, 5], was: "Begleitung Nelson", klasse: "3b", text: "")]
        let k = Zeit.kalender
        return MorgenEintrag(date: Date(), eingerichtet: true, wecker: Weckzeit(minuten: 375, grund: "", tag: Weckzeit.naechsterTag()),
                             wetter: Wetter(jetzt: 6, jetztCode: 2, heute: WetterTag(code: 2, max: 9, min: 3, regen: 10, wind: 10), morgen: nil, stand: Date()),
                             termin: Termin(titel: "Dienstbesprechung", start: k.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date(), ganztags: false),
                             heute: [Termin(titel: "Dienstbesprechung", start: k.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date(), ganztags: false)],
                             vertretung: p, haeuser: ["Haus 4": ["2a", "2b", "2c"]],
                             mensa: MensaTag(datum: Zeit.iso(Date()), gerichte: [Gericht(menue: "Menü 1", text: "Spaghetti Bolognese")]), obst: true,
                             farbton: "system", kinder: ["Ben", "Mia"], fehlen: ("7 + 2", "krank + außer Haus"), stoerungen: 3, aufgaben: 5,
                             ersetzt: ["2": "5a Mathe · R12", "4": "4a Deutsch · R7"])
    }
}
