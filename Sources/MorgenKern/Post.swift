import Foundation

/// Post und Pakete aus der Home-Assistant-Integration „Briefankündigung“ (dieselbe Quelle wie die App Post & Pakete)
public struct PostStand: Codable, Hashable, Sendable {
    public struct Ereignis: Codable, Hashable, Sendable { public var zeit: Date?; public var text: String; public var ort: String }
    public struct Paket: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var datum: Date
        public var absender: String
        public var name: String
        public var nummer: String
        public var dienst: String
        /// „unterwegs“, „zustellung“, „abholbereit“, „zugestellt“ …
        public var stand: String
        public var erwartet: String
        public var zeitfenster: String
        public var statusText: String
        public var problem: Bool
        public var erledigt: Bool
        public var abholcode: String
        public var abholort: String
        public var abholfrist: String
        public var notiz: String
        public var ereignisse: [Ereignis]
        public var titel: String { name.isEmpty ? (absender.isEmpty ? "Paket" : absender) : name }
        public var zugestellt: Bool { erledigt || stand == "zugestellt" }
    }
    public struct Brief: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var datum: Date
        public var absender: String
        public var bild: Bool
        public var wichtig: Bool
        public var erledigt: Bool
    }
    public var pakete: [Paket]
    public var briefe: [Brief]
    public var stand: Date

    /// Heute erwartet, noch unterwegs, zuletzt zugestellt (14 Tage)
    public func gruppen(jetzt: Date = Date()) -> (heute: [Paket], unterwegs: [Paket], zugestellt: [Paket]) {
        let k = Zeit.kalender
        let offen = pakete.filter { !$0.zugestellt }
        let heute = offen.filter { $0.stand == "zustellung" || $0.stand == "abholbereit" || k.isDate($0.datum, inSameDayAs: jetzt) }
        let unterwegs = offen.filter { p in !heute.contains(p) }.sorted { $0.datum < $1.datum }
        let grenze = jetzt.addingTimeInterval(-14 * 86400)
        let zu = pakete.filter { $0.zugestellt && $0.datum > grenze }.sorted { $0.datum > $1.datum }
        return (heute, unterwegs, zu)
    }

    static func zeit(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for o: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = o
            if let d = iso.date(from: s) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Zeit.kalender.timeZone
        for m in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = m
            if let d = f.date(from: String(s.prefix(m.replacingOccurrences(of: "'", with: "").count))) { return d }
        }
        return nil
    }

    /// Antwort von GET /api/briefankuendigung/briefe
    public static func lesen(_ j: Any, jetzt: Date = Date()) -> PostStand? {
        guard let o = j as? [String: Any], let liste = o["briefe"] as? [[String: Any]] else { return nil }
        func t(_ b: [String: Any], _ k: String) -> String { (b[k] as? String) ?? "" }
        var pakete: [Paket] = [], briefe: [Brief] = []
        for b in liste {
            guard let id = b["id"] as? String, let d = zeit(b["datum"]) else { continue }
            if (b["art"] as? String ?? "brief") == "paket" {
                let ev = (b["ereignisse"] as? [[String: Any]] ?? []).compactMap { e -> Ereignis? in
                    guard let text = e["text"] as? String, !text.isEmpty else { return nil }
                    return Ereignis(zeit: zeit(e["zeit"]), text: text, ort: e["ort"] as? String ?? "")
                }
                pakete.append(Paket(id: id, datum: d, absender: t(b, "absender"), name: t(b, "name"), nummer: t(b, "sendung"),
                                    dienst: t(b, "dienst_name").isEmpty ? t(b, "dienst").uppercased() : t(b, "dienst_name"),
                                    stand: t(b, "stand").isEmpty ? "unterwegs" : t(b, "stand"), erwartet: t(b, "erwartet"), zeitfenster: t(b, "zeitfenster"),
                                    statusText: t(b, "status_text"), problem: b["problem"] as? Bool ?? false, erledigt: b["erledigt"] as? Bool ?? false,
                                    abholcode: t(b, "abholcode"), abholort: t(b, "abholort"), abholfrist: t(b, "abholfrist"), notiz: t(b, "notiz"), ereignisse: ev))
            } else {
                briefe.append(Brief(id: id, datum: d, absender: t(b, "absender"), bild: b["bild"] as? Bool ?? false,
                                    wichtig: b["wichtig"] as? Bool ?? false, erledigt: b["erledigt"] as? Bool ?? false))
            }
        }
        return PostStand(pakete: pakete, briefe: briefe.sorted { $0.datum > $1.datum }, stand: jetzt)
    }
}

extension HomeAssistant {
    private func roh(_ pfad: String, methode: String = "GET", koerper: [String: Any]? = nil) async throws -> Data {
        guard eingerichtet, let url = URL(string: basis + pfad) else { throw URLError(.userAuthenticationRequired) }
        let (d, s) = try await Netz.daten(url, methode: methode, kopf: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"],
                                          koerper: koerper.flatMap { try? JSONSerialization.data(withJSONObject: $0) }, zeit: 20)
        guard (200..<300).contains(s) else { throw URLError(.badServerResponse) }
        return d
    }

    /// Alle Briefe und Pakete (Integration „Briefankündigung“)
    public func post() async throws -> PostStand {
        guard let p = PostStand.lesen(try JSONSerialization.jsonObject(with: try await roh("/api/briefankuendigung/briefe"))) else { throw URLError(.cannotParseResponse) }
        return p
    }
    /// Bild des Umschlags
    public func briefBild(_ id: String) async -> Data? { try? await roh("/api/briefankuendigung/bild/" + id) }
    /// Als angekommen / erledigt markieren (gilt auf allen Geräten)
    public func erledigt(_ id: String, _ ja: Bool) async -> Bool {
        (try? await roh("/api/briefankuendigung/erledigt", methode: "POST", koerper: ["id": id, "erledigt": ja])) != nil
    }
}
