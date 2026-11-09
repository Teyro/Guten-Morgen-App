import Foundation

/// Eine Störungsmeldung aus IServ
public struct Stoerung: Codable, Hashable, Sendable {
    public var titel: String
    public var inhalt: String
    public var autor: String
    public var bearbeiter: String
    public var datum: Date?
    public var status: String
    public var ort: String
    public var erledigt: Bool
    /// Status heißt: noch niemand hat sie übernommen („wer macht's?“)
    public var unbesetzt: Bool
    public var url: String

    public var uebernommen: Bool { !erledigt && (!bearbeiter.isEmpty || !unbesetzt) }
    /// „🛠 in Arbeit (Kim)“ bzw. „🆕 noch niemand“
    public var zustand: String {
        if erledigt { return "✅ erledigt" }
        if !bearbeiter.isEmpty { return "🛠 \(bearbeiter)" }
        return unbesetzt ? "🆕 noch niemand" : "🛠 " + (status.isEmpty ? "in Arbeit" : status)
    }
}

public struct StoerungenStand: Codable, Hashable, Sendable {
    public var meldungen: [Stoerung]
    public var stand: Date
    public init(meldungen: [Stoerung], stand: Date = Date()) { self.meldungen = meldungen; self.stand = stand }
    /// Neueste zuerst
    public var offen: [Stoerung] { meldungen.filter { !$0.erledigt }.sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) } }
    public var alle: [Stoerung] { meldungen.sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) } }
}

public enum Stoerungen {
    public static let modulKandidaten = ["/iserv/defect", "/iserv/defect/", "/iserv/defects", "/iserv/troubleticket", "/iserv/ticket"]
    public static let modulMuster = "st(ö|oe|&ouml;)rung|defect|trouble|ticket"
    static let erledigtMuster = "erledigt|geschlossen|behoben|gel(ö|oe)st|abgeschlossen|closed|resolved|done|fertig"
    static let unbesetztMuster = "wer mach|niemand|unbearbeitet|^neu$|^offen$|new|open"
    /// Spaltenüberschriften → Felder; Reihenfolge zählt („erstellt von“ ist der Autor, nicht das Datum)
    static let spalten: [(String, String)] = [
        ("bearbeiter", "bearbeit|zust(ä|ae)ndig|(ü|ue)bernommen|zugewiesen|verantwortlich|assign|techniker|admin"),
        ("autor", "gemeldet von|erstellt von|eingereicht von|^von$|autor|verfasser|melder|ersteller|absender|benutzer|gemeldet durch"),
        ("titel", "betreff|titel|title|st(ö|oe)rung|problem|bezeichnung|thema|subject|kurzbeschreibung"),
        ("inhalt", "beschreibung|inhalt|nachricht|text|details|fehlerbeschreibung|description|body"),
        ("status", "status|zustand"),
        ("ort", "raum|ort|ger(ä|ae)t|standort|location"),
        ("kategorie", "kategorie|bereich|typ|art$"),
        ("aktualisiert", "aktualisier|ge(ä|ae)ndert|update"),
        ("datum", "datum|erstellt|gemeldet|zeit|eingang|date|created"),
    ]

    public static func laden(_ s: IServ, quelle: IServQuelle?) async throws -> (StoerungenStand, IServQuelle) {
        if let q = quelle, let l = lesen(try await s.lade(q), spalten: q.spalten) { return (StoerungenStand(meldungen: l), q) }
        guard let (q, l) = try await s.erkunde(muster: modulMuster, kandidaten: modulKandidaten, lesen: { lesen($0, spalten: $1) }) else {
            throw IServFehler.nichtGefunden("Störungsmeldungen nicht gefunden.")
        }
        return (StoerungenStand(meldungen: l), q)
    }

    static func zuordnen(_ kopf: [String]) -> [String: Int] {
        var z: [String: Int] = [:], belegt = Set<Int>()
        for (feld, m) in spalten {
            if let i = kopf.indices.first(where: { !belegt.contains($0) && kopf[$0].trimmingCharacters(in: .whitespaces).range(of: m, options: [.regularExpression, .caseInsensitive]) != nil }) {
                z[feld] = i; belegt.insert(i)
            }
        }
        return z
    }

    static func meldung(_ zellen: [String], _ z: [String: Int], link: String) -> Stoerung? {
        func w(_ f: String) -> String { z[f].map { $0 < zellen.count ? zellen[$0].trimmingCharacters(in: .whitespaces) : "" } ?? "" }
        let titel = w("titel").isEmpty ? String(w("inhalt").prefix(80)) : w("titel")
        guard !titel.isEmpty else { return nil }
        let status = w("status")
        let erledigt = status.range(of: erledigtMuster, options: [.regularExpression, .caseInsensitive]) != nil
        let bearbeiter = w("bearbeiter").range(of: #"^[-–—]$|^(niemand|keine?r?)$"#, options: [.regularExpression, .caseInsensitive]) != nil ? "" : w("bearbeiter")
        return Stoerung(titel: titel, inhalt: z["titel"] != nil ? w("inhalt") : "", autor: HTML.nameSchoen(w("autor")), bearbeiter: HTML.nameSchoen(bearbeiter),
                        datum: zeit(w("datum")), status: status, ort: w("ort"), erledigt: erledigt,
                        unbesetzt: !erledigt && (status.isEmpty || status.range(of: unbesetztMuster, options: [.regularExpression, .caseInsensitive]) != nil), url: link)
    }

    public static func lesen(_ s: IServ.Seite, spalten sp: [String]) -> [Stoerung]? {
        let body = s.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.typ.lowercased().contains("json") || body.hasPrefix("{") || body.hasPrefix("[") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { return nil }
            let zeilen = (j as? [[Any]]) ?? ((j as? [String: Any]).flatMap { ($0["data"] ?? $0["aaData"] ?? $0["rows"]) as? [[Any]] })
            guard let zz = zeilen, !sp.isEmpty else { return nil }
            let z = zuordnen(sp)
            guard z["titel"] != nil else { return nil }
            return zz.compactMap { r in meldung(r.map { c in HTML.text((c as? String) ?? ((c as? [String: Any])?["display"] as? String) ?? "\(c)") }, z, link: "") }
        }
        if s.typ.lowercased().contains("csv") {
            let zeilen = HTML.csv(body)
            if let kopf = zeilen.first { let z = zuordnen(kopf); if z["titel"] != nil { return zeilen.dropFirst().compactMap { meldung($0, z, link: "") } } }
        }
        var liste: [Stoerung] = []
        for tab in HTML.tabellen(body) where tab.count >= 2 {
            let z = zuordnen(tab[0].zellen)
            guard z["titel"] != nil, z["datum"] != nil || z["autor"] != nil else { continue }
            for r in tab.dropFirst() where r.zellen.count >= 2 {
                if let m = meldung(r.zellen, z, link: r.link.map { HTML.absolut(HTML.entities($0), von: s.url) } ?? "") { liste.append(m) }
            }
        }
        return liste.isEmpty ? nil : liste
    }

    /// „12.10.2026, 08:15“, „2026-10-12T…“, „heute 9:30“, „gestern“
    public static func zeit(_ s: String) -> Date? {
        let k = Zeit.kalender
        if s.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            let f = ISO8601DateFormatter()
            if let d = f.date(from: s) { return d }
            return Zeit.tag(String(s.prefix(10)))
        }
        func uhr(_ d: Date) -> Date {
            guard let u = HTML.erster(#"(\d{1,2}:\d{2})"#, s), let m = Zeit.minuten(u) else { return d }
            return k.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: d) ?? d
        }
        if let iso = Abwesenheiten.datum(s), s.range(of: #"\d{1,2}\.\d{1,2}\.\d{2,4}"#, options: .regularExpression) != nil, let d = Zeit.tag(iso) {
            return uhr(k.startOfDay(for: d))
        }
        if s.range(of: "heute", options: .caseInsensitive) != nil { return uhr(k.startOfDay(for: Date())) }
        if s.range(of: "gestern", options: .caseInsensitive) != nil { return uhr(k.startOfDay(for: Date().addingTimeInterval(-86400))) }
        return nil
    }
}
