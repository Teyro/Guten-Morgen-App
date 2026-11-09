import Foundation

/// Eine Abwesenheit aus IServ (nur zur Anzeige – keine Statistik je Kind, kein Export)
public struct Abwesenheit: Codable, Hashable, Sendable {
    public var name: String
    public var klasse: String
    public var von: String        // ISO-Tag
    public var bis: String
    public var art: String        // unentschuldigt, entschuldigt, krank, beurlaubt, ohne, sonstig
    public var stunden: String    // „8–10 Uhr“ oder Stundenangabe (leer = ganztägig)
    public init(name: String, klasse: String, von: String, bis: String, art: String, stunden: String = "") {
        self.name = name; self.klasse = klasse; self.von = von; self.bis = bis; self.art = art; self.stunden = stunden
    }
    /// Nur einzelne Stunden an einem Tag
    public var stundenweise: Bool { !stunden.isEmpty && von == bis }
}

public struct AbwesenheitenStand: Codable, Hashable, Sendable {
    public var eintraege: [Abwesenheit]
    public var stand: Date
    public init(eintraege: [Abwesenheit], stand: Date = Date()) { self.eintraege = eintraege; self.stand = stand }
}

public enum Abwesenheiten {
    public static let modulKandidaten = ["/iserv/absence", "/iserv/absence/", "/iserv/dsa-absence", "/iserv/dsa/absence"]
    public static let modulMuster = "abwesen|absence|krankmeld|fehlzeit"
    /// Nur Einträge rund um heute behalten (ein Export kann das ganze Schuljahr enthalten)
    public static let fensterTage = 21
    public static let arten: [String: (emoji: String, wort: String)] = [
        "unentschuldigt": ("🤒", "unentschuldigt"), "entschuldigt": ("✅", "entschuldigt"), "krank": ("🤒", "krank"),
        "beurlaubt": ("🏖️", "beurlaubt"), "ohne": ("❓", "ohne Info"), "sonstig": ("📌", "abwesend"),
    ]

    /// Laden: bekannte Quelle direkt, sonst erkunden. Rückgabe mit (ggf. neuer) Quelle zum Merken.
    public static func laden(_ s: IServ, quelle: IServQuelle?) async throws -> (AbwesenheitenStand, IServQuelle) {
        if let q = quelle, let l = lesen(try await s.lade(q), spalten: q.spalten) { return (AbwesenheitenStand(eintraege: imFenster(l)), q) }
        guard let (q, l) = try await s.erkunde(muster: modulMuster, kandidaten: modulKandidaten, lesen: { lesen($0, spalten: $1) }) else {
            throw IServFehler.nichtGefunden("Abwesenheiten-Daten nicht gefunden.")
        }
        return (AbwesenheitenStand(eintraege: imFenster(l)), q)
    }

    static func imFenster(_ l: [Abwesenheit], heute: Date = Date()) -> [Abwesenheit] {
        let k = Zeit.kalender
        let min = Zeit.iso(k.date(byAdding: .day, value: -fensterTage, to: heute)!), max = Zeit.iso(k.date(byAdding: .day, value: fensterTage, to: heute)!)
        return l.filter { $0.bis >= min && $0.von <= max }
    }

    // MARK: Lesen (JSON-Tabellen, CSV, HTML)

    public static func lesen(_ s: IServ.Seite, spalten: [String]) -> [Abwesenheit]? {
        let body = s.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.typ.lowercased().contains("json") || body.hasPrefix("{") || body.hasPrefix("[") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { return nil }
            let zeilen = (j as? [[Any]]) ?? ((j as? [String: Any]).flatMap { ($0["data"] ?? $0["aaData"] ?? $0["rows"]) as? [[Any]] })
            if let z = zeilen, !spalten.isEmpty {
                let tab = [spalten] + z.map { $0.map { c in HTML.text((c as? String) ?? ((c as? [String: Any])?["display"] as? String) ?? "\(c)") } }
                return ausTabelle(tab)
            }
            if let o = j as? [String: Any], let d = o["data"] as? [Any], d.isEmpty { return [] }
            return nil
        }
        if s.typ.lowercased().contains("csv") || body.range(of: #"^[^<\n]*(name|schüler)[^<\n]*[;,\t][^<\n]*\n"#, options: [.regularExpression, .caseInsensitive]) != nil {
            if let c = ausCSV(body) { return c }
        }
        let t = HTML.tabellen(body).flatMap { ausTabelle($0.map(\.zellen)) ?? [] }
        return t.isEmpty ? nil : t
    }

    /// Tabelle (erste Zeile = Kopf) mit Spalten Name/Klasse/Von/Bis/Art
    static func ausTabelle(_ zeilen: [[String]]) -> [Abwesenheit]? {
        guard zeilen.count >= 2 else { return nil }
        let kopf = zeilen[0].map { $0.lowercased() }
        func sp(_ m: String) -> Int? { kopf.firstIndex { $0.range(of: m, options: .regularExpression) != nil } }
        guard let sName = sp("name|schüler|schueler|kind"), let sVon = sp("von|beginn|start|datum|zeitraum|zeit|tag") else { return nil }
        let sKlasse = sp("klasse|lerngruppe"), sBis = sp("bis|ende"), sArt = sp("art|grund|typ|status|kategorie"), sStd = sp("stunde")
        return zeilen.dropFirst().compactMap { z -> Abwesenheit? in
            guard z.count > max(sName, sVon) else { return nil }
            let daten = HTML.alle(#"(\d{1,2}\.\d{1,2}\.(?:\d{2,4})?)"#, z[sVon])
            guard let von = datum(daten.first ?? z[sVon]), !z[sName].isEmpty else { return nil }
            let bis = sBis.flatMap { $0 < z.count ? datum(z[$0]) : nil } ?? (daten.count > 1 ? datum(daten[1]) : nil) ?? von
            return Abwesenheit(name: HTML.nameSchoen(z[sName]), klasse: sKlasse.map { $0 < z.count ? z[$0] : "" } ?? "", von: von, bis: bis,
                               art: art(sArt.map { $0 < z.count ? z[$0] : "" } ?? ""), stunden: sStd.map { $0 < z.count ? z[$0] : "" } ?? uhrzeit(z[sVon]))
        }
    }

    /// CSV-Export (IServ Hamburg: /iserv/absence/.csv). Leere Liste ist ein echtes Ergebnis.
    static func ausCSV(_ body: String) -> [Abwesenheit]? {
        let zeilen = HTML.csv(body)
        guard let kopf = zeilen.first?.map({ $0.lowercased() }) else { return nil }
        func sp(_ m: String) -> Int? { kopf.firstIndex { $0.range(of: m, options: .regularExpression) != nil } }
        let sVor = sp("^vorname"), sNach = sp("^nachname|^familienname"), sName = sp("name|schüler|schueler")
        guard sName != nil || sNach != nil, let sVon = sp("von|beginn|start|zeitraum|abwesenheitszeit|datum") else { return nil }
        let sKlasse = sp("klasse|lerngruppe"), sBis = sp("bis|ende"), sArt = sp("art|grund|typ|status|kategorie|entschuldig"), sStd = sp("stunde")
        func f(_ z: [String], _ i: Int?) -> String { i.map { $0 < z.count ? z[$0] : "" } ?? "" }
        return zeilen.dropFirst().compactMap { z -> Abwesenheit? in
            let daten = HTML.alle(#"(\d{1,2}\.\d{1,2}\.(?:\d{2,4})?|\d{4}-\d{2}-\d{2})"#, f(z, sVon))
            let name = sNach != nil ? [f(z, sVor), f(z, sNach)].filter { !$0.isEmpty }.joined(separator: " ") : HTML.nameSchoen(f(z, sName))
            guard let von = daten.first.flatMap({ datum($0) }), !name.isEmpty else { return nil }
            let bis = (sBis != nil ? datum(f(z, sBis)) : nil) ?? (daten.count > 1 ? datum(daten[1]) : nil) ?? von
            return Abwesenheit(name: name, klasse: f(z, sKlasse), von: von, bis: bis, art: art(f(z, sArt)), stunden: sStd != nil ? f(z, sStd) : uhrzeit(f(z, sVon)))
        }
    }

    /// „12.10.2026“, „12.10.“, „2026-10-12…“ → ISO-Tag
    public static func datum(_ s: String, jahr: Int? = nil) -> String? {
        if let iso = HTML.erster(#"(\d{4}-\d{2}-\d{2})"#, s) { return iso }
        guard let r = s.range(of: #"(\d{1,2})\.(\d{1,2})\.(\d{2,4})?"#, options: .regularExpression) else { return nil }
        let teile = s[r].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard teile.count >= 2, let t = Int(teile[0]), let m = Int(teile[1]), (1...31).contains(t), (1...12).contains(m) else { return nil }
        var j = teile.count > 2 ? Int(teile[2]) ?? 0 : 0
        if j == 0 { j = jahr ?? Zeit.kalender.component(.year, from: Date()) } else if j < 100 { j += 2000 }
        return String(format: "%04d-%02d-%02d", j, m, t)
    }

    public static func art(_ s: String) -> String {
        let t = s.lowercased()
        if t.contains("unentsch") { return "unentschuldigt" }
        if t.contains("entschuldigt") { return "entschuldigt" }
        if t.range(of: "krank|sick|ill", options: .regularExpression) != nil { return "krank" }
        if t.range(of: "beurlaub|urlaub|leave|befrei|antrag", options: .regularExpression) != nil { return "beurlaubt" }
        if t.range(of: "ohne|unbekannt|unknown|missing|keine info|offen", options: .regularExpression) != nil { return "ohne" }
        return "sonstig"
    }

    /// „12.10.2026 (08:00 - 10:00)“ → „8–10 Uhr“
    static func uhrzeit(_ s: String) -> String {
        guard let r = s.range(of: #"\((\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})\)"#, options: .regularExpression) else { return "" }
        let z = s[r].components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard z.count == 4 else { return "" }
        func t(_ h: String, _ m: String) -> String { "\(Int(h) ?? 0)" + (m == "00" ? "" : ":\(m)") }
        return "\(t(z[0], z[1]))–\(t(z[2], z[3])) Uhr"
    }

    // MARK: Auswertung

    /// Wer fehlt am Zieltag: Filter nach Klassen (leer = alle), dieselbe Person nur einmal, ganztägig zuerst, dann Art und Name
    public static func amTag(_ l: [Abwesenheit], ziel: Date, klassen: [String] = []) -> [Abwesenheit] {
        let z = Zeit.iso(ziel)
        let filter = klassen.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }.filter { !$0.isEmpty }
        let rang = ["unentschuldigt": 0, "krank": 1, "ohne": 2, "beurlaubt": 3, "entschuldigt": 4, "sonstig": 5]
        var gesehen = Set<String>()
        return l.filter { $0.von <= z && z <= $0.bis }
            .filter { e in filter.isEmpty || filter.contains(e.klasse.lowercased().replacingOccurrences(of: " ", with: "")) }
            .filter { gesehen.insert($0.name).inserted }
            .sorted { a, b in
                (a.stundenweise ? 1 : 0, rang[a.art] ?? 5, a.name) < (b.stundenweise ? 1 : 0, rang[b.art] ?? 5, b.name)
            }
    }

    /// „seit Mo“, „bis Fr“, „ab morgen da“ oder die Uhrzeit bei einzelnen Stunden
    public static func zeitText(_ e: Abwesenheit, ziel: Date, jetzt: Date = Date()) -> String {
        let k = Zeit.kalender
        let wt = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        guard let von = Zeit.tag(e.von), let bis = Zeit.tag(e.bis) else { return "" }
        let z = Zeit.iso(ziel)
        var teile: [String] = []
        func kurz(_ d: Date, _ tage: Int) -> String { tage < 7 ? wt[k.component(.weekday, from: d) - 1] : "\(k.component(.day, from: d)).\(k.component(.month, from: d))." }
        if e.von < z { teile.append("seit " + kurz(von, Int((ziel.timeIntervalSince(von) / 86400).rounded()))) }
        if e.bis == z {
            if !teile.isEmpty {
                var zurueck = k.date(byAdding: .day, value: 1, to: ziel)!
                while [1, 7].contains(k.component(.weekday, from: zurueck)) { zurueck = k.date(byAdding: .day, value: 1, to: zurueck)! }
                teile.append(k.isDate(zurueck, inSameDayAs: k.date(byAdding: .day, value: 1, to: jetzt)!) ? "ab morgen da" : "ab \(wt[k.component(.weekday, from: zurueck) - 1]) da")
            } else if !e.stunden.isEmpty { teile.append(e.stunden) }
        } else {
            teile.append("bis " + kurz(bis, Int((bis.timeIntervalSince(ziel) / 86400).rounded())))
        }
        return teile.joined(separator: " · ")
    }

    /// Sichtschutz: nur Vorname + Initiale („Mia K.“)
    public static func kurzName(_ n: String) -> String {
        let t = n.split(separator: " ")
        return t.count > 1 ? "\(t[0]) \(t.last!.prefix(1))." : n
    }
}
