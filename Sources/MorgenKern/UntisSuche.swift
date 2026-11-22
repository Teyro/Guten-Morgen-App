import Foundation

/// Etwas mit eigenem Stundenplan in WebUntis: Klasse (1), Lehrkraft (2) oder Raum (4)
public struct UntisElement: Codable, Hashable, Sendable, Identifiable {
    public var typ: Int
    public var name: String
    public var lang: String
    public var untisId: Int
    public init(typ: Int, name: String, lang: String = "", untisId: Int = 0) { self.typ = typ; self.name = name; self.lang = lang; self.untisId = untisId }
    public var id: String { "\(typ)|\(name.lowercased())" }
    public var art: String { typ == 1 ? "Klasse" : typ == 2 ? "Lehrkraft" : "Raum" }
    public var symbol: String { typ == 1 ? "person.3.fill" : typ == 2 ? "person.fill" : "door.left.hand.open" }
    public var titel: String { lang.isEmpty || lang == name ? name : "\(name) – \(lang)" }
}

public extension Untis {
    /// Angemeldete WebUntis-Sitzung für die Suche nach fremden Stundenplänen (eine Anmeldung, viele Abrufe)
    final class Suche: @unchecked Sendable {
        let s: Sitzung
        public private(set) var elemente: [UntisElement] = []
        init(_ s: Sitzung) { self.s = s }

        public static func oeffnen(link: String, schule: String = "", benutzer: String, passwort: String, schluessel: String = "") async throws -> Suche {
            let q = qr(link)
            guard let z = q.map({ (basis: $0.basis, schule: $0.schule) }) ?? server(url: link, schule: schule) else { throw Fehler.text("WebUntis ist nicht eingerichtet.") }
            let s = try Sitzung(basis: z.basis, schule: z.schule)
            let nutzer = (q?.benutzer).flatMap { $0.isEmpty ? nil : $0 } ?? benutzer.trimmingCharacters(in: .whitespaces)
            let geheim = (q?.schluessel).flatMap { $0.isEmpty ? nil : $0 } ?? schluessel
            if !geheim.isEmpty { _ = try await s.anmeldenMitSchluessel(benutzer: nutzer, schluessel: geheim) }
            else { _ = try await s.rufe("authenticate", ["user": nutzer, "password": passwort, "client": "GutenMorgen"]) }
            let su = Suche(s)
            func liste(_ m: String, _ typ: Int) async -> [UntisElement] {
                ((try? await s.rufe(m)) as? [[String: Any]] ?? []).compactMap { o in
                    guard let n = o["name"] as? String, !n.isEmpty else { return nil }
                    let lang = typ == 2 ? [o["foreName"] as? String, o["longName"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") : (o["longName"] as? String ?? "")
                    return UntisElement(typ: typ, name: n, lang: lang, untisId: (o["id"] as? NSNumber)?.intValue ?? 0)
                }
            }
            su.elemente = await liste("getKlassen", 1) + liste("getTeachers", 2) + liste("getRooms", 4)
            return su
        }

        /// Plan eines Elements für die Woche ab [montag] (Mo–Fr)
        public func plan(_ e: UntisElement, montag: Date) async throws -> [UntisStunde] {
            var id = e.untisId
            if id == 0, let x = elemente.first(where: { $0.id == e.id }) { id = x.untisId }
            guard id != 0 else { throw Fehler.text("\(e.art) „\(e.name)“ gibt es in WebUntis nicht (oder dieses Konto darf sie nicht sehen).") }
            let bis = Zeit.kalender.date(byAdding: .day, value: 4, to: montag) ?? montag
            let o: [String: Any] = ["element": ["id": id, "type": e.typ], "startDate": zahl(montag), "endDate": zahl(bis), "showSubstText": true,
                                    "klasseFields": ["id", "name", "longname"], "teacherFields": ["id", "name", "longname"],
                                    "subjectFields": ["id", "name", "longname"], "roomFields": ["id", "name", "longname"]]
            return stunden(try await s.rufe("getTimetable", ["options": o]))
        }

        public func schliessen() { let s = self.s; Task { _ = try? await s.rufe("logout") } }
    }

    /// Klassen und Lehrkräfte aus der Untis-Sicherung (Räume hat sie nicht)
    static func elemente(sicherung daten: Data) -> [UntisElement] {
        guard let o = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { return [] }
        func liste(_ k: String, _ typ: Int) -> [UntisElement] { (o[k] as? [[String: Any]] ?? []).compactMap { e in (e["name"] as? String).map { UntisElement(typ: typ, name: $0, lang: e["lang"] as? String ?? "") } } }
        return liste("klassen", 1) + liste("lehrer", 2)
    }

    /// Plan eines Elements aus der Untis-Sicherung (nur die gesicherten zwei Wochen)
    static func plan(sicherung daten: Data, element e: UntisElement) -> [UntisStunde] {
        guard let o = try? JSONSerialization.jsonObject(with: daten) as? [String: Any], let plaene = o["plaene"] as? [String: Any],
              let bereich = plaene[e.typ == 1 ? "klassen" : "lehrer"] as? [String: Any],
              let k = bereich.keys.first(where: { $0.lowercased() == e.name.lowercased() }) else { return [] }
        // gleiche Umwandlung wie für die eigenen Stunden
        let huelle: [String: Any] = ["faecher": o["faecher"] ?? [], "plaene": ["lehrer": ["x": bereich[k] ?? []], "klassen": [:]]]
        guard let d = try? JSONSerialization.data(withJSONObject: huelle), let st = ausSicherung(d, kuerzel: "x") else { return [] }
        return st.meine
    }

    /// Montag der Woche, in der [datum] liegt (am Wochenende: der nächsten)
    static func montag(_ datum: Date = Date()) -> Date {
        let k = Zeit.kalender
        var m = k.date(from: k.dateComponents([.yearForWeekOfYear, .weekOfYear], from: datum)) ?? datum
        if [1, 7].contains(k.component(.weekday, from: datum)) { m = k.date(byAdding: .day, value: 7, to: m) ?? m }
        return m
    }
}
