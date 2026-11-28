import Foundation

/// Chat über den Matrix-Server der Schule (IServ-Messenger, Element): Anmeldung mit den IServ-Zugangsdaten,
/// Räume mit Nachrichten über /sync, Antworten als Text.
/// shortcut: keine Ende-zu-Ende-Verschlüsselung, keine Einladungen, kein Nachladen älterer Nachrichten – nachrüsten, wenn die Schule E2EE erzwingt.
public struct Matrix: Sendable {
    public static let server = "https://s5586.schuldock.de"
    public var token: String
    /// eigene Matrix-ID (@benutzer:server)
    public var ich: String

    public init(token: String, ich: String) { self.token = token; self.ich = ich }

    public struct Nachricht: Hashable, Identifiable, Sendable {
        public var id: String
        public var absender: String
        public var text: String
        public var zeit: Date
        public var verschluesselt = false
        /// Bild, Video, Audio oder Datei (dann ist [text] nur Beschriftung bzw. „📷 Foto“)
        public var anhang: Anhang?
    }

    public struct Anhang: Hashable, Sendable {
        public enum Art: String, Sendable { case bild, video, audio, datei }
        public var art: Art
        public var mxc: String
        public var name: String
        /// eigener Text zum Anhang (nicht nur der Dateiname)
        public var beschriftung = ""
        public var breite = 0, hoehe = 0
        /// Vorschaubild (bei Videos)
        public var vorschau = ""
    }

    public struct Raum: Hashable, Identifiable, Sendable {
        public var id: String
        public var titel = ""
        /// Matrix-ID → Anzeigename
        public var namen: [String: String] = [:]
        /// andere Mitglieder (für Direktchats ohne Raumnamen)
        public var helden: [String] = []
        public var ungelesen = 0
        /// angepinnt = Favorit (Tag „m.favourite“, gleich wie in Element)
        public var angepinnt = false
        public var verschluesselt = false
        public var nachrichten: [Nachricht] = []
        /// Matrix-ID → Profilbild (mxc://…); [avatar] = Bild des Raums
        public var bilder: [String: String] = [:]
        public var avatar = ""

        /// Bild für die Liste: Raumbild, im Direktchat das der anderen Person
        public var bild: String { avatar.isEmpty && helden.count == 1 ? bilder[helden[0]] ?? "" : avatar }

        public var name: String {
            if !titel.isEmpty { return titel }
            let h = helden.map { namen[$0] ?? Matrix.lokal($0) }
            return h.isEmpty ? "Chat" : h.joined(separator: ", ")
        }
        public func name(von id: String) -> String { namen[id] ?? Matrix.lokal(id) }
        public var letzte: Date { nachrichten.last?.zeit ?? .distantPast }
    }

    public enum Fehler: LocalizedError {
        case anmeldung, server(Int, String)
        public var errorDescription: String? {
            switch self {
            case .anmeldung: "Anmeldung am Chat fehlgeschlagen – IServ-Benutzername und Passwort prüfen."
            case .server(let s, let t): "Chat-Server antwortet nicht (HTTP \(s))\(t.isEmpty ? "" : ": \(t)")."
            }
        }
    }

    /// „@vorname.name:s5586.schuldock.de“ → „vorname.name“
    public static func lokal(_ id: String) -> String {
        String(id.dropFirst(id.hasPrefix("@") ? 1 : 0).split(separator: ":").first ?? "")
    }

    // MARK: Netz

    static func anfrage(_ pfad: String, methode: String = "GET", token: String? = nil, koerper: [String: Any]? = nil, frist: TimeInterval = 30) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: server + pfad)!, timeoutInterval: frist)
        r.httpMethod = methode
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let koerper { r.httpBody = try JSONSerialization.data(withJSONObject: koerper); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (d, a) = try await URLSession.shared.data(for: r)
        let s = (a as? HTTPURLResponse)?.statusCode ?? 0
        let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        if s == 401 || s == 403 { throw Fehler.anmeldung }
        guard (200..<300).contains(s) else { throw Fehler.server(s, j["error"] as? String ?? "") }
        return j
    }

    /// IServ-Login ist oft die E-Mail (Schuldock-SSO), der Chat kennt meist nur den Namen davor → nacheinander probieren
    public static func kennungen(_ benutzer: String) -> [[String: String]] {
        let b = benutzer.trimmingCharacters(in: .whitespaces).lowercased()
        guard let at = b.firstIndex(of: "@"), !b.hasPrefix("@") else { return [["type": "m.id.user", "user": b]] }
        return [["type": "m.id.user", "user": String(b[..<at])], ["type": "m.id.thirdparty", "medium": "email", "address": b], ["type": "m.id.user", "user": b]]
    }

    public static func anmelden(benutzer: String, passwort: String) async throws -> Matrix {
        for k in kennungen(benutzer) {
            let j: [String: Any]
            do {
                j = try await anfrage("/_matrix/client/v3/login", methode: "POST", koerper: [
                    "type": "m.login.password", "identifier": k,
                    "password": passwort, "initial_device_display_name": Marke.schule ? "DammAPP" : "GutenMorgen"])
            } catch Fehler.anmeldung { continue } // nur falsche Kennung → nächste; Netzfehler durchreichen
            if let t = j["access_token"] as? String, let u = j["user_id"] as? String { return Matrix(token: t, ich: u) }
        }
        throw Fehler.anmeldung
    }

    /// Ein /sync: [seit] leer = erster Abruf (je Raum die letzten 30 Nachrichten), [warten] ms Long-Poll
    public func sync(seit: String, warten: Int = 0) async throws -> [String: Any] {
        let filter = #"{"room":{"timeline":{"limit":30},"state":{"lazy_load_members":true}}}"#
        var q = "filter=" + filter.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "&timeout=\(warten)"
        if !seit.isEmpty { q += "&since=" + seit.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
        return try await Self.anfrage("/_matrix/client/v3/sync?" + q, token: token, frist: TimeInterval(warten / 1000 + 30))
    }

    public func senden(raum: String, text: String) async throws {
        let txn = "dm\(Int(Date().timeIntervalSince1970 * 1000))"
        _ = try await Self.anfrage("/_matrix/client/v3/rooms/\(Self.pfad(raum))/send/m.room.message/\(txn)", methode: "PUT", token: token,
                                   koerper: ["msgtype": "m.text", "body": text])
    }

    /// Gelesen bis [event] (Lesebestätigung + Marker)
    public func gelesen(raum: String, event: String) async {
        _ = try? await Self.anfrage("/_matrix/client/v3/rooms/\(Self.pfad(raum))/read_markers", methode: "POST", token: token,
                                    koerper: ["m.fully_read": event, "m.read": event])
    }

    /// Anpinnen = Favorit in Matrix (erscheint auch in Element oben)
    public func anpinnen(raum: String, _ an: Bool) async throws {
        _ = try await Self.anfrage("/_matrix/client/v3/user/\(Self.pfad(ich))/rooms/\(Self.pfad(raum))/tags/m.favourite", methode: an ? "PUT" : "DELETE", token: token, koerper: an ? ["order": 0.5] : nil)
    }

    public func abmelden() async { _ = try? await Self.anfrage("/_matrix/client/v3/logout", methode: "POST", token: token, koerper: [:]) }

    /// mxc://server/id → Pfad zum (angemeldeten) Laden; [groesse] > 0 = Vorschaubild
    public static func medienPfad(_ mxc: String, groesse: Int = 0) -> String? {
        let t = mxc.split(separator: "/", omittingEmptySubsequences: true)
        guard mxc.hasPrefix("mxc://"), t.count == 3 else { return nil }
        let s = pfad(String(t[1])), id = pfad(String(t[2]))
        return groesse > 0 ? "/_matrix/client/v1/media/thumbnail/\(s)/\(id)?width=\(groesse)&height=\(groesse)&method=scale"
                           : "/_matrix/client/v1/media/download/\(s)/\(id)"
    }

    /// Bild/Datei laden (mit Anmeldung, wie Element)
    public func medien(_ mxc: String, groesse: Int = 0) async throws -> Data {
        guard let p = Self.medienPfad(mxc, groesse: groesse) else { throw Fehler.server(0, "") }
        var r = URLRequest(url: URL(string: Self.server + p)!, timeoutInterval: 60)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (d, a) = try await URLSession.shared.data(for: r)
        let s = (a as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(s) else { throw Fehler.server(s, "") }
        return d
    }

    /// Anhang aus dem Inhalt einer Nachricht (msgtype m.image/m.video/m.audio/m.file)
    static func anhang(_ c: [String: Any]) -> Anhang? {
        let art: Anhang.Art
        switch c["msgtype"] as? String {
        case "m.image", "m.sticker": art = .bild
        case "m.video": art = .video
        case "m.audio": art = .audio
        case "m.file": art = .datei
        default: return nil
        }
        // shortcut: verschlüsselte Anhänge (content.file) werden nicht entschlüsselt – nur angezeigt, dass es einen gibt
        guard let mxc = c["url"] as? String ?? (c["file"] as? [String: Any])?["url"] as? String else { return nil }
        let body = c["body"] as? String ?? "", datei = c["filename"] as? String ?? ""
        let info = c["info"] as? [String: Any] ?? [:]
        return Anhang(art: art, mxc: mxc, name: datei.isEmpty ? body : datei, beschriftung: !datei.isEmpty && body != datei ? body : "",
                      breite: (info["w"] as? NSNumber)?.intValue ?? 0, hoehe: (info["h"] as? NSNumber)?.intValue ?? 0,
                      vorschau: info["thumbnail_url"] as? String ?? "")
    }

    /// Kurzer Text für Liste, Suche und Mitteilungen
    public static func anhangText(_ a: Anhang) -> String {
        if !a.beschriftung.isEmpty { return a.beschriftung }
        switch a.art {
        case .bild: return "📷 Foto"
        case .video: return "🎬 Video"
        case .audio: return "🎤 Sprachnachricht"
        case .datei: return "📎 " + a.name
        }
    }

    static func pfad(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    // MARK: Lesen

    /// Angepinnte oben, sonst neueste zuerst
    public static func sortiert(_ r: [Raum]) -> [Raum] { r.sorted { ($0.angepinnt ? 1 : 0, $0.letzte) > ($1.angepinnt ? 1 : 0, $1.letzte) } }

    /// Suche in Chat-Namen und Nachrichten (Groß-/Kleinschreibung egal)
    public static func suchen(_ r: [Raum], _ text: String) -> [Raum] {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return r }
        return r.filter { $0.name.localizedCaseInsensitiveContains(t) || $0.nachrichten.contains { $0.text.localizedCaseInsensitiveContains(t) } }
    }

    /// Antwort von /sync in die bekannten Räume einarbeiten; liefert die Räume (neueste zuerst) und das Merkzeichen für den nächsten Abruf
    public static func einarbeiten(_ j: [String: Any], in alt: [Raum]) -> (raeume: [Raum], weiter: String) {
        var raeume = Dictionary(alt.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rooms = j["rooms"] as? [String: Any] ?? [:]
        for id in (rooms["leave"] as? [String: Any] ?? [:]).keys { raeume[id] = nil }
        for (id, wert) in rooms["join"] as? [String: Any] ?? [:] {
            guard let r = wert as? [String: Any] else { continue }
            var raum = raeume[id] ?? Raum(id: id)
            let tl = r["timeline"] as? [String: Any] ?? [:]
            if tl["limited"] as? Bool == true { raum.nachrichten = [] } // Lücke: nur das Neue zeigen
            let ereignisse = ((r["state"] as? [String: Any])?["events"] as? [[String: Any]] ?? []) + (tl["events"] as? [[String: Any]] ?? [])
            for e in ereignisse {
                let typ = e["type"] as? String ?? "", inhalt = e["content"] as? [String: Any] ?? [:]
                switch typ {
                case "m.room.name": raum.titel = inhalt["name"] as? String ?? ""
                case "m.room.encryption": raum.verschluesselt = true
                case "m.room.avatar": raum.avatar = inhalt["url"] as? String ?? ""
                case "m.room.member":
                    if let k = e["state_key"] as? String {
                        if let n = inhalt["displayname"] as? String, !n.isEmpty { raum.namen[k] = n }
                        if let a = inhalt["avatar_url"] as? String { raum.bilder[k] = a }
                    }
                case "m.room.message", "m.room.encrypted":
                    guard let eid = e["event_id"] as? String, !raum.nachrichten.contains(where: { $0.id == eid }) else { continue }
                    let enc = typ == "m.room.encrypted"
                    let anhang = enc ? nil : anhang(inhalt)
                    let text = enc ? "🔒 Verschlüsselte Nachricht – nur in Element/IServ lesbar" : anhang.map(anhangText) ?? (inhalt["body"] as? String ?? "")
                    guard !text.isEmpty else { continue } // gelöscht
                    let ms = (e["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0
                    raum.nachrichten.append(Nachricht(id: eid, absender: e["sender"] as? String ?? "", text: text, zeit: Date(timeIntervalSince1970: ms / 1000), verschluesselt: enc, anhang: anhang))
                default: break
                }
            }
            for e in (r["account_data"] as? [String: Any])?["events"] as? [[String: Any]] ?? [] where e["type"] as? String == "m.tag" {
                raum.angepinnt = ((e["content"] as? [String: Any])?["tags"] as? [String: Any])?["m.favourite"] != nil
            }
            if let h = (r["summary"] as? [String: Any])?["m.heroes"] as? [String] { raum.helden = h }
            if let u = (r["unread_notifications"] as? [String: Any])?["notification_count"] as? Int { raum.ungelesen = u }
            raum.nachrichten = Array(raum.nachrichten.suffix(200))
            raeume[id] = raum
        }
        return (sortiert(Array(raeume.values)), j["next_batch"] as? String ?? "")
    }
}
