import Foundation

/// Ein Abschnitt des Schultags laut Klingelzeiten: eine Stunde („1“ … „6“) oder eine Pause („1. Pause“)
public struct Schulzeit: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Minuten nach Mitternacht
    public var von: Int
    public var bis: Int
    public var pause: Bool
    public init(name: String, von: Int, bis: Int, pause: Bool = false) { self.name = name; self.von = von; self.bis = bis; self.pause = pause }

    /// Raster der Schule am Öjendorfer Damm (wie in DammTable): 8:30–13:30, Pausen 10:00 und 11:55
    public static let standard: [Schulzeit] = [
        Schulzeit(name: "1", von: 510, bis: 555), Schulzeit(name: "2", von: 555, bis: 600),
        Schulzeit(name: "1. Pause", von: 600, bis: 625, pause: true),
        Schulzeit(name: "3", von: 625, bis: 670), Schulzeit(name: "4", von: 670, bis: 715),
        Schulzeit(name: "2. Pause", von: 715, bis: 740, pause: true),
        Schulzeit(name: "5", von: 740, bis: 785), Schulzeit(name: "6", von: 785, bis: 810),
    ]
}

/// Eine eigene Stunde im Wochenplan
public struct Unterricht: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// Wochentag wie Calendar.weekday (2 = Montag … 6 = Freitag)
    public var tag: Int
    /// Name der Stunde wie in den Schulzeiten („1“ … „6“)
    public var stunde: String
    public var klasse: String
    public var fach: String
    public var raum: String
    public init(tag: Int, stunde: String, klasse: String, fach: String = "", raum: String = "") {
        self.tag = tag; self.stunde = stunde; self.klasse = klasse; self.fach = fach; self.raum = raum
    }
    /// „5a Mathe · R12“
    public var text: String { [klasse, fach].filter { !$0.isEmpty }.joined(separator: " ") + (raum.isEmpty ? "" : " · \(raum)") }
}

/// Ein Eintrag im Tagesablauf (für Briefing, Widget, Live-Aktivität und Uhr)
public struct Block: Codable, Hashable, Sendable {
    public enum Art: String, Codable, Sendable { case unterricht, vertretung, aufsicht, pause, frei }
    public var name: String
    public var von: Date
    public var bis: Date
    public var art: Art
    public var text: String
    /// Die feste Stunde, die hier eigentlich wäre (durch Vertretung ersetzt oder ausgefallen) – wird durchgestrichen gezeigt
    public var ersetzt: String?
    /// Aufgeteilte Klassen in dieser Stunde laut Vertretungsplan
    public var aufteilung: [String]?
    public init(name: String, von: Date, bis: Date, art: Art, text: String, ersetzt: String? = nil, aufteilung: [String]? = nil) {
        self.name = name; self.von = von; self.bis = bis; self.art = art; self.text = text; self.ersetzt = ersetzt; self.aufteilung = aufteilung
    }
    /// In der Übersicht zeigen (eigene Abschnitte und ausgefallene feste Stunden)
    public var zeigen: Bool { meins || ersetzt != nil }

    /// Kurzname: „3.“ bzw. „1. P“
    public var marke: String { Int(name) != nil ? "\(name)." : name.replacingOccurrences(of: "Pause", with: "P").replacingOccurrences(of: " ", with: "") }
    /// „3. Stunde“ bzw. „1. Pause“
    public var titel: String { Int(name) != nil ? "\(name). Stunde" : name }
    /// Gehört zu meinem Tag (nicht nur Raster)
    public var meins: Bool { art == .unterricht || art == .vertretung || art == .aufsicht }
}

public enum Stundenplan {
    private static func zeit(_ tag: Date, _ minuten: Int) -> Date {
        Zeit.kalender.date(bySettingHour: minuten / 60, minute: minuten % 60, second: 0, of: tag) ?? tag
    }

    /// „1. Pause“ ↔ „1. Pause“, „Pause 1“, „1.P“ – die Nummer zählt
    static func pausenNummer(_ s: String) -> Int? {
        guard s.lowercased().contains("p") else { return nil }
        return s.first(where: \.isNumber).flatMap { Int(String($0)) }
    }

    /// Der Tag in Abschnitten: eigene Stunden, Vertretungen, Aufsichten; dazwischen Freistunden und Pausen.
    /// Leer, wenn an diesem Wochentag nichts geplant ist und die Vertretung nichts nennt.
    /// [ausfall]: ausgefallene eigene Stunden laut WebUntis (Minuten von–bis) – ohne Vertretung dafür: „Entfall“
    public static func tag(_ datum: Date, zeiten: [Schulzeit], unterricht: [Unterricht], vertretung: VertretungsPlan?, haeuser: [String: [String]] = [:],
                           ausfall: [ClosedRange<Int>] = [], ganz: Bool = false) -> [Block] {
        let wt = Zeit.kalender.component(.weekday, from: datum)
        let tag = Zeit.kalender.startOfDay(for: datum)
        let v = vertretung.flatMap { $0.datum == nil || $0.datum == Zeit.iso(datum) ? $0 : nil }
        var bloecke: [Block] = []
        for z in zeiten.sorted(by: { $0.von < $1.von }) {
            let von = zeit(tag, z.von), bis = zeit(tag, z.bis)
            if z.pause {
                // Mehrere Aufsichten in derselben Pause zusammenfassen
                let ps = v?.pausen.filter { pausenNummer($0.pause) == pausenNummer(z.name) } ?? []
                if !ps.isEmpty {
                    let text = (ps.allSatisfy(\.reserve) ? "Reserve " : "Aufsicht ") + ps.map(\.ort).joined(separator: " + ")
                    bloecke.append(Block(name: z.name, von: von, bis: bis, art: .aufsicht, text: text))
                } else {
                    bloecke.append(Block(name: z.name, von: von, bis: bis, art: .pause, text: "Pause"))
                }
            } else if let s = v?.stunden.first(where: { $0.stunde.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) == z.name }) {
                let h = Vertretung.haus(s.klasse, haeuser)
                let fest = unterricht.first(where: { $0.tag == wt && $0.stunde == z.name })?.text
                bloecke.append(Block(name: z.name, von: von, bis: bis, art: .vertretung, text: "Vertretung \(s.klasse)" + (h.isEmpty ? "" : " · \(h)"), ersetzt: fest))
            } else if let u = unterricht.first(where: { $0.tag == wt && $0.stunde == z.name }) {
                if ausfall.contains(where: { $0.lowerBound < z.bis && $0.upperBound > z.von }) {
                    bloecke.append(Block(name: z.name, von: von, bis: bis, art: .frei, text: "Entfall", ersetzt: u.text))
                } else {
                    bloecke.append(Block(name: z.name, von: von, bis: bis, art: .unterricht, text: u.text))
                }
            } else {
                bloecke.append(Block(name: z.name, von: von, bis: bis, art: .frei, text: "frei"))
            }
        }
        if let a = v?.aufteilung {
            for i in bloecke.indices where !(a[bloecke[i].name] ?? []).isEmpty { bloecke[i].aufteilung = a[bloecke[i].name] }
        }
        guard let erst = bloecke.firstIndex(where: \.zeigen), let letzt = bloecke.lastIndex(where: \.zeigen) else { return [] }
        // [ganz]: immer das ganze Raster 1–6 mit beiden Pausen (Übersicht „Schule heute“)
        return ganz ? bloecke : Array(bloecke[erst...letzt])
    }

    /// Wann ich am Tag in der Schule sein muss (Beginn des ersten eigenen Abschnitts)
    public static func beginn(_ bloecke: [Block]) -> Date? { bloecke.first(where: \.meins)?.von }

    /// Was gerade läuft und was danach kommt (für Live-Aktivität, Widget, Uhr)
    public static func jetzt(_ bloecke: [Block], _ zeit: Date = Date()) -> (jetzt: Block?, danach: Block?) {
        let laeuft = bloecke.first { $0.von <= zeit && zeit < $0.bis }
        let danach = bloecke.first { $0.von >= (laeuft?.bis ?? zeit) && $0.art != .frei }
        return (laeuft, danach)
    }

    /// Zeitpunkte, an denen sich die Anzeige ändert (für Widget-Zeitleisten)
    public static func wechsel(_ bloecke: [Block]) -> [Date] { Array(Set(bloecke.flatMap { [$0.von, $0.bis] })).sorted() }

    /// Gesprochen: „Deine Stunden: 1. 5a Mathe in R12, 3. Vertretung 2c in Haus 2, Aufsicht in der 2. Pause: Mensa.“
    public static func satz(_ bloecke: [Block]) -> String {
        let meine = bloecke.filter(\.zeigen)
        guard !meine.isEmpty else { return "" }
        let teile = meine.map { b -> String in
            switch b.art {
            case .aufsicht: return "\(b.text.hasPrefix("Reserve") ? "Reserve" : "Aufsicht") in der \(b.name): \(b.text.replacingOccurrences(of: "Aufsicht ", with: "").replacingOccurrences(of: "Reserve ", with: ""))"
            case .frei: return "\(b.name). \(b.ersetzt?.replacingOccurrences(of: " · ", with: " in ") ?? "Stunde") fällt aus"
            case .vertretung where b.ersetzt != nil: return "\(b.name). statt \(b.ersetzt!.replacingOccurrences(of: " · ", with: " in ")) \(b.text.replacingOccurrences(of: " · ", with: " in "))"
            default: return "\(b.name). \(b.text.replacingOccurrences(of: " · ", with: " in "))"
            }
        }
        return "Deine Stunden: " + Briefing.aufzaehlen(teile) + "."
    }
}

/// Anfahrt: wann losfahren, damit man pünktlich ist – und ob deshalb früher geweckt werden muss
public enum Anfahrt {
    /// Losfahren um (Minuten nach Mitternacht): Beginn − Puffer − Fahrzeit
    public static func losfahren(beginn: Int, fahrtMinuten: Int, puffer: Int) -> Int { beginn - puffer - fahrtMinuten }

    /// Weckzeit, die das noch schafft (Losfahren − Zeit zum Fertigmachen) – nur, wenn sie früher ist als die geplante
    public static func weckzeit(_ w: Weckzeit, beginn: Int, fahrtMinuten: Int, puffer: Int, fertig: Int, fruehestens: Int, art: String) -> Weckzeit {
        guard let m = w.minuten else { return w }
        let los = losfahren(beginn: beginn, fahrtMinuten: fahrtMinuten, puffer: puffer)
        let spaetestens = max(los - fertig, fruehestens)
        guard spaetestens < m else { return w }
        return Weckzeit(minuten: spaetestens, grund: "früher: \(fahrtMinuten) Minuten \(art), losfahren um \(Zeit.sprechen(los))", tag: w.tag)
    }
}

/// Glätte oder Schnee: früher wecken
public enum WetterWecken {
    public static func weckzeit(_ w: Weckzeit, wetter: WetterTag?, minuten: Int, fruehestens: Int) -> Weckzeit {
        guard let m = w.minuten, let t = wetter, minuten > 0, Wetter.glaette(t) else { return w }
        let neu = max(m - minuten, fruehestens)
        guard neu < m else { return w }
        return Weckzeit(minuten: neu, grund: (w.grund.isEmpty ? "" : w.grund + ", ") + "\(minuten) Minuten früher wegen \(Wetter.schnee(t) ? "Schnee" : "Glätte")", tag: w.tag)
    }
}

/// Was das iPhone der Apple Watch schickt
public struct UhrPaket: Codable, Sendable {
    public var wecker: Date?
    public var grund: String
    /// Tagesablauf des Schultags (heute bzw. ab 16 Uhr der nächste) und von heute
    public var schultag: [Block]
    public var schulName: String
    public var heute: [Block]
    public var farbton: String
    public var stand: Date
    public init(wecker: Date?, grund: String, schultag: [Block], schulName: String, heute: [Block], farbton: String, stand: Date) {
        self.wecker = wecker; self.grund = grund; self.schultag = schultag; self.schulName = schulName; self.heute = heute; self.farbton = farbton; self.stand = stand
    }
}
