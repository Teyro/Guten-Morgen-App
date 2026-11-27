import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Untis-Sicherung: täglich zentral aus WebUntis erzeugt, liegt im Schul-Ordner („Untis/untis-plan.json“).
/// Rückfall, wenn WebUntis nicht erreichbar ist. Rangfolge überall: Vertretungsplan > von Hand > Untis.
public extension Untis {
    static let sicherungAdresse = "https://cloudfiles.s5586.schuldock.de/public.php/webdav/Untis/untis-plan.json"
    /// Kennung der Freigabe „Schul-Ordner“ (das Passwort trägt jede Lehrkraft selbst ein)
    static let sicherungFreigabe = "mxmLySXtyzC6XFp"

    /// Aus der Nextcloud der Schule (WebDAV, Ordner „Untis“) – mit dem App-Zugang aus den Schul-Vorgaben
    static func sicherungLaden(nextcloud server: String, benutzer: String, passwort: String) async throws -> Data {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("http") { s = "https://" + s }
        let pfad = "/remote.php/dav/files/" + (benutzer.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? benutzer) + "/Untis/untis-plan.json"
        guard let url = URL(string: s + pfad) else { throw Fehler.text("Nextcloud-Adresse ungültig.") }
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.setValue("Basic " + Data("\(benutzer):\(passwort)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (d, a) = try await URLSession.shared.data(for: r)
        let code = (a as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Fehler.text("Nextcloud: App-Passwort falsch.") }
        guard code == 200 else { throw Fehler.text("Untis-Sicherung in der Nextcloud nicht abrufbar (HTTP \(code)).") }
        return d
    }

    static func sicherungLaden(passwort: String) async throws -> Data {
        var r = URLRequest(url: URL(string: sicherungAdresse)!, timeoutInterval: 30)
        r.setValue("Basic " + Data("\(sicherungFreigabe):\(passwort)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (d, a) = try await URLSession.shared.data(for: r)
        let code = (a as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Fehler.text("Schul-Ordner: Passwort falsch.") }
        guard code == 200 else { throw Fehler.text("Untis-Sicherung nicht abrufbar (HTTP \(code)).") }
        return d
    }

    /// Meine Stunden (über das Kürzel) und die Pläne meiner Klassen aus der Sicherung
    static func ausSicherung(_ daten: Data, kuerzel: String) -> UntisStand? {
        guard let o = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let plaene = o["plaene"] as? [String: Any], let lehrer = plaene["lehrer"] as? [String: Any], let klassen = plaene["klassen"] as? [String: Any],
              let schluessel = lehrer.keys.first(where: { $0.lowercased() == kuerzel.lowercased() }) else { return nil }
        let lang = Dictionary((o["faecher"] as? [[String: Any]] ?? []).compactMap { f in (f["name"] as? String).map { ($0, f["lang"] as? String ?? "") } }, uniquingKeysWith: { a, _ in a })
        func min(_ t: Any?) -> Int { let p = (t as? String ?? "").split(separator: ":").compactMap { Int($0) }; return p.count == 2 ? p[0] * 60 + p[1] : 0 }
        func stunden(_ liste: Any?) -> [UntisStunde] {
            (liste as? [[String: Any]] ?? []).map { s in
                let fach = (s["faecher"] as? [String])?.first ?? ""
                let vorher = s["lehrerVorher"] as? [String] ?? []
                return UntisStunde(datum: s["datum"] as? String ?? "", von: min(s["von"]), bis: min(s["bis"]), fach: fach, fachLang: lang[fach] ?? "",
                                   klassen: s["klassen"] as? [String] ?? [], lehrer: vorher.isEmpty ? (s["lehrer"] as? [String] ?? []) : vorher,
                                   raum: (s["raeume"] as? [String] ?? []).joined(separator: ", "), code: s["code"] as? String ?? "")
            }
            .sorted { ($0.datum, $0.von) < ($1.datum, $1.von) }
        }
        let meine = stunden(lehrer[schluessel])
        guard !meine.isEmpty else { return nil }
        var plaeneKlassen: [String: [UntisStunde]] = [:]
        for k in Set(meine.flatMap(\.klassen)) { plaeneKlassen[k] = stunden(klassen[k]) }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let erstellt = (o["erstellt"] as? String).flatMap { f.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()
        return UntisStand(meine: meine, klassen: plaeneKlassen, ich: 0, kuerzel: schluessel, stand: erstellt)
    }

    /// „Mein Stundenplan“ mit Untis zusammenführen: von Hand Eingetragenes bleibt, Untis füllt freie Stunden und
    /// aktualisiert nur Stunden, die noch genau so aussehen, wie Untis sie beim letzten Mal eingetragen hat ([vorher]).
    static func zusammenfuehren(hand: [Unterricht], untis neu: [Unterricht], vorher: [Unterricht]) -> [Unterricht] {
        func gleich(_ a: Unterricht?, _ b: Unterricht?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a.klasse == b.klasse && a.fach == b.fach && a.raum == b.raum
        }
        func schluessel(_ u: Unterricht) -> String { "\(u.tag)|\(u.stunde)" }
        let alt = Dictionary(vorher.map { (schluessel($0), $0) }, uniquingKeysWith: { a, _ in a })
        let untis = Dictionary(neu.map { (schluessel($0), $0) }, uniquingKeysWith: { a, _ in a })
        var ergebnis: [Unterricht] = []
        var gesehen = Set<String>()
        for h in hand {
            let k = schluessel(h); gesehen.insert(k)
            if let a = alt[k], gleich(h, a) {           // noch von Untis → darf sich ändern (oder wegfallen)
                if var u = untis[k] { u.id = h.id; ergebnis.append(u) }
            } else { ergebnis.append(h) }                // von Hand → bleibt
        }
        for u in neu where !gesehen.contains(schluessel(u)) {
            ergebnis.append(u)                           // weiße Fläche
        }
        return ergebnis.sorted { ($0.tag, $0.stunde) < ($1.tag, $1.stunde) }
    }
}
