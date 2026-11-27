import Foundation

/// Eine Aufgabe (Karte in deiner Farbe) aus Edupool Boards
public struct Aufgabe: Codable, Hashable, Identifiable, Sendable {
    /// Ein Inhaltsblock der Karte (Text als HTML/Markdown, Link, Datei, Bild …)
    public struct Block: Codable, Hashable, Sendable {
        public var typ: String
        public var text = ""
        public var titel = ""
        public var url = ""
    }
    public var id: String
    public var titel: String
    public var beschreibung: String
    public var inhalt: [Block]
    public var geaendert: Date?
    public var board: String
    public var boardTitel: String
    public var spalte: String
    public var kategorie: Int
    public var sort: Double
    /// Sichtbare Kommentare (für „neuer Kommentar“-Mitteilung); nil bei älteren gespeicherten Ständen
    public var kommentarAnzahl: Int? = nil
}

/// Was das Laden ergibt (wird gespeichert, damit das Öffnen ohne Netz geht)
public struct AufgabenStand: Codable, Hashable, Sendable {
    public var aufgaben: [Aufgabe]
    public var boards: Int
    public var stand: Date
    /// Alle Kartenfarben auf den Boards („#rrggbb“) – zur Auswahl in den Einstellungen
    public var farben: [String]?
    public init(aufgaben: [Aufgabe], boards: Int, stand: Date = Date(), farben: [String]? = nil) { self.aufgaben = aufgaben; self.boards = boards; self.stand = stand; self.farben = farben }

    /// Offene Aufgaben (alles außer „Erledigt“)
    public var offen: [Aufgabe] { aufgaben.filter { !Aufgaben.kategorien[$0.kategorie].erledigt } }
    /// Gruppen in fester Reihenfolge (oder „wichtig“: In Bearbeitung zuerst), leere weggelassen
    public func gruppen(wichtigZuerst: Bool = false) -> [(kategorie: Int, aufgaben: [Aufgabe])] {
        var reihe = Array(Aufgaben.kategorien.indices)
        if wichtigZuerst { reihe.sort { Aufgaben.kategorien[$0].rang < Aufgaben.kategorien[$1].rang } }
        return reihe.compactMap { i in
            let a = aufgaben.filter { $0.kategorie == i }.sorted { ($0.board, $0.sort, $0.titel) < ($1.board, $1.sort, $1.titel) }
            return a.isEmpty ? nil : (i, a)
        }
    }
}

/// Edupool Boards (boards.edupool.cloud): Lese-Freigabe per Code (wie „Verbinden“ im Skript), dann Karten in deiner Farbe
public enum Aufgaben {
    public static let basis = "https://boards.edupool.cloud"
    public static let maxBoards = 12

    public struct Kategorie: Sendable {
        public let name: String, kurz: String, muster: String, symbol: String, rang: Int, erledigt: Bool
    }
    /// Reihenfolge der Prüfung = Reihenfolge der Liste („Zu erledigen“ vor „Erledigt“)
    public static let kategorien: [Kategorie] = [
        Kategorie(name: "Ideen Backlog", kurz: "Ideen", muster: "ideen|backlog|ideas?", symbol: "lightbulb", rang: 3, erledigt: false),
        Kategorie(name: "Zu erledigen", kurz: "To-do", muster: "zu ?erledigen|zu ?tun|to ?do|offen", symbol: "circle", rang: 1, erledigt: false),
        Kategorie(name: "In Bearbeitung", kurz: "Läuft", muster: "bearbeitung|in ?arbeit|doing|in ?progress|laufend", symbol: "circle.lefthalf.filled", rang: 0, erledigt: false),
        Kategorie(name: "Wartet auf Feedback", kurz: "Wartet", muster: "wartet|warten|feedback|rueckmeldung|rückmeldung|review", symbol: "hourglass", rang: 2, erledigt: false),
        Kategorie(name: "Erledigt", kurz: "Erledigt", muster: "erledigt|fertig|done|abgeschlossen|geschafft", symbol: "checkmark.circle.fill", rang: 4, erledigt: true),
    ]

    /// Spaltentitel → Kategorie (−1 = Spalte wird nicht gezeigt)
    public static func kategorie(_ spalte: String) -> Int {
        let t = spalte.lowercased().replacingOccurrences(of: #"[^a-zäöüß]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return kategorien.firstIndex { t.range(of: $0.muster, options: .regularExpression) != nil } ?? -1
    }

    public enum Fehler: Error, LocalizedError {
        case verbinden(String), server(String)
        public var errorDescription: String? { switch self { case .verbinden(let t), .server(let t): return t } }
    }

    // MARK: Verbinden (Geräte-Code)

    public struct Freigabe: Sendable { public let deviceCode: String; public let userCode: String; public let seite: URL; public let intervall: Double; public let ablauf: Date }

    public static func freigabeStarten() async throws -> Freigabe {
        let (d, s) = try await anfrage("/api/auth/cli/device", methode: "POST", koerper: [:], token: nil)
        guard let o = d as? [String: Any], let dc = o["device_code"].map({ "\($0)" }), let uc = o["user_code"].map({ "\($0)" }) else {
            throw Fehler.server("Edupool Boards hat keinen Freigabe-Code geliefert (HTTP \(s)).")
        }
        let seite = ((o["verification_uri"] as? String) ?? basis + "/cli/authorize") + "?user_code=" + (uc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uc)
        return Freigabe(deviceCode: dc, userCode: uc, seite: URL(string: seite)!, intervall: max(2, zahl(o["interval"]) > 0 ? zahl(o["interval"]) : 5),
                        ablauf: Date().addingTimeInterval(zahl(o["expires_in"]) > 0 ? zahl(o["expires_in"]) : 600))
    }

    /// Einmal nachfragen: Token, nil = noch nicht bestätigt
    public static func freigabeAbholen(_ f: Freigabe) async throws -> String? {
        let (d, s) = try await anfrage("/api/auth/cli/device/token", methode: "POST", koerper: ["device_code": f.deviceCode], token: nil)
        let o = d as? [String: Any] ?? [:]
        if let t = o["token"] { return "\(t)" }
        let fehler = (o["error"] as? String) ?? ""
        if fehler == "authorization_pending" || fehler == "slow_down" { return nil }
        if fehler == "expired" { throw Fehler.verbinden("Der Code ist abgelaufen – bitte noch einmal verbinden.") }
        if fehler == "access_denied" || fehler == "denied" { throw Fehler.verbinden("Die Freigabe wurde abgelehnt.") }
        throw Fehler.verbinden("Freigabe nicht erhalten: \(fehler.isEmpty ? "HTTP \(s)" : fehler)")
    }

    // MARK: Laden

    public static func laden(token: String, farbe: String = "#76a5af", boards gewaehlt: [String] = []) async throws -> AufgabenStand {
        let (bd, _) = try await anfrage("/api/boards", token: token)
        let alle = liste(bd).compactMap { b -> (id: String, titel: String, layout: String)? in
            guard let id = b["id"] else { return nil }
            return ("\(id)", (b["title"] as? String) ?? (b["name"] as? String) ?? "Board \(id)", (b["layout_type"] as? String) ?? "")
        }
        let boards = gewaehlt.isEmpty ? alle.filter { $0.layout == "kanban" } : alle.filter { gewaehlt.contains($0.id) }
        // leer = keine Farbe gewählt → alle Karten
        let ziel = farbNorm(farbe)
        var aufgaben: [Aufgabe] = []
        var farben = Set<String>()
        for b in boards.prefix(maxBoards) {
            async let sek = anfrage("/api/sections/board/\(b.id)", token: token)
            async let kar = anfrage("/api/cards/board/\(b.id)", token: token)
            var spalten: [String: String] = [:]
            for s in liste((try await sek).0) { if let id = s["id"] { spalten["\(id)"] = (s["title"] as? String) ?? "" } }
            for k in liste((try await kar).0) {
                let f = farbNorm((k["color"] as? String) ?? "")
                if !f.isEmpty { farben.insert("#" + f) }
                guard ziel.isEmpty || f == ziel else { continue }
                let spalte = spalten[k["section_id"].map { "\($0)" } ?? ""] ?? ""
                let kat = kategorie(spalte)
                guard kat >= 0, let id = k["id"] else { continue }
                let inhalt = inhaltAus(k)
                let (titel, beschreibung) = textAus(k, inhalt)
                aufgaben.append(Aufgabe(id: "\(id)", titel: titel, beschreibung: beschreibung, inhalt: inhalt,
                                        geaendert: zeit(k["updated_at"] ?? k["updatedAt"] ?? k["created_at"]),
                                        board: b.id, boardTitel: b.titel, spalte: spalte, kategorie: kat, sort: zahl(k["sort_index"]),
                                        kommentarAnzahl: Int(zahl(k["visible_comment_count"] ?? k["comment_count"] ?? k["comments_count"]))))
            }
        }
        return AufgabenStand(aufgaben: aufgaben, boards: boards.count, farben: farben.sorted())
    }

    // MARK: Farben der Personen (Board „Medien“)

    /// Kartenfarben des Boards „Medien“ (Stand 27.11.2026) – gelten, bis Edupool selbst Farben liefert
    public static let medienVorgabe = ["Christian S.": "#80a4ae", "Vivi": "#8b7dbe", "Christian N.": "#79a75a", "Jörn": "#db954b", "Michelle": "#7ba7d8"]

    /// Wer welche Farbe hat – aus dem Board „Medien“: Mitglieder mit Farbe, sonst die Farbe der Karten, denen jemand zugewiesen ist.
    /// Liefert die Schnittstelle dazu nichts, bleibt die Liste leer (dann gelten die Farben aus den Einstellungen).
    public static func personenFarben(token: String, board titel: String = "Medien") async -> [String: String] {
        guard let (bd, _) = try? await anfrage("/api/boards", token: token) else { return [:] }
        guard let b = liste(bd).first(where: { (($0["title"] ?? $0["name"]) as? String)?.localizedCaseInsensitiveContains(titel) == true }), let id = b["id"] else { return [:] }
        var m: [String: String] = [:], karten: [String: String] = [:]
        func nimm(_ personen: Any?, farbe: Any? = nil) {
            for p in personen as? [[String: Any]] ?? [] {
                let u = (p["user"] as? [String: Any]) ?? p
                let n = [u["display_name"], u["name"], u["username"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
                let f = farbNorm(((p["color"] ?? p["colour"] ?? u["color"]) as? String) ?? (farbe as? String) ?? "")
                if !n.isEmpty, !f.isEmpty, m[n] == nil { m[n] = "#" + f }
            }
        }
        nimm(b["members"] ?? b["users"])
        if let (d, _) = try? await anfrage("/api/boards/\(id)", token: token), let o = d as? [String: Any] { nimm(o["members"] ?? o["users"] ?? o["participants"]) }
        if let (kd, _) = try? await anfrage("/api/cards/board/\(id)", token: token) {
            for k in liste(kd) {
                // Karte je Person: Titel = Name („Christian S.“, „Vivi“), Kartenfarbe = Farbe der Person
                let f = farbNorm((k["color"] as? String) ?? ""), t = ((k["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !f.isEmpty, t.count <= 25, t.range(of: #"^\p{Lu}[\p{L}.\- ]*$"#, options: .regularExpression) != nil, t.split(separator: " ").count <= 3 { karten[t] = "#" + f }
                nimm(k["assignees"] ?? k["assigned_users"] ?? k["members"], farbe: k["color"])
            }
        }
        // Personen-Karten sind die Farben, die alle sehen – Mitglieds-/Zuweisungsfarben nur, wenn es keine gibt
        return karten.isEmpty ? m : karten
    }

    /// Farbe zu einem Namen nach Vorname (+ Anfang des Nachnamens): „Christian Stake Admin“ → „Christian S.“, „Viviane Haist“ → „Vivi“
    public static func farbe(fuer name: String, in farben: [String: String]) -> String? {
        func woerter(_ s: String) -> [String] { s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0 != "admin" } }
        let n = woerter(name)
        guard let vn = n.first else { return nil }
        var best: (punkte: Int, farbe: String)?
        for (k, f) in farben.sorted(by: { $0.key < $1.key }) {
            let t = woerter(k)
            guard let vk = t.first, vk.count >= 3, vn.hasPrefix(vk) || vk.hasPrefix(vn) else { continue }
            var punkte = 1
            if t.count > 1 {
                // mit Nachname(-Anfang): muss passen, sonst ist es jemand anderes (Christian N. ≠ Christian S.)
                guard n.count > 1, n[1].hasPrefix(t[1]) || t[1].hasPrefix(n[1]) else { continue }
                punkte = 2 + t[1].count
            }
            if punkte > best?.punkte ?? 0 { best = (punkte, f) }
        }
        // Rückfall: voller Nachname („Herr Kurz“ → „Ben Kurz“)
        return best?.farbe ?? farben.sorted(by: { $0.key < $1.key }).first { k, _ in let t = woerter(k); return t.count > 1 && t.last!.count >= 3 && n.contains(t.last!) }?.value
    }

    // MARK: Kommentare (Verlauf einer Karte, antworten braucht beim Verbinden „Schreiben“)

    public struct Kommentar: Hashable, Identifiable, Sendable {
        public var id: String
        public var autor: String
        public var text: String
        public var zeit: Date?
    }

    public static func kommentare(token: String, karte: String) async throws -> [Kommentar] {
        let (d, s) = try await anfrage("/api/cards/\(karte)/comments", token: token)
        guard (200..<300).contains(s) else { throw Fehler.server("Kommentare nicht geladen (HTTP \(s)).") }
        return kommentareAus(d)
    }

    /// Antwort schreiben; 403 = Freigabe nur zum Lesen
    public static func antworten(token: String, karte: String, text: String) async throws {
        let (_, s) = try await anfrage("/api/cards/\(karte)/comments", methode: "POST", koerper: ["content": text], token: token, schreiben: true)
        if s == 403 { throw Fehler.verbinden("Zum Antworten bitte neu verbinden und dabei auch „Boards und Inhalte erstellen, ändern“ anhaken.") }
        guard (200..<300).contains(s) else { throw Fehler.server("Antwort nicht gesendet (HTTP \(s)).") }
    }

    /// Älteste zuerst; Autor aus user/author (Name oder Anzeigename)
    public static func kommentareAus(_ d: Any?) -> [Kommentar] {
        liste(d).compactMap { k in
            let text = reinerText((k["content"] as? String) ?? (k["text"] as? String) ?? (k["body"] as? String) ?? "")
            guard !text.isEmpty else { return nil }
            let u = (k["user"] as? [String: Any]) ?? (k["author"] as? [String: Any]) ?? [:]
            let name = [u["display_name"], u["name"], u["username"], k["author_name"], k["user_name"], k["display_name"]]
                .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            return Kommentar(id: k["id"].map { "\($0)" } ?? UUID().uuidString, autor: name, text: text, zeit: zeit(k["created_at"] ?? k["createdAt"]))
        }.sorted { ($0.zeit ?? .distantPast) < ($1.zeit ?? .distantPast) }
    }

    // MARK: Hilfen (öffentlich für Tests)

    static func anfrage(_ pfad: String, methode: String = "GET", koerper: [String: String]? = nil, token: String?, schreiben: Bool = false) async throws -> (Any?, Int) {
        var kopf = ["Accept": "application/json"]
        if koerper != nil { kopf["Content-Type"] = "application/json" }
        if let t = token { kopf["Authorization"] = "Bearer " + t }
        let (d, s) = try await Netz.daten(URL(string: basis + pfad)!, methode: methode, kopf: kopf, koerper: koerper.flatMap { try? JSONSerialization.data(withJSONObject: $0) }, zeit: 20)
        if token != nil && s == 401 { throw Fehler.verbinden("Die Freigabe ist abgelaufen oder wurde widerrufen – bitte neu verbinden.") }
        if token != nil && s == 403 && !schreiben { throw Fehler.verbinden("Die Freigabe reicht nicht – beim Verbinden „Lesen“ und alle Boards wählen.") }
        return (try? JSONSerialization.jsonObject(with: d), s)
    }

    /// Array direkt oder das erste Array darin ({boards: […]}, {data: […]} …)
    static func liste(_ d: Any?) -> [[String: Any]] {
        if let a = d as? [[String: Any]] { return a }
        if let o = d as? [String: Any] { for v in o.values { if let a = v as? [[String: Any]] { return a } } }
        return []
    }

    public static func farbNorm(_ c: String) -> String {
        var h = c.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3, h.allSatisfy(\.isHexDigit) { h = h.map { "\($0)\($0)" }.joined() }
        return h.count >= 6 && h.prefix(6).allSatisfy(\.isHexDigit) ? String(h.prefix(6)) : ""
    }

    static func zeit(_ w: Any?) -> Date? {
        if let n = w as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        guard let s = w as? String, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Zahl aus JSON (Int, Double, NSNumber oder Text)
    static func zahl(_ w: Any?) -> Double {
        if let d = w as? Double { return d }
        if let i = w as? Int { return Double(i) }
        if let n = w as? NSNumber { return n.doubleValue }
        if let s = w as? String { return Double(s) ?? 0 }
        return 0
    }

    static func https(_ u: Any?) -> String { let s = (u as? String) ?? ""; return s.lowercased().hasPrefix("http") ? s : "" }

    /// Inhalt der Karte als Blöcke (text, link, file, image, video, audio, plotter, edupool_media)
    public static func inhaltAus(_ k: [String: Any]) -> [Aufgabe.Block] {
        var b: [Aufgabe.Block] = []
        let roh = ((k["blocks"] as? [[String: Any]]) ?? []).sorted { zahl($0["position"]) < zahl($1["position"]) }
        for x in roh {
            let typ = (x["block_type"] as? String) ?? (x["type"] as? String) ?? "text"
            let d = x["data"] as? [String: Any] ?? [:]
            func s(_ k: String) -> String { (d[k] as? String) ?? "" }
            switch typ {
            case "text": if !s("text").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { b.append(.init(typ: "text", text: String(s("text").prefix(20000)))) }
            case "link":
                let u = https(d["resolved_url"] ?? d["url"])
                if !u.isEmpty { b.append(.init(typ: "link", text: s("preview_description"), titel: s("title").isEmpty ? s("description") : s("title"), url: u)) }
            case "file": b.append(.init(typ: "file", titel: s("filename").isEmpty ? "Datei" : s("filename")))
            case "image", "drawing": b.append(.init(typ: "image", titel: s("caption").isEmpty ? s("alt_text") : s("caption"), url: https(d["url"])))
            case "video", "audio": b.append(.init(typ: typ, titel: s("title").isEmpty ? s("filename") : s("title"), url: https(d["url"])))
            case "plotter":
                let f = ((d["functions"] as? [[String: Any]]) ?? []).compactMap { ($0["label"] as? String) ?? ($0["expr"] as? String) }
                b.append(.init(typ: "plotter", text: s("prompt"), titel: f.joined(separator: ", ")))
            case "edupool_media": b.append(.init(typ: "edupool_media", text: String((s("fn_kurztext").isEmpty ? s("fn_text") : s("fn_kurztext")).prefix(1000)), titel: s("title").isEmpty ? "Edupool-Medium" : s("title")))
            default:
                let t = s("text").isEmpty ? (s("description").isEmpty ? s("title") : s("description")) : s("text")
                if !t.isEmpty { b.append(.init(typ: "text", text: t)) }
            }
        }
        // Ältere Karten: Inhalt direkt an der Karte
        for f in ["content", "description", "text"] { if let t = k[f] as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty { b.append(.init(typ: "text", text: t)) } }
        let l = https(k["link_url"]); if !l.isEmpty { b.append(.init(typ: "link", url: l)) }
        return b
    }

    /// Titel und kurze Beschreibung (erster Text, der nicht der Titel ist)
    static func textAus(_ k: [String: Any], _ inhalt: [Aufgabe.Block]) -> (String, String) {
        var texte = inhalt.filter { $0.typ == "text" }.map { reinerText($0.text) }.filter { !$0.isEmpty }
        var titel = ((k["title"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        if titel.isEmpty { titel = texte.isEmpty ? (inhalt.first?.titel ?? "Ohne Titel") : String(texte.removeFirst().prefix(80)) }
        if titel.isEmpty { titel = "Ohne Titel" }
        return (titel, String((texte.first { $0 != titel } ?? "").prefix(200)))
    }

    /// Reiner Text aus HTML/Markdown (für Zeilen und Vorlesen)
    public static func reinerText(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"</?(b|strong|i|em|u|s|a|span|code|mark|sub|sup)\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { t = t.replacingOccurrences(of: a, with: b) }
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[#*_`>$]+"#, with: " ", options: .regularExpression)
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}
