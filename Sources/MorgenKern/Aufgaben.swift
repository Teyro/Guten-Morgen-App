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
}

/// Was das Laden ergibt (wird gespeichert, damit das Öffnen ohne Netz geht)
public struct AufgabenStand: Codable, Hashable, Sendable {
    public var aufgaben: [Aufgabe]
    public var boards: Int
    public var stand: Date
    public init(aufgaben: [Aufgabe], boards: Int, stand: Date = Date()) { self.aufgaben = aufgaben; self.boards = boards; self.stand = stand }

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
        return Freigabe(deviceCode: dc, userCode: uc, seite: URL(string: seite)!, intervall: max(2, (o["interval"] as? Double) ?? 5),
                        ablauf: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 600))
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
        let ziel = farbNorm(farbe)
        var aufgaben: [Aufgabe] = []
        for b in boards.prefix(maxBoards) {
            async let sek = anfrage("/api/sections/board/\(b.id)", token: token)
            async let kar = anfrage("/api/cards/board/\(b.id)", token: token)
            var spalten: [String: String] = [:]
            for s in liste((try await sek).0) { if let id = s["id"] { spalten["\(id)"] = (s["title"] as? String) ?? "" } }
            for k in liste((try await kar).0) {
                guard farbNorm((k["color"] as? String) ?? "") == ziel else { continue }
                let spalte = spalten[k["section_id"].map { "\($0)" } ?? ""] ?? ""
                let kat = kategorie(spalte)
                guard kat >= 0, let id = k["id"] else { continue }
                let inhalt = inhaltAus(k)
                let (titel, beschreibung) = textAus(k, inhalt)
                aufgaben.append(Aufgabe(id: "\(id)", titel: titel, beschreibung: beschreibung, inhalt: inhalt,
                                        geaendert: zeit(k["updated_at"] ?? k["updatedAt"] ?? k["created_at"]),
                                        board: b.id, boardTitel: b.titel, spalte: spalte, kategorie: kat, sort: (k["sort_index"] as? Double) ?? 0))
            }
        }
        return AufgabenStand(aufgaben: aufgaben, boards: boards.count)
    }

    // MARK: Hilfen (öffentlich für Tests)

    static func anfrage(_ pfad: String, methode: String = "GET", koerper: [String: String]? = nil, token: String?) async throws -> (Any?, Int) {
        var kopf = ["Accept": "application/json"]
        if koerper != nil { kopf["Content-Type"] = "application/json" }
        if let t = token { kopf["Authorization"] = "Bearer " + t }
        let (d, s) = try await Netz.daten(URL(string: basis + pfad)!, methode: methode, kopf: kopf, koerper: koerper.flatMap { try? JSONSerialization.data(withJSONObject: $0) }, zeit: 20)
        if token != nil && s == 401 { throw Fehler.verbinden("Die Freigabe ist abgelaufen oder wurde widerrufen – bitte neu verbinden.") }
        if token != nil && s == 403 { throw Fehler.verbinden("Die Freigabe reicht nicht – beim Verbinden „Lesen“ und alle Boards wählen.") }
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

    static func https(_ u: Any?) -> String { let s = (u as? String) ?? ""; return s.lowercased().hasPrefix("http") ? s : "" }

    /// Inhalt der Karte als Blöcke (text, link, file, image, video, audio, plotter, edupool_media)
    public static func inhaltAus(_ k: [String: Any]) -> [Aufgabe.Block] {
        var b: [Aufgabe.Block] = []
        let roh = ((k["blocks"] as? [[String: Any]]) ?? []).sorted { (($0["position"] as? Double) ?? 0) < (($1["position"] as? Double) ?? 0) }
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
